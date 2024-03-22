local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local render = require('hlslens.render')
local utils = require('hlslens.utils')
local event = require('hlslens.lib.event')
local disposable = require('hlslens.lib.disposable')

---@class HlslensExternalUfo
---@field winid number
---@field auGroupId? number
---@field module? table
---@field initialized boolean
---@field disposables HlslensDisposable[]
local Ufo = {
    disposables = {}
}

function Ufo:listVirtTextInfos(bufnr, row, endRow)
    local marks = api.nvim_buf_get_extmarks(bufnr, self.ns, {row, 0}, {endRow, -1}, {details = true})
    local res = {}
    local lastRow, lastEndRow = -1, -1
    for _, mark in ipairs(marks) do
        local details = mark[4]
        local sr, er = mark[2], details.end_row
        if sr and er and (sr < lastRow or er > lastEndRow) then
            table.insert(res, {
                row = sr,
                endRow = er,
                priority = details.priority,
                virtText = details.virt_text
            })
            lastRow, lastEndRow = sr, er
        end
    end
    return res
end

function Ufo:virtTextWidth(virtText)
    local width = 0
    for _, chunk in ipairs(virtText) do
        local text = chunk[1]
        width = width + fn.strdisplaywidth(text)
    end
    return width
end

local function calibratePos(pos, offsetLnum)
    return {pos[1] - offsetLnum + 1, pos[2]}
end

---
---@param char string|'n'|'N'
---@param ... any
---@return boolean, number
function Ufo:nN(char, ...)
    vim.validate({char = {char, function(c) return c == 'n' or c == 'N' end, [['n' or 'N']]}})
    local winid
    local ok, msg = pcall(cmd, 'norm!' .. vim.v.count1 .. char)
    if not ok then
        ---@diagnostic disable-next-line: need-check-nil
        api.nvim_echo({{msg:match('(E%d+:.*)$'), 'ErrorMsg'}}, false, {})
        return ok, winid
    end
    if self.module then
        winid = self.module.peekFoldedLinesUnderCursor(...)
        self.winid = winid
        if utils.isWinValid(self.winid) then
            local bufnr = api.nvim_win_get_buf(self.winid)
            api.nvim_create_autocmd('WinClosed', {
                group = self.auGroupId,
                buffer = bufnr,
                once = true,
                callback = function(ev)
                    event:emit('UfoPreviewClosed', ev.buf)
                end
            })
        end
    end
    return require('hlslens').start(), winid
end

function Ufo:decoratePeekWindow(winid, sList, eList, idx)
    local pos = sList[idx]
    local foldedLnum = utils.foldClosed(winid, pos[1])
    if self.winid ~= winid then
        local w = self.winid
        vim.schedule(function()
            if self.winid == w and utils.isWinValid(self.winid) then
                local sp = calibratePos(sList[idx], foldedLnum)
                local ep = calibratePos(eList[idx], foldedLnum)
                local bufnr = api.nvim_win_get_buf(self.winid)
                render.clear(true, bufnr, true)
                render.addWinHighlight(self.winid, sp, ep)
                render:addNearestLens(bufnr, sp, idx, #sList)
            end
        end)
    end
end

function Ufo:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
end

function Ufo:initialize(module)
    if self.initialized then
        return self
    end
    self.module = module
    self.ns = api.nvim_create_namespace('ufo')
    self.winid = -1
    self.auGroupId = api.nvim_create_augroup('HlSearchLensUfoPreview', {})
    local disposables = {}
    table.insert(disposables, disposable:create(function()
        self.winid = -1
        self.initialized = false
        self.module = nil
        if self.auGroupId then
            api.nvim_del_augroup_by_id(self.auGroupId)
            self.auGroupId = nil
        end
    end))
    event:on('LensUpdated', function(bufnr, pattern, changedtick, sList, eList, idx, rIdx, region)
        local winid = fn.bufwinid(bufnr)
        if #sList == 0 or not utils.isWinValid(winid) or not vim.wo[winid].foldenable then
            return
        end
        self:decoratePeekWindow(winid, sList, eList, idx)
        local lnum, endLnum = region[1], region[2]
        local virtTextInfos = self:listVirtTextInfos(bufnr, lnum - 1, endLnum - 1)
        if #virtTextInfos == 0 then
            return
        end
        local curLnum = api.nvim_win_get_cursor(winid)[1]
        local curFoldLnum = utils.foldClosed(winid, curLnum)
        local curRow = (curFoldLnum > 0 and curFoldLnum or curLnum) - 1
        local lineWidth = utils.lineWidth(winid)
        for _, textInfo in ipairs(virtTextInfos) do
            local s, e, virtText = textInfo.row, textInfo.endRow, textInfo.virtText
            local hlsTextInfos = render:listVirtTextInfos(bufnr, s, e)
            local len = #hlsTextInfos
            if len > 0 then
                local hlsTextInfo = curRow <= s and hlsTextInfos[1] or hlsTextInfos[len]
                local hlsVirtText = hlsTextInfo.virtText
                -- replace `Ignore` highlight with `UfoFoldedBg`
                hlsVirtText[1][2] = 'UfoFoldedBg'
                if not virtText then
                    virtText = require('ufo.decorator'):getVirtTextAndCloseFold(winid, s + 1)
                end
                local width = self:virtTextWidth(virtText)
                local hlsVirtTextWidth = self:virtTextWidth(hlsVirtText)
                if width + hlsVirtTextWidth >= lineWidth then
                    local prefix = ' ⋯'
                    table.insert(hlsVirtText, 1, {prefix, 'UfoFoldedEllipsis'})
                    width = lineWidth - fn.strdisplaywidth(prefix) - hlsVirtTextWidth - 1
                end
                local priority = textInfo.priority
                render:setVirtText(bufnr, s, hlsVirtText, {
                    virt_text_win_col = width,
                    priority = type(priority) == 'number' and priority + 1 or 100
                })
            end
        end
    end, disposables)
    event:on('UfoPreviewClosed', function(bufnr)
        self.winid = -1
        render.clear(true, bufnr, true)
    end, disposables)
    self.disposables = disposables
    return self
end

return Ufo
