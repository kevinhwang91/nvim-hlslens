local M = {}

local api = vim.api
local fn = vim.fn

local config = require('hlslens.config')
local utils = require('hlslens.utils')

local bufs
local jitEnabled
local rangeModule
local limit

local function buildCache(bufnr, pattern, posList)
    local c = {
        posList = posList or {},
        changedtick = api.nvim_buf_get_changedtick(bufnr),
        pattern = pattern
    }
    if not bufs[bufnr] then
        bufs.cnt = bufs.cnt + 1
    end
    bufs[bufnr] = c
    return c
end

function M.hitCache(bufnr, pattern, nearestIdx, nearestRelIdx)
    local c = bufs[bufnr]
    return c and pattern == c.pattern and nearestIdx == c.nIdx and
        nearestRelIdx == c.nrIdx and vim.v.searchforward == c.searchForward
end

function M.updateCache(bufnr, pattern, nearestIdx, nearestRelIdx)
    local c = bufs[bufnr]
    c.pattern, c.nIdx, c.nrIdx, c.searchForward = pattern, nearestIdx, nearestRelIdx, vim.v.searchforward
end

-- make sure run under current buffer
function M.build(curBufnr, pattern)
    curBufnr = curBufnr or api.nvim_get_current_buf()
    local c = bufs[curBufnr] or {}
    if c.changedtick == api.nvim_buf_get_changedtick(curBufnr) and c.pattern == pattern then
        return c.posList
    end

    if not jitEnabled then
        if not rangeModule.valid(pattern) or vim.bo.bt == 'quickfix' or utils.isCmdLineWin() then
            return buildCache(curBufnr, pattern, {startPos = {}, endPos = {}}).posList
        end
    end

    -- fast and simple way to prevent memory leaking :)
    if bufs.cnt > 5 then
        bufs = {cnt = 0}
    end

    local startPosList, endPosList = rangeModule.buildList(pattern, limit)

    local posList = {startPos = startPosList, endPos = endPosList}
    -- TODO
    -- will remove start_pos and end_pos fields
    posList.start_pos = posList.startPos
    posList.end_pos = posList.endPos

    local cache = buildCache(curBufnr, pattern, posList)

    if type(config.build_position_cb) == 'function' then
        pcall(config.build_position_cb, cache.posList, curBufnr, cache.changedtick, cache.pattern)
    end

    return cache.posList
end

function M.clear()
    bufs = {cnt = 0}
end

local function nearestIndex(posList, curPos, topl, botl)
    local spList = posList.startPos
    local idx = utils.binSearch(spList, curPos, utils.comparePosition)
    if idx > 0 then
        return idx, 0
    else
        idx = -idx - 1
        if idx == 0 then
            return 1, 1
        elseif idx == #spList then
            return #spList, -1
        end
    end
    local loIdx = idx
    local hiIdx = idx + 1
    local relIdx = -1

    local loIdxLnum = spList[loIdx][1]
    local hiIdxLnum = spList[hiIdx][1]
    local midLnum = math.ceil((hiIdxLnum + loIdxLnum) / 2) - 1
    local curLnum = curPos[1]

    -- fn.line('w$') may be expensive while scrolling down
    topl = topl or fn.line('w0')
    if topl > loIdxLnum or midLnum < curLnum and (botl or fn.line('w$')) >= hiIdxLnum then
        relIdx = 1
        idx = idx + 1
    end

    if relIdx == 1 and idx > 1 then
        -- calibrate the nearest index, because index is based on start of the position
        -- curPos <= previousIdxEndPos < idxStartPos maybe happened
        -- for instance:
        --     text: 1ab|c 2abc
        --     pattern: abc
        --     cursor: |
        -- nearest index locate at start of second 'abc',
        -- but current position is between start of
        -- previous index position and end of current index position
        if utils.comparePosition(curPos, posList.endPos[idx - 1]) <= 0 then
            idx = idx - 1
            relIdx = -1
        end
    end

    return idx, relIdx
end

function M.getOffsetPos(s, e, obyte)
    local sl, sc = unpack(s)
    local el, ec = unpack(e)
    local ol, oc
    local forward = obyte > 0 and true or false
    obyte = math.abs(obyte)
    if sl == el then
        ol = sl
        if forward then
            oc = sc + obyte
            if oc > ec then
                oc = -1
            end
        else
            oc = ec - obyte
            if oc < sc then
                oc = -1
            end
        end
    else
        local lines = api.nvim_buf_get_lines(0, sl - 1, el, true)
        local len = #lines
        local first = lines[1]
        lines[1] = first:sub(sc)
        local last = lines[len]
        lines[len] = last:sub(1, ec)
        if forward then
            ol = sl
            oc = sc
            for i = 1, len do
                local l = lines[i]
                if #l <= obyte then
                    ol = ol + 1
                    oc = 1
                    obyte = obyte - #l
                else
                    oc = oc + obyte
                    break
                end
            end
            if ol > el then
                oc = -1
            end
        else
            ol = el
            for i = len, 1, -1 do
                local l = lines[i]
                if #l <= obyte then
                    ol = ol - 1
                    oc = -1
                    obyte = obyte - #l
                else
                    oc = #l - obyte
                    break
                end
            end
            if ol == sl then
                oc = oc + sc - 1
            end
        end
    end
    return oc == -1 and {} or {ol, oc}
end

function M.nearestIdxInfo(posList, off)
    local wv = fn.winsaveview()
    local curPos = {wv.lnum, wv.col + 1}
    local topl = wv.topline
    local idx, rIdx = nearestIndex(posList, curPos, topl)
    local startPos = posList.startPos[idx]
    local endPos = posList.endPos[idx]

    local offsetPos = {}
    if off and not off ~= '' then
        local obyte
        if off:match('^e%-?') then
            obyte = off:match('%-%d+', 1)
            if not obyte and off:sub(2, 2) ~= '+' then
                offsetPos = endPos
            end
        elseif off:match('^s%+?') and off:sub(2, 2) ~= '-' then
            obyte = off:match('%+%d+', 1)
            if not obyte then
                offsetPos = startPos
            end
        end
        if obyte then
            obyte = tonumber(obyte)
            offsetPos = M.getOffsetPos(startPos, endPos, obyte)
        end
        if offsetPos and not vim.tbl_isempty(offsetPos) then
            rIdx = utils.comparePosition(offsetPos, curPos)
        end
    else
        offsetPos = startPos
    end
    return {
        idx = idx,
        rIdx = rIdx,
        curPos = curPos,
        startPos = startPos,
        endPos = endPos,
        offsetPos = offsetPos
    }
end

function M.inRange(s, e, c)
    return utils.comparePosition(s, c) <= 0 and utils.comparePosition(c, e) <= 0
end

local function init()
    bufs = {cnt = 0}
    jitEnabled = utils.jitEnabled()
    limit = jitEnabled and 100000 or 10000
    rangeModule = jitEnabled and require('hlslens.range.regex') or require('hlslens.range.qf')
end

init()

return M
