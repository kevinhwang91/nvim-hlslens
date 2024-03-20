local fn = vim.fn
local api = vim.api
local cmd = vim.cmd

local utils = require('hlslens.utils')
local config = require('hlslens.config')
local disposable = require('hlslens.lib.disposable')
local decorator = require('hlslens.decorator')
local throttle = require('hlslens.lib.throttle')
local position = require('hlslens.position')
local event = require('hlslens.lib.event')

local winhl = require('hlslens.render.winhl')
local extmark = require('hlslens.render.extmark')
local floatwin = require('hlslens.render.floatwin')

local DUMMY_POS

---@diagnostic disable: undefined-doc-name
---@alias HlslensRenderState
---| STOP #1
---| START #2
---| PENDING #3
---@diagnostic enable: undefined-doc-name
local STOP = 1
local START = 2
local PENDING = 3

---@class HlslensRender
---@field initialized boolean
---@field ns number
---@field status HlslensRenderState
---@field force? boolean
---@field nearestOnly boolean
---@field nearestFloatWhen string
---@field calmDown boolean
---@field stopDisposes HlslensDisposable[]
---@field disposables HlslensDisposable[]
local Render = {
    initialized = false,
    stopDisposes = {},
    disposables = {}
}

local function chunksToText(chunks)
    local text = ''
    for _, chunk in ipairs(chunks) do
        text = text .. chunk[1]
    end
    return text
end

function Render:doNohAndStop(defer)
    local function f()
        cmd('noh')
        self:stop()
    end

    if defer then
        vim.schedule(f)
    else
        f()
    end
end

function Render:mayStop()
    local status = self.status
    if status == START then
        self.status = PENDING
        vim.schedule(function()
            if self.status == PENDING then
                self.status = status
            end
            if vim.v.hlsearch == 0 then
                self:stop()
            end
        end)
    end
end

local function refreshCurrentBuf()
    local self = Render
    local bufnr = api.nvim_get_current_buf()
    local pos = position:compute(bufnr)
    if not pos then
        self:stop()
        return
    end
    if #pos.sList == 0 then
        self.clear(true, 0, true)
        return
    end

    local winid = api.nvim_get_current_win()
    local cursor = api.nvim_win_get_cursor(winid)
    local curPos = {cursor[1], cursor[2] + 1}
    local topLine, botLine = fn.line('w0'), fn.line('w$')
    local hit = pos:buildInfo(curPos, topLine, botLine)
    if self.calmDown then
        if not pos:cursorInRange(curPos) then
            self:doNohAndStop()
            return
        end
    elseif not self.force and hit then
        return
    end

    local fs, fe = pos.foldedLine, -1
    if fs ~= -1 then
        fe = fn.foldclosedend(curPos[1])
    end
    local idx, rIdx = pos.nearestIdx, pos.nearestRelIdx
    local sList, eList = pos.sList, pos.eList
    self.addWinHighlight(0, sList[idx], eList[idx])
    self:doLens(bufnr, sList, not pos.offsetPos, idx, rIdx, {topLine, botLine}, {fs, fe})
    event:emit('LensUpdated', bufnr, pos.pattern, pos.changedtick, sList, eList, idx, rIdx,
        {topLine, botLine})
end

function Render:createEvents()
    local dps = {}
    local gid = api.nvim_create_augroup('HlSearchLensRender', {})
    local events = {'CursorMoved', 'TermEnter'}
    if self.calmDown then
        table.insert(events, 'TextChanged')
        table.insert(events, 'TextChangedI')
        event:on('TextChanged', function()
            self:doNohAndStop(true)
        end, dps)
        event:on('TextChangedI', function()
            self:doNohAndStop(true)
        end, dps)
    end
    api.nvim_create_autocmd(events, {
        group = gid,
        callback = function(ev)
            event:emit(ev.event)
        end
    })
    event:on('CursorMoved', self.throttledRefresh, dps)
    event:on('TermEnter', function()
        self.clear(true, 0, true)
    end, dps)
    return disposable:create(function()
        api.nvim_del_augroup_by_id(gid)
        disposable.disposeAll(dps)
    end)
end

local function enoughSizeForVirt(winid, lnum, text, lineWidth)
    if utils.foldClosed(winid, lnum) > 0 then
        return true
    end
    local endVcol = utils.vcol(winid, {lnum, '$'}) - 1
    local remainingVcol
    if vim.wo[winid].wrap then
        remainingVcol = lineWidth - (endVcol - 1) % lineWidth - 1
    else
        remainingVcol = math.max(0, lineWidth - endVcol)
    end
    return remainingVcol > #text
