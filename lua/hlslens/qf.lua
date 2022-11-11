local fn = vim.fn
local api = vim.api
local cmd = vim.cmd

local position = require('hlslens.position')


---@class HlslensQuickfix
local QF = {}

local function setLocList(what, action)
    return fn.setloclist(0, {}, action or ' ', what)
end

local function setQfList(what, action)
    return fn.setqflist({}, action or ' ', what)
end

local function getLocList(winid, what)
    return fn.getloclist(winid or 0, what)
end

local function getQfList(what)
    return fn.getqflist(what)
end

local function qftf(qinfo)
    local qfBufnr = api.nvim_get_current_buf()
    local getListFunc = qinfo.quickfix == 1 and getQfList or function(what0)
        return getLocList(qinfo.winid, what0)
    end
    local qfList = getListFunc({id = qinfo.id, items = 0})
    local id, items = qfList.id, qfList.items
    local res = {}
    for i = qinfo.start_idx, qinfo.end_idx do
        local e = items[i]
        table.insert(res, e.text)
    end
    vim.schedule(function()
        if vim.bo[qfBufnr].bt == 'quickfix' and getListFunc({id = 0}).id == id then
            api.nvim_buf_call(qfBufnr, function()
                cmd('syntax clear')
            end)
        end
    end)
    return res
end

---
---@param isLocation? boolean
function QF.exportRanges(isLocation)
    local bufnr = api.nvim_get_current_buf()
    local pos = position:compute(bufnr)
    if not pos or #pos.sList == 0 then
        return false
    end
    local sList, eList = pos.sList, pos.eList
    local cnt = #sList
    local startLnum, endLnum = sList[1][1], sList[cnt][1]
    local lines = api.nvim_buf_get_lines(bufnr, startLnum - 1, endLnum, true)
    local items = {}
    for i = 1, cnt do
        local lnum, col = sList[i][1], sList[i][2]
        local text = lines[lnum - startLnum + 1]
        table.insert(items, {
            bufnr = bufnr,
            lnum = lnum,
            col = col,
            end_lnum = eList[i][1],
            end_col = eList[i][2] + 1,
            text = (#text > 300 and text:sub(1, 300) .. ' ⋯' or text):gsub('%z', '^@')
        })
    end
    local idx = pos.nearestIdx
    if not idx then
        local cursor = api.nvim_win_get_cursor(0)
        local curPos = {cursor[1], cursor[2] + 1}
        pos:buildInfo(curPos, fn.line('w0'), fn.line('w$'))
        idx = pos.nearestIdx
    end
    local what = {
        items = items,
        idx = pos.nearestIdx,
        title = ('hlslens bufnr: %d, pattern: %s'):format(bufnr, pos.pattern),
        quickfixtextfunc = qftf
    }
    local action
    local title = isLocation and getLocList(0, {title = 1}).title or getQfList({title = 1}).title
    if title:match('^hlslens bufnr:') then
        action = 'r'
    end
    if isLocation then
        setLocList(what, action)
    else
        setQfList(what, action)
    end
    return true
end

return QF
