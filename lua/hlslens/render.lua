local M = {}
local fn = vim.fn
local api = vim.api
local cmd = vim.cmd

local utils = require('hlslens.utils')
local config = require('hlslens.config')

local winhl = require('hlslens.render.winhl')
local extmark = require('hlslens.render.extmark')
local floatwin = require('hlslens.render.floatwin')

local virtPriority
local nearestOnly
local nearestFloatWhen
local floatShadowBlend
local floatVirtId

local hlBlendTbl

local function init()
    virtPriority = config.virt_priority
    nearestOnly = config.nearest_only
    nearestFloatWhen = config.nearest_float_when
    floatShadowBlend = config.float_shadow_blend

    cmd([[
        hi default link HlSearchNear IncSearch
        hi default link HlSearchLens WildMenu
        hi default link HlSearchLensNear IncSearch
        hi default link HlSearchFloat IncSearch
    ]])

    hlBlendTbl = setmetatable({Ignore = 'Ignore'}, {
        __index = function(tbl, hlgroup)
            local newHlGroup
            if vim.o.termguicolors then
                newHlGroup = 'HlSearchBlend_' .. hlgroup
                local hlCmdTbl = {'hi ' .. newHlGroup, 'blend=0'}
                for k, v in pairs(utils.hlAttrs(hlgroup)) do
                    table.insert(hlCmdTbl, ('%s=%s'):format(k, type(v) == 'table' and
                        table.concat(v, ',') or v))
                end
                cmd(table.concat(hlCmdTbl, ' '))
            else
                newHlGroup = hlgroup
            end
            rawset(tbl, hlgroup, newHlGroup)
            return rawget(tbl, hlgroup)
        end
    })
end

local function chunksToText(chunks)
    local text = ''
    for _, chunk in ipairs(chunks) do
        text = text .. chunk[1]
    end
    return text
end

local function enoughSizeForVirt(winid, lnum, chunks, lineWidth)
    local text = chunksToText(chunks)
    local endVcol = utils.vcol(winid, {lnum, '$'}) - 1
    local remainingVcol
    if vim.wo[winid].wrap then
        remainingVcol = lineWidth - (endVcol - 1) % lineWidth - 1
    else
        remainingVcol = math.max(0, lineWidth - endVcol)
    end
    return remainingVcol > #text
end

