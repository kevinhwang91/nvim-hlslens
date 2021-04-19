-- position (1,1)-indexed
local M = {}

local fn = vim.fn

local utils = require('hlslens.utils')

local function nearest_index(plist, c_pos, topl, botl)
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

        if r == -1 then
            local n_idx_lnum = plist[idx + 1][1]
            if topl > idx_lnum then
                idx = idx + 1
                r_idx = 1
            elseif botl < n_idx_lnum then
                r_idx = -1
            elseif mid_lnum < c_lnum then
                idx = idx + 1
                r_idx = 1
            else
                r_idx = -1
            end
        elseif r == 1 then
            local p_idx_lnum = plist[idx - 1][1]
            if topl > p_idx_lnum then
                r_idx = 1
            elseif botl < idx_lnum then
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

function M.nearest_idx_info(plist, pattern)
    local wv = fn.winsaveview()
    local c_pos = {wv.lnum, wv.col + 1}
    local topl, botl = wv.topline, fn.line('w$')
    local idx, r_idx_s = nearest_index(plist, c_pos, topl, botl)

    local i_pos_s = plist[idx]
    local i_pos_e

    if r_idx_s == 0 then
        i_pos_e = fn.searchpos(pattern, 'cen')
    elseif r_idx_s == 1 and idx > 1 then
        i_pos_e = fn.searchpos(pattern, 'cen')
        -- calibrate the nearest index, because index is based on start of the position
        -- prev_i_pos_s < c_pos < i_pos_e < i_pos_s maybe happened
        -- for instance:
        --     text: 1ab|c 2abc
        --     pattern: abc
        --     cursor: |
        -- index is locate at start of second 'abc', but current postion is between start of
        -- previous index postion and end of current index position
        if utils.compare_pos(i_pos_e, i_pos_s) < 0 then
            idx = idx - 1
            r_idx_s = -1
            i_pos_s = plist[idx]
        end
    else
        fn.cursor(i_pos_s)
        i_pos_e = fn.searchpos(pattern, 'cen')
        fn.winrestview(wv)
    end

    local r_idx_e = utils.compare_pos(i_pos_e, c_pos)

    return {idx = idx, r_idxs = {r_idx_s, r_idx_e}, p_start = i_pos_s, p_end = i_pos_e}
end

return M
