local M = {}
local fn = vim.fn
local api = vim.api
local cmd = vim.cmd

local utils = require('hlslens.utils')
local config = require('hlslens.config')

local winhl = require('hlslens.render.winhl')
local extmark = require('hlslens.render.extmark')
local floatwin = require('hlslens.render.floatwin')

local virt_priority
local nearest_only
local nearest_float_when
local float_shadow_blend

local float_virt_id

local gutter_size

local function init()
    virt_priority = config.virt_priority
    nearest_only = config.nearest_only
    nearest_float_when = config.nearest_float_when
    float_shadow_blend = config.float_shadow_blend

    cmd([[
        hi default link HlSearchNear IncSearch
        hi default link HlSearchLens WildMenu
        hi default link HlSearchLensNear IncSearch
        hi default link HlSearchFloat IncSearch
    ]])

    if vim.o.termguicolors then
        local tbl_hi_cmd = {'hi HlSearchFloat', 'blend=0'}
        for k, v in pairs(utils.hl_attrs('HlSearchFloat')) do
            table.insert(tbl_hi_cmd,
                ('%s=%s'):format(k, type(v) == 'table' and table.concat(v, ',') or v))
        end
        cmd(table.concat(tbl_hi_cmd, ' '))
    end
end

local function enough_size4virt(winid, lnum, line_wid, t_len)
    local end_vcol = utils.vcol(winid, {lnum, '$'}) - 1
    local re_vcol
    if vim.wo[winid].wrap then
        re_vcol = line_wid - (end_vcol - 1) % line_wid - 1
    else
        re_vcol = math.max(0, line_wid - end_vcol)
    end
    return re_vcol > t_len
end