local function updateFloatWin(winid, pos, chunks, lineWidth, gutterSize)
    local width, height = api.nvim_win_get_width(winid), api.nvim_win_get_height(winid)
    local floatCol = utils.vcol(winid, pos) % lineWidth + gutterSize - 1
    local text = chunksToText(chunks)
    if vim.o.termguicolors then
        local floatWin, floatBuf = floatwin.update(height, 0, width)
        vim.wo[floatWin].winbl = floatShadowBlend
        local padding = (' '):rep(math.min(floatCol, width - #text) - 1)
        local newChunks = {{padding, 'Ignore'}}
        for _, chunk in ipairs(chunks) do
            local t, hlgroup = unpack(chunk)
            if not t:match('^%s+$') and hlgroup ~= 'Ignore' then
                table.insert(newChunks, {t, hlBlendTbl[hlgroup]})
            end
        end
        floatVirtId = extmark.setVirtEol(floatBuf, 0, newChunks, virtPriority, floatVirtId)
    else
        local floatWin, floatBuf = floatwin.update(height, floatCol, #text)
        vim.wo[floatWin].winhl = 'Normal:HlSearchFloat'
        api.nvim_buf_set_lines(floatBuf, 0, 1, true, {text})
    end
end

-- Add lens template, can be overridden by `override_lens`
---@param bufnr number buffer number
---@param startPosList table (1,1)-indexed position
---@param nearest boolean whether nearest lens
---@param idx number nearest index in the plist
---@param relIdx number relative index, negative means before current position, positive means after
function M.addLens(bufnr, startPosList, nearest, idx, relIdx)
    if type(config.override_lens) == 'function' then
        -- export render module for hacking :)
        return config.override_lens(M, startPosList, nearest, idx, relIdx)
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
        chunks = {{' ', 'Ignore'}, {text, 'HlSearchLensNear'}}
    else
        text = ('[%s %d]'):format(indicator, idx)
        chunks = {{' ', 'Ignore'}, {text, 'HlSearchLens'}}
    end
    M.setVirt(bufnr, lnum - 1, col - 1, chunks, nearest)
end

function M.setVirt(bufnr, lnum, col, chunks, nearest)
    local exLnum, exCol = lnum + 1, col + 1
    if nearest and (nearestFloatWhen == 'auto' or nearestFloatWhen == 'always') then
        if utils.isCmdLineWin(bufnr) then
            extmark.setVirtEol(bufnr, lnum, chunks, virtPriority)
        else
            local gutterSize = utils.textoff(api.nvim_get_current_win())
            local lineWidth = api.nvim_win_get_width(0) - gutterSize
            if nearestFloatWhen == 'always' then
                updateFloatWin(0, {exLnum, exCol}, chunks, lineWidth, gutterSize)
            else
                if enoughSizeForVirt(0, exLnum, chunks, lineWidth) and fn.foldclosed(exLnum) == -1 then
                    extmark.setVirtEol(bufnr, lnum, chunks, virtPriority)
                    floatwin.close()
                else
                    updateFloatWin(0, {exLnum, exCol}, chunks, lineWidth, gutterSize)
                end
            end
        end
    else
        extmark.setVirtEol(bufnr, lnum, chunks, virtPriority)
    end
end

-- TODO
-- compatible with old demo
M.set_virt = M.setVirt

function M.addWinHighlight(winid, startPos, endPos)
    winhl.addHighlight(winid, startPos, endPos, 'HlSearchNear')
end

local function getIdxLnum(posList, i)
    return posList[i][1]
end

function M.doLens(startPosList, nearest, idx, relIdx)
    local posLen = #startPosList
    local idxLnum = getIdxLnum(startPosList, idx)

    local lineRenderList = {}

    if not nearestOnly and not nearest then
        local t0, b0
        local prevPos = startPosList[math.max(1, idx - 1)]
        local nextPos = startPosList[math.min(posLen, idx + 1)]
        -- TODO just relieve foldclosed behavior, can't solve the issue perfectly
        if vim.wo.foldenable then
            t0, b0 = math.min(prevPos[1], fn.line('w0')), math.max(nextPos[1], fn.line('w$'))
        else
            t0, b0 = prevPos[1], nextPos[1]
        end
        local winHeight = api.nvim_win_get_height(0)
        local topLimit = math.max(0, t0 - winHeight + 1)
        local botLimit = math.min(api.nvim_buf_line_count(0), b0 + winHeight - 1)

        local iLnum, rIdx
        local lastHlLnum = 0
        local topRelIdx = math.min(relIdx, 0)

        for i = math.max(idx - 1, 0), 1, -1 do
            iLnum = getIdxLnum(startPosList, i)
            if iLnum < topLimit then
                break
            end
            if lastHlLnum ~= iLnum then
                lastHlLnum = iLnum
                rIdx = i - idx + topRelIdx
                lineRenderList[iLnum] = {i, rIdx}
            end
        end

        lastHlLnum = idxLnum
        local botRelIdx = math.max(relIdx, 0)
        local lastI
        for i = idx + 1, posLen do
            lastI = i
            iLnum = getIdxLnum(startPosList, i)
            if lastHlLnum ~= iLnum then
                lastHlLnum = iLnum
                rIdx = i - 1 - idx + botRelIdx
                lineRenderList[startPosList[i - 1][1]] = {i - 1, rIdx}
                if iLnum > botLimit then
                    break
                end
            end
        end

        if lastI and iLnum <= botLimit then
            rIdx = lastI - idx + botRelIdx
            lineRenderList[iLnum] = {lastI, rIdx}
        end
        lineRenderList[idxLnum] = nil
    end

    local bufnr = api.nvim_get_current_buf()
    extmark.clearBuf(bufnr)
    M.addLens(bufnr, startPosList, true, idx, relIdx)
    for _, idxPairs in pairs(lineRenderList) do
        M.addLens(bufnr, startPosList, false, idxPairs[1], idxPairs[2])
    end
end

function M.clear(hl, bufnr, floated)
    if hl then
        winhl.clearHighlight()
    end
    if bufnr then
        extmark.clearBuf(bufnr)
    end
    if floated then
        floatwin.close()
    end
end

function M.clearAll()
    floatwin.close()
    winhl.clearHighlight()
    extmark.clearAllBuf()
end

init()

return M
