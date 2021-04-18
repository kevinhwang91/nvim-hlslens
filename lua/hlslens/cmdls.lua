local M = {}
local fn = vim.fn
local api = vim.api

local utils = require('hlslens.utils')
local render = require('hlslens.render')
local index = require('hlslens.index')
local config = require('hlslens.config')

local incsearch

local index_otf
local plist_otf
local cmdl_otf

local last_pat
local last_off
local ns
local timer

local function setup()
    last_pat = ''
    last_off = ''
    ns = api.nvim_create_namespace('hlslens')
    incsearch = config.enable_incsearch
end

local function refresh_lens()
    -- ^R ^[
    fn.feedkeys(string.format('%c%c', 0x12, 0x1b), 'n')
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

local function split_cmdl(cmdl)
    local pat = cmdl
    local off
    local i = 0;
    while true do
        i = cmdl:find('/', i + 1)
        if i == nil then
            break
        end
        if cmdl:sub(i - 1, i - 1) ~= [[\]] then
            pat = cmdl:sub(1, i - 1)
            off = cmdl:sub(i + 1, -1)
            break
        end
    end
    return pat, off
end

local function validate_pat(pat)
    if #pat <= 2 then
        if #pat == 1 or pat:sub(1, 1) == [[\]] or pat == '..' then
            return false
        end
    end
    return true
end

local function jump_inc(forward)
    if plist_otf and #plist_otf > 0 then
        local inc = forward and 1 or -1
        local cnt = #plist_otf
        index_otf = (index_otf + inc + cnt - 1) % cnt + 1
        render.clear(false, 0)
        render.add_lens(plist_otf, true, index_otf, 0)
    end
end

local function is_incsearch()
    return vim.o.is and incsearch
end

function M.search_attach()
    if not is_incsearch() then
        return
    end

    cmdl_otf = ''
    vim.register_keystroke_callback(function(char)
        local b = char:byte(1, -1)
        -- ^G = 0x7
        -- ^T = 0x14
        if b == 7 then
            jump_inc(true)
        elseif b == 20 then
            jump_inc(false)
        end
    end, ns)
end

function M.search_changed()
    if not is_incsearch() then
        return
    end

    local cmdl = fn.getcmdline()
    if cmdl_otf == cmdl then
        return
    else
        cmdl_otf = cmdl
    end

    local pat = split_cmdl(cmdl)

    local bufnr = api.nvim_get_current_buf()
    render.clear(true)

    if validate_pat(pat) then
        timer = utils.killable_defer(timer, function()
            if api.nvim_get_mode().mode ~= 'c' then
                return
            end
            local plist = index.build(bufnr, pat)
            if #plist > 0 then
                render.clear(false, bufnr)
                local pos = fn.searchpos(pat, 'bn')
                local idx, r = utils.bin_search(plist, pos, utils.compare_pos)
                if r ~= 0 then
                    return
                end
                plist_otf, index_otf = plist, idx

                render.add_lens(plist, true, idx, 0)

                refresh_lens()
            else
                clear_lens(bufnr)
            end
        end, 50)
    else
        clear_lens(bufnr)
    end
end

function M.search_detach()
    if is_incsearch() then
        index_otf = nil
        plist_otf = nil
        cmdl_otf = nil
        index.reset_cache()
    end
    -- is_incsearch() may return false but callback is registered
    vim.register_keystroke_callback(nil, ns)

    local cmdl = fn.getcmdline()
    if cmdl == '' then
        cmdl = fn.histget('/')
    end
    local pat, raw_off = split_cmdl(cmdl)
    last_pat, last_off = pat, parse_off(raw_off or '')
end

function M.off(pat)
    if pat ~= last_pat then
        last_off = ''
    end
    return last_off
end

setup()

return M
