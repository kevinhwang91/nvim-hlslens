local M = {}
local fn = vim.fn
local cmd = vim.cmd
local api = vim.api

local utils = require('hlslens.utils')
local render = require('hlslens.render')
local config = require('hlslens.config')

local DUMMY_POS = {1, 1}

local incsearch
local should_fold

local pat_otf
local cmdl_otf
local cmd_type

local last_pat
local last_off
local ns
local timer

local function init()
    last_pat = ''
    last_off = ''
    ns = api.nvim_create_namespace('hlslens')
    incsearch = config.enable_incsearch
    should_fold = false
end

local function refresh_lens()
    -- ^R ^[
    fn.feedkeys(('%c%c'):format(0x12, 0x1b), 'n')
end

local function build_dummy_list(cnt)
    local plist = {}
    for _ = 1, cnt do
        table.insert(plist, DUMMY_POS)
    end
    return plist
end

local function render_lens(bufnr, idx, cnt, pos)
    -- To build a dummy list for compatibility
    local plist = build_dummy_list(cnt)
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
    local pat = cmdl
    local off
    local i = 0;
    while true do
        i = cmdl:find(cmdt or '/', i + 1)
        if i == nil then
            break
        end
        if cmdl:sub(i - 1, i - 1) ~= [[\]] then
            pat = cmdl:sub(1, i - 1)
            if pat == '' then
                pat = fn.getreg('/')
            end
            off = cmdl:sub(i + 1, -1)
            break
        end
    end
    return pat, off
end

local function filter(pat)
    if #pat <= 2 then
        if #pat == 1 or pat:sub(1, 1) == [[\]] or pat == '..' then
            return false
        end
    end
    return true
end

local function do_search(bufnr, delay)
    bufnr = bufnr or api.nvim_get_current_buf()
    timer = utils.killable_defer(timer, function()
        if cmd_type == fn.getcmdtype() then
            local res = fn.searchcount({
                recompute = true,
                maxcount = 10000,
                timeout = 100,
                pattern = pat_otf
            })
            if res.incomplete == 0 and res.total and res.total > 0 then
                render.clear(false, bufnr)
                if should_fold then
                    cmd('norm! zv')
                end

                local idx = res.current

                local pos = fn.searchpos(pat_otf, 'bn')
                render_lens(bufnr, idx, res.total, pos)
            else
                clear_lens(bufnr)
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
    end

    if vim.o.fdo:find('search') and vim.wo.foldenable then
        should_fold = true
    end

    cmdl_otf = ''
    cmd_type = vim.v.event.cmdtype
    vim.register_keystroke_callback(function(char)
        local b = char:byte(1, -1)
        -- ^G = 0x7
        -- ^T = 0x14
        if b == 0x07 or b == 0x14 then
            do_search()
        end
    end, ns)
end

function M.search_changed()
    if not incsearch_enabled() or fn.bufname() == '[Command Line]' then
        return
    end

    local cmdl = fn.getcmdline()
    if cmdl_otf == cmdl then
        return
    else
        cmdl_otf = cmdl
    end

    pat_otf = split_cmdl(cmdl, cmd_type)

    local bufnr = api.nvim_get_current_buf()
    render.clear(true)

    if filter(pat_otf) then
        do_search(bufnr, 50)
    else
        clear_lens(bufnr)
    end
end

function M.search_detach()
    local cmdl = fn.getcmdline()
    if cmdl == '' then
        cmdl = fn.getreg('/')
    end
    local pat, raw_off = split_cmdl(cmdl, cmd_type)
    last_pat, last_off = pat, parse_off(raw_off or '')

    pat_otf = nil
    cmdl_otf = nil
    cmd_type = nil
    should_fold = false

    vim.register_keystroke_callback(nil, ns)
end

function M.off(pat)
    if pat ~= last_pat then
        last_off = ''
    end
    return last_off
end

init()

return M
