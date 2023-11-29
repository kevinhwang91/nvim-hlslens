local api = vim.api
local fn = vim.fn

local config = require('hlslens.config')
local utils = require('hlslens.utils')

---@class HlslensPosition
---@field bufnr number
---@field changedtick number
---@field pattern string
---@field pool table<number, HlslensPosition>
---@field poolCount number
---@field sList table
---@field eList table
---@field nearestIdx number
---@field nearestRelIdx number
---@field searchForward boolean
---@field foldedLine number
---@field visualAreaStart? number[]
---@field visualAreaEnd? number[]
local Position = {
    initialized = false
}

function Position:new(bufnr, changedtick, pattern)
    local o = setmetatable({}, self)
    self.__index = self
    o.bufnr = bufnr
    o.changedtick = changedtick
    o.pattern = pattern
    self.pool[bufnr] = o
    self.poolCount = self.poolCount + 1
    return o
end

---make sure run under current buffer
---@param bufnr? number
---@return HlslensPosition?
function Position:compute(bufnr)
    local pattern = fn.getreg('/')
    if pattern == '' then
        return
    end
    bufnr = bufnr or api.nvim_get_current_buf()
    local o = self.pool[bufnr]
    local changedtick = api.nvim_buf_get_changedtick(bufnr)
    if o and o.changedtick == changedtick and o.pattern == pattern then
        local hit = true
        if pattern:find([[\%V]], 1, true) then
            local vs = api.nvim_buf_get_mark(bufnr, '<')
            local ve = api.nvim_buf_get_mark(bufnr, '>')
            hit = (not o.visualAreaStart or utils.comparePosition(vs, o.visualAreaStart) == 0) and
                (not o.visualAreaEnd or utils.comparePosition(ve, o.visualAreaEnd) == 0)
            o.visualAreaStart, o.visualAreaEnd = vs, ve
        end
        if hit then
            return o
        end
    end
    if not self.rangeModule.valid(pattern) then
        return
    end

    -- fast and simple way to prevent memory leaking :)
    if self.poolCount > 5 then
        self.pool = {}
        self.poolCount = 0
    end

    o = self:new(bufnr, changedtick, pattern)
    o.sList, o.eList = self.rangeModule.buildList(pattern)

    local l = {startPos = o.sList, endPos = o.eList}
    -- TODO
    -- will remove build_position_cb
    l.start_pos = l.startPos
    l.end_pos = l.endPos
    if type(config.build_position_cb) == 'function' then
        pcall(config.build_position_cb, l, bufnr, changedtick, pattern)
    end

    return o
end

function Position:nearestIndex(curPos, curFoldedLnum, topl, botl)
    local idx = utils.binSearch(self.sList, curPos, utils.comparePosition)
    local len = #self.sList
    if idx > 0 then
        return idx, 0
    else
        idx = -idx - 1
        if idx == 0 then
            if curFoldedLnum > 0 and curFoldedLnum == fn.foldclosed(self.sList[1][1]) then
                return 1, 0
            else
                return 1, 1
            end
        elseif idx == len then
            return len, -1
        end
    end
    local loIdx = idx
    local hiIdx = idx + 1
    local relIdx = -1

    local loIdxLnum = self.sList[loIdx][1]
    local hiIdxLnum = self.sList[hiIdx][1]
    if curFoldedLnum > 0 and curFoldedLnum == fn.foldclosed(loIdxLnum) then
        return loIdx, 0
    end
    local foldedLnum = fn.foldclosed(hiIdxLnum)
    if foldedLnum > 0 then
        hiIdxLnum = foldedLnum
        if hiIdxLnum == curFoldedLnum then
            return hiIdx, 0
        end
    end
    local wv = fn.winsaveview()
    local loWinLine, hiWinLine = 0, 0
    local curWinLine = fn.winline()
    if topl <= loIdxLnum then
        api.nvim_win_set_cursor(0, {loIdxLnum, 0})
        loWinLine = fn.winline()
    end
    if botl >= hiIdxLnum then
        api.nvim_win_set_cursor(0, {hiIdxLnum, 0})
        hiWinLine = fn.winline()
    end
    fn.winrestview(wv)
    if hiWinLine > 0 and (loWinLine == 0 or
            math.ceil((hiWinLine - loWinLine) / 2) - 1 < curWinLine - loWinLine) then
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
        if utils.comparePosition(curPos, self.eList[idx - 1]) <= 0 then
            idx = idx - 1
            relIdx = -1
        end
    end

    return idx, relIdx
end

local function getOffsetPos(s, e, obyte)
    local sl, sc = unpack(s)
    local el, ec = unpack(e)
    local ol, oc
    local forward = obyte > 0
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
    return oc ~= -1 and {ol, oc} or nil
end

local function parseOffset(pattern)
    local off
    local histSearch = fn.histget('/')
    if histSearch ~= pattern then
        local delim = vim.v.searchforward == 1 and '/' or '?'
        local sects = vim.split(histSearch, delim)
        if #sects > 1 then
            local p = table.concat(sects, delim, 1, #sects - 1)
            if p == '' or p == pattern then
                off = sects[#sects]
            end
        end
    end
    return off
end

function Position:update(idx, rIdx, searchForward, foldedLine)
    local hit = self.nearestIdx == idx and self.nearestRelIdx == rIdx and
        self.searchForward == searchForward and self.foldedLine == foldedLine
    self.nearestIdx, self.nearestRelIdx = idx, rIdx
    self.searchForward, self.foldedLine = searchForward, foldedLine
    return hit
end

---
---@param topLine number
---@param botLine number
function Position:buildInfo(curPos, topLine, botLine)
    local foldedLine = fn.foldclosed(curPos[1])
    local idx, rIdx = self:nearestIndex(curPos, foldedLine, topLine, botLine)
    local sp = self.sList[idx]
    local ep = self.eList[idx]

    local offsetPos
    local off = parseOffset(self.pattern)
    if off and not off ~= '' then
        local obyte
        if off:match('^e%-?') then
            obyte = off:match('%-%d+', 1)
            if not obyte and off:sub(2, 2) ~= '+' then
                offsetPos = ep
            end
        elseif off:match('^s%+?') and off:sub(2, 2) ~= '-' then
            obyte = off:match('%+%d+', 1)
            if not obyte then
                offsetPos = sp
            end
        end
        obyte = tonumber(obyte)
        if obyte then
            offsetPos = getOffsetPos(sp, ep, obyte)
        end
        if offsetPos then
            rIdx = utils.comparePosition(offsetPos, curPos)
        end
    else
        offsetPos = sp
    end
    self.offsetPos = offsetPos
    local searchForward = vim.v.searchforward == 1
    return self:update(idx, rIdx, searchForward, foldedLine)
end

function Position:cursorInRange(curPos)
    return utils.comparePosition(self.sList[self.nearestIdx], curPos) <= 0 and
        utils.comparePosition(curPos, self.eList[self.nearestIdx]) <= 0
end

function Position:resetPool()
    self.pool = {}
    self.poolCount = 0
end

function Position:dispose()
    self:resetPool()
    self.rangeModule = nil
    self.initialized = false
end

function Position:initialize()
    if self.initialized then
        return
    end
    self.pool = {}
    self.poolCount = 0
    local limit
    if jit then
        Position.rangeModule = require('hlslens.position.range.regex')
        limit = 1e5
    else
        Position.rangeModule = require('hlslens.position.range.qf')
        limit = 1e4
    end
    Position.rangeModule.initialize(limit)
    self.initialized = false
    return self
end

return Position
