local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local index = require('hlslens.index')
local utils = require('hlslens.utils')
local vtext = require('hlslens.vtext')
local winhl = require('hlslens.winhl')
local config = require('hlslens').get_config()

local ns
local hl_off
local bufs

local function double_check_hloff()
    if vim.v.hlsearch == 0 then
        if not hl_off then
            hl_off = true
        else
            hl_off = false
            return true
        end
    else
        hl_off = false
    end
    return false
end

local function render_buf_lens(pos_list, idx, r_idx, top_limit, bot_limit)
    local pos_len = #pos_list
    local idx_lnum = pos_list[idx][1]
    vtext.clear_buf(0, ns)

    local i_lnum, rel_idx
    local last_hl_lnum = 0
    local top_r_idx = math.min(r_idx, 0)
    for i = math.max(idx - 1, 0), 1, -1 do
        i_lnum = pos_list[i][1]
        if i_lnum < top_limit then
            break
        end
        if last_hl_lnum == i_lnum then
            goto continue
        end
        last_hl_lnum = i_lnum
        rel_idx = i - idx + top_r_idx
        vtext.add_line_lens(i_lnum, 'a', i, rel_idx, pos_len, ns)
        ::continue::
    end

    last_hl_lnum = idx_lnum
    local bot_r_idx = math.max(r_idx, 0)
    local last_i = 0
    for i = idx + 1, pos_len do
        last_i = i
        i_lnum = pos_list[i][1]
        if last_hl_lnum == i_lnum then
            goto continue
        end
        last_hl_lnum = i_lnum
        rel_idx = i - 1 - idx + bot_r_idx
        if rel_idx == 0 then
            goto continue
        end
        vtext.add_line_lens(pos_list[i - 1][1], 'b', i - 1, rel_idx, pos_len, ns)
        if i_lnum > bot_limit then
            break
        end
        ::continue::
    end
    if last_i > idx and i_lnum <= bot_limit then
        rel_idx = last_i - idx + bot_r_idx
        vtext.add_line_lens(i_lnum, 'b', last_i, rel_idx, pos_len, ns)
    end

    vtext.add_line_lens(idx_lnum, 'c', idx, r_idx, pos_len, ns)
end

local function locate_pos(pos_list, c_pos, top_limit, bot_limit)
    local idx, ret = utils.bin_search(pos_list, c_pos, utils.compare_pos)
    local r_idx = 0
    local idx_lnum = pos_list[idx][1]

    if idx == 1 and ret == -1 then
        if bot_limit < idx_lnum then
            return
        end
        r_idx = 1
    elseif idx == #pos_list and ret == 1 then
        if top_limit > idx_lnum then
            return
        end
        r_idx = -1
    else
        local mid_lnum = math.ceil((idx_lnum + pos_list[idx + ret][1] - 1) / 2)
        local c_lnum = c_pos[1]
        local win_info = fn.getwininfo(api.nvim_get_current_win())[1]
        local topline, botline = win_info.topline, win_info.botline

        if ret == 1 then
            local n_idx_lnum = pos_list[idx + 1][1]
            if bot_limit < n_idx_lnum and top_limit > idx_lnum then
                return
            end
            if topline > idx_lnum then
                idx = idx + 1
                r_idx = 1
            elseif botline < n_idx_lnum then
                r_idx = -1
            elseif mid_lnum < c_lnum then
                idx = idx + 1
                r_idx = 1
            else
                r_idx = -1
            end
        elseif ret == -1 then
            local p_idx_lnum = pos_list[idx - 1][1]
            if bot_limit < idx_lnum and top_limit > p_idx_lnum then
                return
            end
            if topline > p_idx_lnum then
                r_idx = 1
            elseif botline < idx_lnum then
                idx = idx - 1
                r_idx = -1
            elseif mid_lnum < c_lnum then
                r_idx = 1
            else
                idx = idx - 1
                r_idx = -1
            end
        end
    end
    return idx, r_idx
end

local function init()
    ns = vtext.create_namespace()
    hl_off = false
    bufs = {}
