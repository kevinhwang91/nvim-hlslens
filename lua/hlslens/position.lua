-- position (1,1)-indexed
local M = {}

local fn = vim.fn

local utils = require('hlslens.utils')

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

return M
