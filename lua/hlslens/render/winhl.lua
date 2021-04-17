local M = {}

local fn = vim.fn
local api = vim.api

local utils = require('hlslens.utils')
local win_mids = {}

function M.add_hl(winid, start_p, end_p, higroup)
    winid = winid == 0 and api.nvim_get_current_win() or winid
    M.clear_hl()

    local s_lnum, s_col = unpack(start_p)
    local e_lnum, e_col = unpack(end_p)
    local pos
    if e_lnum == s_lnum then
        pos = {{s_lnum, s_col, e_col - s_col + 1}}
    else
        pos = {{s_lnum, s_col, vim.o.co}}
        for i = 1, e_lnum - s_lnum - 1 do
            table.insert(pos, {s_lnum + i})
        end
        table.insert(pos, {e_lnum, 1, e_col})
    end

    local matchids = utils.matchaddpos(higroup, pos, 1, winid)
    win_mids = {winid, matchids}
    return matchids
end

function M.clear_hl()
    local winid, matchids = unpack(win_mids)
    if matchids then
        if api.nvim_win_is_valid(winid) then
            for _, id in ipairs(matchids) do
                pcall(fn.matchdelete, id, winid)
            end
        end
        win_mids = {}
    end
end

return M
