local M = {}
local fn = vim.fn
local cmd = vim.cmd
local api = vim.api

local utils = require('hlslens.utils')
local render = require('hlslens.render')
local config = require('hlslens.config')

local DUMMY_POS

local incsearch

local fold_info

local last_cmdl
local cmd_type

local last_pat
local last_off
local last_mul

local ns
local timer

local skip

local on_key

local function refresh_lens()
    -- ^R ^[
    api.nvim_feedkeys(('%c%c'):format(0x12, 0x1b), 'in', false)
end

local function fill_dummy_list(cnt)
    local plist = {}
    for _ = 1, cnt do
        table.insert(plist, DUMMY_POS)
    end
    return plist
end

local function render_lens(bufnr, idx, cnt, pos)
    -- To build a dummy list for compatibility
    local plist = fill_dummy_list(cnt)
    plist[idx] = pos
    render.add_lens(bufnr, plist, true, idx, 0)
    refresh_lens()
end

local function clear_lens(bufnr)
    render.clear(false, bufnr, true)
    refresh_lens()
end

local function parse_off(r_off)
    local _, _, char, sign, num = r_off:find('^([bes]?)([+-]?)(%d*)')
    local off = char
    if off == '' and sign == '' and num ~= '' then
        off = '+'
    end
    if num == '' and sign ~= '' then
        off = off .. sign .. '1'
    else
        off = off .. sign .. num
    end
    return off
end

local function split_cmdl(cmdl, cmdt)
    local pat
    local off = ''
    local mul = false
    local delim = cmdt or '/'
    local i = 0
    local start = i + 1

    while true do
        i = cmdl:find(delim, i + 1)
        if not i then
            pat = cmdl:sub(start)
            break
        end
        if cmdl:sub(i - 1, i - 1) ~= [[\]] then
            -- For example: "/pat/;/foo/+3;?bar"
            if cmdl:sub(i + 1, i + 1) == ';' then
                i = i + 2
                start = i + 1
                delim = cmdl:sub(i, i)
                if i <= #cmdl then
                    mul = true
                end
            else
                pat = cmdl:sub(start, i - 1)
                if pat == '' then
                    pat = fn.getreg('/')
                end
                off = cmdl:sub(i + 1)
                break
            end
        end
    end
    return pat, off, mul
end

local function filter(pat)
    if #pat <= 2 then
        if #pat == 1 or pat:sub(1, 1) == [[\]] or pat == '..' then
            return false
        end
    end
    return true
end

local function close_fold(level, target_line, cur_line)
    if target_line > 0 then
        cur_line = cur_line or api.nvim_win_get_cursor(0)[1]
        level = level or 1
        cmd(('keepj norm! %dgg%dzc%dgg'):format(target_line, level, cur_line))
    end
end

local function do_search(bufnr, delay)
    bufnr = bufnr or api.nvim_get_current_buf()
    timer = utils.killable_defer(timer, function()
        if cmd_type == fn.getcmdtype() then
            local ok, msg = pcall(fn.searchcount, {
                recompute = true,
                maxcount = 100000,
                timeout = 100,
                pattern = last_pat
            })
            if ok then
                local res = msg
                if res.incomplete == 0 and res.total and res.total > 0 then
                    render.clear(false, bufnr)

                    local idx = res.current

                    local pos = fn.searchpos(last_pat, 'bcnW')

                    if fold_info then
                        close_fold(fold_info.level, fold_info.lnum)
                        fold_info.lnum = -1

                        local lnum = pos[1]
                        if fn.foldclosed(lnum) > 0 then
                            fold_info.lnum = lnum
                            fold_info.level = fn.foldlevel(lnum)
                            cmd('norm! zv')
                        end
                    end
                    render_lens(bufnr, idx, res.total, pos)
                else
                    clear_lens(bufnr)
                end
            end
        end
    end, delay or 0)
end

local function incsearch_enabled()
    return vim.o.is and incsearch
end

function M.search_attach()
    if not incsearch_enabled() then
        return
    elseif not utils.jit_enabled() and utils.is_cmdwin() then
        return
    end

    if vim.o.fdo:find('search') and vim.wo.foldenable then
        fold_info = {lnum = -1}
    end

    last_cmdl = ''
    cmd_type = vim.v.event.cmdtype
    on_key(function(char)
        local b1, b2, b3 = char:byte(1, -1)
        if b1 == 0x07 or b1 == 0x14 then
            -- <C-g> = 0x7
            -- <C-t> = 0x14
            if last_off == '' and not last_mul then
                do_search()
            end
        elseif b1 == 0x80 and b2 == 0x6b and (b3 == 0x64 or b3 == 0x75) then
            -- <Up> = 0x80 0x6b 0x75
            -- <Down> = 0x80 0x6b 0x64
            -- TODO https://github.com/kevinhwang91/nvim-hlslens/issues/18
            skip = true
            render.clear(false, 0, true)
        end
    end, ns)
end

function M.search_changed()
    if skip then
        skip = false
        return
    end

    if not incsearch_enabled() then
        return
    end

    local cmdl = fn.getcmdline()
    if last_cmdl == cmdl then
        return
    else
        last_cmdl = cmdl
    end

    last_pat, last_off, last_mul = split_cmdl(cmdl, cmd_type)

    local bufnr = api.nvim_get_current_buf()
    render.clear(true)

    if filter(last_pat) then
        do_search(bufnr, 50)
    else
        timer = utils.killable_defer(timer, function()
            if cmd_type == fn.getcmdtype() then
                clear_lens(bufnr)
            end
        end, 0)
    end
end

function M.search_detach()
    last_off = parse_off(last_off)

    last_cmdl = nil
    cmd_type = nil

    on_key(nil, ns)

    if timer and timer:has_ref() then
        timer:stop()
        if not timer:is_closing() then
            timer:close()
        end
    end

    if fold_info and vim.v.event.abort then
        close_fold(fold_info.level, fold_info.lnum)
    end
    fold_info = nil
end

local function init()
    DUMMY_POS = {1, 1}
    last_pat = ''
    last_off = ''
    last_mul = false
    skip = false
    ns = api.nvim_create_namespace('hlslens')
    incsearch = config.enable_incsearch
    fold_info = nil
    on_key = vim.on_key and vim.on_key or vim.register_keystroke_callback
end

init()

return M