end

local function reset()
    M.disable()
    M.enable()
end

function M.enable()
    api.nvim_exec([[
        augroup HlSearchLens
            autocmd!
            autocmd CmdlineLeave [/\?] lua require('hlslens.main').listen_searched()
        augroup END
        ]], false)
end

function M.disable()
    for bufnr in pairs(bufs) do
        if fn.bufexists(bufnr) == 1 then
            vtext.clear_buf(bufnr, ns)
        end
    end

    winhl.delete_all_win_hl()
    bufs = {}
    hl_off = false
    cmd('autocmd! HlSearchLens')
    config.started = false
end

function M.refresh_lens()
    if double_check_hloff() then
        reset()
        return
    end
    local bufnr = api.nvim_get_current_buf()
    local bt = vim.bo.buftype
    if fn.expand('%') == '' or bt == 'terminal' or bt == 'quickfix' or bt == 'prompt' then
        return
    end

    local pattern = fn.getreg('/')
    local pos_list
    local bcache = bufs[bufnr] or {}
    if bcache.changedtick == vim.b.changedtick and bcache.pattern == pattern then
        pos_list = bcache.index
    else
        pos_list = index.build_index(pattern)
        if not pos_list then
            return
        end
        bcache = {index = pos_list, changedtick = vim.b.changedtick, pattern = pattern}
        bufs[bufnr] = bcache
    end

    local winid = api.nvim_get_current_win()
    local pos_len = #pos_list
    if pos_len == 0 then
        vtext.clear_buf(0, ns)
        winhl.delete_win_hl(winid)
        return
    end

    local c_lnum, c_col = unpack(fn.getpos('.'), 2, 3)
    local c_pos = {c_lnum, c_col}

    local win_height = api.nvim_win_get_height(0)
    local top_limit = math.max(0, c_lnum - win_height + 1)
    local bot_limit = math.min(api.nvim_buf_line_count(0), c_lnum + win_height - 1)

    local idx, r_idx = locate_pos(pos_list, c_pos, top_limit, bot_limit)
    if not idx then
        vtext.clear_buf(0, ns)
        winhl.delete_win_hl(winid)
        return
    end
    if idx == bcache.idx and r_idx == bcache.r_idx and not config.calm_down then
        return
    end
    bcache.idx, bcache.r_idx = idx, r_idx

    local idx_pos = pos_list[idx]
    local ret = utils.compare_pos(c_pos, idx_pos)
    local idx_pos_end
    if ret > 0 then
        cmd(string.format([[noautocmd call cursor(%d, %d)]], unpack(idx_pos)))
        idx_pos_end = fn.searchpos(pattern, 'cen')
        cmd(string.format([[keepjumps noautocmd call cursor(%d, %d)]], unpack(c_pos)))
    else
        idx_pos_end = fn.searchpos(pattern, 'cen')
    end

    if config.calm_down and (ret < 0 or utils.compare_pos(c_pos, idx_pos_end) > 0) then
        vim.defer_fn(function()
            cmd('nohlsearch')
            reset()
        end, 0)
        return
    end
    winhl.add_hl(winid, idx_pos, idx_pos_end)

    render_buf_lens(pos_list, idx, r_idx, top_limit, bot_limit)
end

function M.start()
    if #bufs == 0 then
        api.nvim_exec([[
        augroup HlSearchLens
            autocmd! CmdlineLeave :
            autocmd! CursorMoved,CursorMovedI *
            autocmd CmdlineLeave : lua require('hlslens.main').listen_nohlseach()
            autocmd CursorMoved,CursorMovedI * lua require('hlslens.main').refresh_lens()
        augroup END
        ]], false)
    end
    config.started = true
    vim.defer_fn(M.refresh_lens, 0)
end

function M.listen_searched()
    if vim.v.event.abort or not vim.o.hlsearch then
        return
    end
    M.start()
end

function M.listen_nohlseach()
    if vim.v.event.abort then
        return
    end
    if string.match('nohlsearch', fn.getcmdline()) then
        reset()
    end
end

init()

return M