local function update_floatwin(winid, pos, line_wid, g_size, text)
    local width, height = api.nvim_win_get_width(winid), api.nvim_win_get_height(winid)
    local f_col = utils.vcol(winid, pos) % line_wid + g_size - 1
    text = vim.trim(text)
    if vim.o.termguicolors then
        local f_win, f_buf = floatwin.update(height, 0, width)
        vim.wo[f_win].winbl = float_shadow_blend
        local padding = (' '):rep(math.min(f_col, width - #text) - 1)
        local chunks = {{padding, 'Ignore'}, {text, 'HlSearchFloat'}}
        float_virt_id = extmark.set_virt_eol(f_buf, 0, chunks, virt_priority, float_virt_id)
    else
        local f_win, f_buf = floatwin.update(height, f_col, #text)
        vim.wo[f_win].winhl = 'Normal:HlSearchFloat'
        api.nvim_buf_set_lines(f_buf, 0, 1, true, {text})
    end
end

-- Add lens template, can be overrided by `override_lens`
-- @param bufnr (number) buffer number
-- @param plist (table) (1,1)-indexed position list
-- @param nearest (boolean) whether nearest lens
-- @param idx (number) nearest index in the plist
-- @param r_idx (number) relative index, negative means before current position, positive means after
function M.add_lens(bufnr, plist, nearest, idx, r_idx)
    if type(config.override_lens) == 'function' then
        -- export render module for hacking :)
        return config.override_lens(M, plist, nearest, idx, r_idx)
    end
    local sfw = vim.v.searchforward == 1
    local indicator, text, chunks
    local abs_r_idx = math.abs(r_idx)
    if abs_r_idx > 1 then
        indicator = ('%d%s'):format(abs_r_idx, sfw ~= (r_idx > 1) and 'N' or 'n')
    elseif abs_r_idx == 1 then
        indicator = sfw ~= (r_idx == 1) and 'N' or 'n'
    else
        indicator = ''
    end

    local lnum, col = unpack(plist[idx], 1, 2)
    if nearest then
        local cnt = #plist
        if indicator ~= '' then
            text = ('[%s %d/%d]'):format(indicator, idx, cnt)
        else
            text = ('[%d/%d]'):format(idx, cnt)
        end
        chunks = {{' ', 'Ignore'}, {text, 'HlSearchLensNear'}}
    else
        text = ('[%s %d]'):format(indicator, idx)
        chunks = {{' ', 'Ignore'}, {text, 'HlSearchLens'}}
    end
    M.set_virt(bufnr, lnum - 1, col - 1, chunks, nearest)
end

function M.set_virt(bufnr, lnum, col, chunks, nearest)
    local ex_lnum, ex_col = lnum + 1, col + 1
    local text = ''
    for _, chunk in ipairs(chunks) do
        text = text .. chunk[1]
    end
    if nearest and (nearest_float_when == 'auto' or nearest_float_when == 'always') then
        local g_size = gutter_size or utils.gutter_size(0)
        local per_line_wid = api.nvim_win_get_width(0) - g_size
        if nearest_float_when == 'always' then
            update_floatwin(0, {ex_lnum, ex_col}, per_line_wid, g_size, text)
        else
            if enough_size4virt(0, ex_lnum, per_line_wid, #text) then
                extmark.set_virt_eol(bufnr, lnum, chunks, virt_priority)
                floatwin.close()
            else
                update_floatwin(0, {ex_lnum, ex_col}, per_line_wid, g_size, text)
            end
        end
    else
        extmark.set_virt_eol(bufnr, lnum, chunks, virt_priority)
    end
end

function M.add_win_hl(winid, start_p, end_p)
    winhl.add_hl(winid, start_p, end_p, 'HlSearchNear')
end

function M.do_lens(plist, nearest, idx, r_idx)
    local pos_len = #plist
    local idx_lnum = plist[idx][1]

    local tbl_render = {}

    if not nearest_only and not nearest then
        local t0, b0
        local p_pos, n_pos = plist[math.max(1, idx - 1)], plist[math.min(pos_len, idx + 1)]
        -- TODO just relieve foldclosed behavior, can't solve the issue perfectly
        if vim.wo.foldenable then
            t0, b0 = math.min(p_pos[1], fn.line('w0')), math.max(n_pos[1], fn.line('w$'))
        else
            t0, b0 = p_pos[1], n_pos[1]
        end
        local w_hei = api.nvim_win_get_height(0)
        local top_limit = math.max(0, t0 - w_hei + 1)
        local bot_limit = math.min(api.nvim_buf_line_count(0), b0 + w_hei - 1)

        local i_lnum, rel_idx
        local last_hl_lnum = 0
        local top_r_idx = math.min(r_idx, 0)
        for i = math.max(idx - 1, 0), 1, -1 do
            i_lnum = plist[i][1]
            if i_lnum < top_limit then
                break
            end
            if last_hl_lnum == i_lnum then
                goto continue
            end
            last_hl_lnum = i_lnum
            rel_idx = i - idx + top_r_idx
            tbl_render[i_lnum] = {i, rel_idx}
            ::continue::
        end

        last_hl_lnum = idx_lnum
        local bot_r_idx = math.max(r_idx, 0)
        local last_i
        for i = idx + 1, pos_len do
            last_i = i
            i_lnum = plist[i][1]
            if last_hl_lnum == i_lnum then
                goto continue
            end
            last_hl_lnum = i_lnum
            rel_idx = i - 1 - idx + bot_r_idx
            tbl_render[plist[i - 1][1]] = {i - 1, rel_idx}
            if i_lnum > bot_limit then
                break
            end
            ::continue::
        end

        if last_i and i_lnum <= bot_limit then
            rel_idx = last_i - idx + bot_r_idx
            tbl_render[i_lnum] = {last_i, rel_idx}
        end
        tbl_render[idx_lnum] = nil
    end

    local bufnr = api.nvim_get_current_buf()
    gutter_size = utils.gutter_size(0)
    extmark.clear_buf(bufnr)
    M.add_lens(bufnr, plist, true, idx, r_idx)
    for _, idxs in pairs(tbl_render) do
        M.add_lens(bufnr, plist, false, idxs[1], idxs[2])
    end
    gutter_size = false
end

function M.clear(hl, bufnr, floated)
    if hl then
        winhl.clear_hl()
    end
    if bufnr then
        extmark.clear_buf(bufnr)
    end
    if floated then
        floatwin.close()
    end
end

function M.clear_all()
    floatwin.close()
    winhl.clear_hl()
    extmark.clear_all_buf()
end

init()

return M
