-- position (1,1)-indexed
local M = {}

local api = vim.api
local fn = vim.fn

local utils = require('hlslens.utils')

local function nearest_index(plist, c_pos)
    local idx, r = utils.bin_search(plist, c_pos, utils.compare_pos)
    local r_idx = 0
    local idx_lnum = plist[idx][1]

    if idx == 1 and r == 1 then
        r_idx = 1
    elseif idx == #plist and r == -1 then
        r_idx = -1
    else
        local mid_lnum = math.ceil((idx_lnum + plist[idx - r][1]) / 2) - 1
        local c_lnum = c_pos[1]
        local topline, botline = fn.line('w0'), fn.line('w$')

        if r == -1 then
            local n_idx_lnum = plist[idx + 1][1]
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
        elseif r == 1 then
            local p_idx_lnum = plist[idx - 1][1]
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

local function get_cursor()
    local lnum, col = unpack(api.nvim_win_get_cursor(0))
    col = col + 1
    return {lnum, col}
end

function M.nearest_idx_info(plist, pattern)
    local c_pos = get_cursor()
    local idx, r_idx_s = nearest_index(plist, c_pos)

    local i_pos_s, i_pos_e = plist[idx], fn.searchpos(pattern, 'cenW')

    if r_idx_s >= 0 then
        if r_idx_s == 1 and idx > 1 then
            if utils.compare_pos(i_pos_e, i_pos_s) < 0 then
                idx = idx - 1
                r_idx_s = -1
                i_pos_s = plist[idx]
            end
        end
    else
        if idx == #plist then
            if utils.compare_pos(i_pos_e, {0, 0}) == 0 then
                i_pos_e = fn.searchpos(pattern, 'ben')
            end
        else
            local ni_pos_s = plist[idx + 1]
            if utils.compare_pos(i_pos_e, ni_pos_s) >= 0 then
                i_pos_e = fn.searchpos(pattern, 'ben')
            end
        end
    end

    local r_idx_e = utils.compare_pos(i_pos_e, c_pos)

    return {idx = idx, r_idxs = {r_idx_s, r_idx_e}, p_start = i_pos_s, p_end = i_pos_e}
end

return M