end

function Render:addNearestLens(bufnr, pos, idx, cnt)
    -- To build a dummy list for compatibility
    local plist = {}
    for _ = 1, cnt do
        table.insert(plist, DUMMY_POS)
    end
    plist[idx] = pos
    self:addLens(bufnr, plist, true, idx, 0)
end

-- Add lens template, can be overridden by `override_lens`
---@param bufnr number buffer number
---@param startPosList table (1,1)-indexed position
---@param nearest boolean whether nearest lens
---@param idx number nearest index in the plist
---@param relIdx number relative index, negative means before current position, positive means after
function Render:addLens(bufnr, startPosList, nearest, idx, relIdx)
    if type(config.override_lens) == 'function' then
        -- export render module for hacking :)
        return config.override_lens(self, startPosList, nearest, idx, relIdx)
    end
    local sfw = vim.v.searchforward == 1
    local indicator, text, chunks
    local absRelIdx = math.abs(relIdx)
    if absRelIdx > 1 then
        indicator = ('%d%s'):format(absRelIdx, sfw ~= (relIdx > 1) and 'N' or 'n')
    elseif absRelIdx == 1 then
        indicator = sfw ~= (relIdx == 1) and 'N' or 'n'
    else
        indicator = ''
    end

    local lnum, col = unpack(startPosList[idx])
    if nearest then
        local cnt = #startPosList
        if indicator ~= '' then
            text = ('[%s %d/%d]'):format(indicator, idx, cnt)
        else
            text = ('[%d/%d]'):format(idx, cnt)
        end
        chunks = {{' '}, {text, 'HlSearchLensNear'}}
    else
        text = ('[%s %d]'):format(indicator, idx)
        chunks = {{' '}, {text, 'HlSearchLens'}}
    end
    self.setVirt(bufnr, lnum - 1, col - 1, chunks, nearest)
end

function Render:listVirtTextInfos(bufnr, row, endRow)
    return extmark:listVirtEol(bufnr, row, endRow)
end

function Render:setVirtText(bufnr, row, virtText, opts)
    return extmark:setVirtText(bufnr, row, virtText, opts)
end

function Render.setVirt(bufnr, row, col, chunks, nearest)
    local self = Render
    local when = self.nearestFloatWhen
    local exLnum, exCol = row + 1, col + 1
    if nearest and (when == 'auto' or when == 'always') then
        if utils.isCmdLineWin(bufnr) then
            extmark:setVirtText(bufnr, row, chunks)
        else
            local winid = fn.bufwinid(bufnr ~= 0 and bufnr or '')
            if winid == -1 then
                return
            end
            local textOff = utils.textOff(winid)
            local lineWidth = api.nvim_win_get_width(winid) - textOff
            local text = chunksToText(chunks)
            local pos = {exLnum, exCol}
            if when == 'always' then
                floatwin:updateFloatWin(winid, pos, chunks, text, lineWidth, textOff)
            else
                if enoughSizeForVirt(winid, exLnum, text, lineWidth) then
                    extmark:setVirtText(bufnr, row, chunks)
                    floatwin:close()
                else
                    floatwin:updateFloatWin(winid, pos, chunks, text, lineWidth, textOff)
                end
            end
        end
    else
        extmark:setVirtText(bufnr, row, chunks)
    end
end

-- TODO
-- compatible with old demo
Render.set_virt = Render.setVirt

function Render:setVisualArea()
    local function calibrate(pos)
        return {pos[1] - 1, pos[2]}
    end

    local start = calibrate(api.nvim_buf_get_mark(0, '<'))
    local finish = calibrate(api.nvim_buf_get_mark(0, '>'))
    extmark:setHighlight(0, 'Visual', start, finish)
end

function Render:clearVisualArea()
    extmark:clearHighlight(0)
end

function Render.addWinHighlight(winid, startPos, endPos)
    winhl.addHighlight(winid, startPos, endPos, 'HlSearchNear')
end

local function getIdxLnum(posList, i)
    return posList[i][1]
end

