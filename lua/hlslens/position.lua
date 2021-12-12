local M = {}

local api = vim.api
local fn = vim.fn

local utils = require('hlslens.utils')

local bufs
local jit_enabled
local range_module
local limit

local function build_cache(bufnr, pattern, plist)
    local c = {
        plist = plist or {},
        changedtick = api.nvim_buf_get_changedtick(bufnr),
        pattern = pattern
    }
    if not bufs[bufnr] then
        bufs.cnt = bufs.cnt + 1
    end
    bufs[bufnr] = c
    return c
end

function M.hit_cache(bufnr, pattern, n_idx, nr_idx)
    local c = bufs[bufnr]
    return c and pattern == c.pattern and n_idx == c.n_idx and nr_idx == c.nr_idx and
               vim.v.searchforward == c.sfw
end

function M.update_cache(bufnr, pattern, n_idx, nr_idx)
    local c = bufs[bufnr]
    c.pattern, c.n_idx, c.nr_idx, c.sfw = pattern, n_idx, nr_idx, vim.v.searchforward
end

-- make sure run under current buffer
function M.build(cur_bufnr, pat)
    cur_bufnr = cur_bufnr or api.nvim_get_current_buf()
    local c = bufs[cur_bufnr] or {}
    if c.changedtick == api.nvim_buf_get_changedtick(cur_bufnr) and c.pattern == pat then
        return c.plist
    end

    if not jit_enabled then
        if not range_module.valid(pat) or vim.bo.bt == 'quickfix' or utils.is_cmdwin() then
            return build_cache(cur_bufnr, pat, {start_pos = {}, end_pos = {}}).plist
        end
    end

    -- fast and simple way to prevent memory leaking :)
    if bufs.cnt > 5 then
        bufs = {cnt = 0}
    end

    local start_pos_list, end_pos_list = range_module.build_list(pat, limit)

    local plist = {start_pos = start_pos_list, end_pos = end_pos_list}
    local cache = build_cache(cur_bufnr, pat, plist)
    return cache.plist
end

function M.clear()
    bufs = {cnt = 0}
end

local function nearest_index(plist, c_pos, topl, botl)
    local splist = plist.start_pos
    local idx, r = utils.bin_search(splist, c_pos, utils.compare_pos)
    local another_idx = idx - r
    local r_idx = r

    if r ~= 0 and another_idx <= #splist and another_idx >= 1 then
        local idx_lnum = splist[idx][1]
        local another_idx_lnum = splist[idx - r][1]
        local mid_lnum = math.ceil((idx_lnum + another_idx_lnum) / 2) - 1
        local c_lnum = c_pos[1]

        -- fn.line('w$') may be expensive while scrolling down
        topl = topl or fn.line('w0')
        if r == -1 then
            if topl > idx_lnum then
                r_idx = 1
            elseif mid_lnum < c_lnum and (botl or fn.line('w$')) >= another_idx_lnum then
                r_idx = 1
            end
        else
            if topl <= another_idx_lnum then
                if mid_lnum >= c_lnum or (botl or fn.line('w$')) < idx_lnum then
                    r_idx = -1
                end
            end
        end
        if r_idx ~= r then
            idx = idx - r
        end

        if r_idx == 1 and idx > 1 then
            -- calibrate the nearest index, because index is based on start of the position
            -- c_pos <= prev_i_pos_e < i_pos_s maybe happened
            -- for instance:
            --     text: 1ab|c 2abc
            --     pattern: abc
            --     cursor: |
            -- nearest index locate at start of second 'abc',
            -- but current postion is between start of
            -- previous index postion and end of current index position
            if utils.compare_pos(c_pos, plist.end_pos[idx - 1]) <= 0 then
                idx = idx - 1
                r_idx = -1
            end
        end
    end

    return idx, r_idx
end

function M.nearest_idx_info(plist)
    local wv = fn.winsaveview()
    local c_pos = {wv.lnum, wv.col + 1}
    local topl = wv.topline
    local idx, r_idx_s = nearest_index(plist, c_pos, topl)
    local pos_s = plist.start_pos[idx]
    local pos_e = plist.end_pos[idx]
    local r_idx_e = utils.compare_pos(pos_e, c_pos)
    return {idx = idx, r_idx_s = r_idx_s, r_idx_e = r_idx_e, pos_s = pos_s, pos_e = pos_e}
end

local function init()
    bufs = {cnt = 0}
    jit_enabled = utils.jit_enabled()
    limit = jit_enabled and 100000 or 10000
    range_module = jit_enabled and require('hlslens.range.regex') or require('hlslens.range.qf')
end

init()

return M
