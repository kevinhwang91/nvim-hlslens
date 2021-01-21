local M = {}

local fn = vim.fn
local api = vim.api

local wins = {}

function M.add_hl(winid, start_p, end_p)
    local matchid = wins[winid]
    if matchid and api.nvim_win_is_valid(winid) then
        pcall(fn.matchdelete, matchid)
    end

    local s_lnum, s_col = unpack(start_p)
    local e_lnum, e_col = unpack(end_p)
    local pos
    if e_lnum == s_lnum then
        pos = {{s_lnum, s_col, e_col - s_col + 1}}
    elseif e_lnum - s_lnum > 8 then
        return
    else
        pos = {{s_lnum, s_col, 999}}
        for i = 1, e_lnum - s_lnum - 1 do
            table.insert(pos, {s_lnum + i})
        end
        table.insert(pos, {e_lnum, 1, e_col})
    end

    wins[winid] = fn.matchaddpos('HlSearchCur', pos, 1)
end

function M.delete_win_hl(winid)
    local matchid = wins[winid]
    if matchid and api.nvim_win_is_valid(winid) then
        pcall(fn.matchdelete, matchid)
    end
end
function M.delete_all_win_hl()
    for winid, matchid in pairs(wins) do
        if matchid and api.nvim_win_is_valid(winid) then
            pcall(fn.matchdelete, matchid, winid)
        end
    end
    wins = {}
end

return M