function Render:doLens(bufnr, startPosList, nearest, idx, relIdx, limitRange, foldRange)
    local posLen = #startPosList
    local idxLnum = getIdxLnum(startPosList, idx)

    local lineRenderList = {}

    if not self.nearestOnly and not nearest then
        local iLnum, rIdx
        local lastHlLnum = 0
        local topLimit, botLimit = limitRange[1], limitRange[2]
        local fs, fe = foldRange[1], foldRange[2]

        local tIdx = idx - 1 - math.min(relIdx, 0)
        while fs > -1 and tIdx > 0 do
            iLnum = getIdxLnum(startPosList, tIdx)
            if fs > iLnum then
                break
            end
            tIdx = tIdx - 1
        end
        for i = math.max(tIdx, 0), 1, -1 do
            iLnum = getIdxLnum(startPosList, i)
            if iLnum < topLimit then
                break
            end
            if lastHlLnum ~= iLnum then
                lastHlLnum = iLnum
                rIdx = i - tIdx - 1
                lineRenderList[iLnum] = {i, rIdx}
            end
        end

        local bIdx = idx + 1 - math.max(relIdx, 0)
        while fe > -1 and bIdx < posLen do
            iLnum = getIdxLnum(startPosList, bIdx)
            if fe < iLnum then
                break
            end
            bIdx = bIdx + 1
        end
        lastHlLnum = idxLnum
        local lastI
        for i = bIdx, posLen do
            lastI = i
            iLnum = getIdxLnum(startPosList, i)
            if lastHlLnum ~= iLnum then
                lastHlLnum = iLnum
                rIdx = i - bIdx
                lineRenderList[startPosList[i - 1][1]] = {i - 1, rIdx}
            end
            if iLnum > botLimit then
                break
            end
        end

        if lastI and iLnum <= botLimit then
            rIdx = lastI - bIdx + 1
            lineRenderList[iLnum] = {lastI, rIdx}
        end
        lineRenderList[idxLnum] = nil
    end

    extmark:clearBuf(bufnr)
    self:addLens(bufnr, startPosList, true, idx, relIdx)
    for _, idxPairs in pairs(lineRenderList) do
        self:addLens(bufnr, startPosList, false, idxPairs[1], idxPairs[2])
    end
end

function Render.clear(hl, bufnr, floated)
    if hl then
        winhl.clearHighlight()
    end
    if bufnr then
        extmark:clearBuf(bufnr)
    end
    if floated then
        floatwin:close()
    end
end

function Render.clearAll()
    floatwin:close()
    extmark:clearAll()
    winhl.clearHighlight()
end

function Render:refresh(force)
    self.force = force or self.force
    self.throttledRefresh()
end

function Render:start(force)
    if vim.o.hlsearch then
        if self.status == STOP then
            self.status = START
            table.insert(self.stopDisposes, decorator:initialize(self.ns))
            table.insert(self.stopDisposes, self:createEvents())
            event:on('RegionChanged', function()
                self:refresh(true)
            end, self.stopDisposes)
            event:on('HlSearchCleared', function()
                self:mayStop()
            end, self.stopDisposes)
            table.insert(self.stopDisposes, disposable:create(function()
                position:resetPool()
                self.status = STOP
                self.clearAll()
                self.throttledRefresh:cancel()
            end))
        end
        if not self.throttledRefresh then
            return
        end
        if force then
            self.throttledRefresh:cancel()
        end
        self:refresh(force)
    end
end

function Render:isStarted()
    return self.status == START
end

function Render:dispose()
    self:stop()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
end

function Render:stop()
    disposable.disposeAll(self.stopDisposes)
    self.stopDisposes = {}
end

function Render:initialize(namespace)
    self.status = STOP
    if self.initialized then
        return self
    end
    self.nearestOnly = config.nearest_only
    self.nearestFloatWhen = config.nearest_float_when
    self.calmDown = config.calm_down
    self.throttledRefresh = throttle(function()
        if self.status == START and self.throttledRefresh then
            refreshCurrentBuf()
        end
        self.force = nil
    end, 150)
    table.insert(self.disposables, disposable:create(function()
        self.status = STOP
        self.initialized = false
        self.throttledRefresh:cancel()
        self.throttledRefresh = nil
    end))
    table.insert(self.disposables, extmark:initialize(namespace, config.virt_priority))
    table.insert(self.disposables, floatwin:initialize(config.float_shadow_blend))
    self.ns = namespace
    self.initialized = true
    DUMMY_POS = {1, 1}
    return self
end

return Render
