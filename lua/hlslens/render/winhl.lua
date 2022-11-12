local M = {}

local fn = vim.fn
local api = vim.api

local utils = require('hlslens.utils')
local winMatchIds = {}

function M.addHighlight(winid, startPos, endPos, hlGroup, priority)
    winid = winid == 0 and api.nvim_get_current_win() or winid
    M.clearHighlight()

    local sLnum, sCol = unpack(startPos)
    local eLnum, eCol = unpack(endPos)
    local pos
    if eLnum == sLnum then
        pos = {{sLnum, sCol, eCol - sCol + 1}}
    else
        pos = {{sLnum, sCol, vim.o.co}}
        for i = 1, eLnum - sLnum - 1 do
            table.insert(pos, {sLnum + i})
        end
        table.insert(pos, {eLnum, 1, eCol})
    end

    local matchids = utils.matchAddPos(hlGroup, pos, priority, winid)
    winMatchIds = {winid, matchids}
    return matchids
end

function M.clearHighlight()
    local winid, matchids = unpack(winMatchIds)
    if matchids then
        if api.nvim_win_is_valid(winid) then
            for _, id in ipairs(matchids) do
                pcall(fn.matchdelete, id, winid)
            end
        end
        winMatchIds = {}
    end
end

return M
