local fn = vim.fn
local cmd = vim.cmd
local api = vim.api
local uv = vim.loop

local utils = require('hlslens.utils')
local render = require('hlslens.render')
local config = require('hlslens.config')
local event = require('hlslens.lib.event')
local parser = require('hlslens.cmdline.parser')
local fold = require('hlslens.cmdline.fold')
local debounce = require('hlslens.lib.debounce')
local disposable = require('hlslens.lib.disposable')

---@class HlslensCmdLine
---@field attached boolean
---@field incSearch boolean
---@field initialized boolean
---@field disposables HlslensDisposable[]
---@field ns number
---@field currentIdx number
---@field total number
---@field hrtime number
---@field parser HlslensCmdLineParser
---@field isSubstitute boolean
---@field isVisualArea boolean
---@field range? number[]
---@field searching boolean
---@field fold? HlslensCmdLineIncSearchFold
---@field debouncedSearch HlslensDebounce
---@field searchStart number[] (1, 0)-indexed position
---@field matchStart number[] (1, 0)-indexed position
---@field matchEnd number[] (1, 0)-indexed position
---@field keyCode number[]
local CmdLine = {
    initialized = false,
    disposables = {}
}

local function decPos(pos)
    return {pos[1], math.max(0, pos[2] - 1)}
end

function CmdLine:resetState()
    self.currentIdx = 0
    self.total = 0
end

---
---@return boolean
function CmdLine:typeUpDown()
    -- <Up> = 0x80 0x6b 0x75
    -- <Down> = 0x80 0x6b 0x64
    return self.keyCode[1] == 0x80 and self.keyCode[2] == 0x6b and
        (self.keyCode[3] == 0x75 or self.keyCode[3] == 0x64)
end

---
---@param pos number[]
---@param endPos? number[]
function CmdLine:doRender(pos, endPos)
    render.clear(true, 0, true)
    if endPos then
        render.addWinHighlight(0, pos, endPos)
    end
    render:addNearestLens(0, pos, self.currentIdx, self.total)
    if self.fold then
        self.fold:expand(pos[1])
    end
end

---may_do_incsearch_highlighting
---@param pattern string
---@return table|nil
function CmdLine:searchRange(pattern)
    api.nvim_win_set_cursor(0, self.searchStart)
    local flag = self.isSubstitute and 'c' or (self.type == '?' and 'b' or '')
    if self.range then
        flag = flag .. 'n'
    end
    local pos = utils.searchPosSafely(pattern, flag)
    if utils.comparePosition(pos, {0, 0}) == 0 then
        return
    end
    if self.range then
        if pos[1] < self.range[1] or pos[1] > self.range[2] then
            return
        end
        api.nvim_win_set_cursor(0, decPos(pos))
    end
    local ok, res = pcall(fn.searchcount, {
        recompute = true,
        maxcount = 100000,
        timeout = 100,
        pattern = pattern
    })
    local range
    if ok and res.incomplete == 0 and res.total and res.total > 0 then
        self.currentIdx = res.current
        self.total = res.total
        local endPos = utils.searchPosSafely(pattern, 'cenW')
        self.matchStart, self.matchEnd = decPos(pos), decPos(endPos)
        range = {pos, endPos}
    end
    return range
end

---may_do_command_line_next_incsearch
---@param pattern string
---@param forward boolean
---@return number[]|nil
function CmdLine:incSearchPos(forward, pattern)
    local pos
    local cursor = self.matchEnd
    api.nvim_win_set_cursor(0, cursor)
    if forward then
        pos = utils.searchPosSafely(pattern, '')
        self.currentIdx = self.currentIdx == self.total and 1 or self.currentIdx + 1
    else
        utils.searchPosSafely(pattern, 'b')
        pos = utils.searchPosSafely(pattern, 'b')
        self.currentIdx = self.currentIdx == 1 and self.total or self.currentIdx - 1
    end
    api.nvim_win_set_cursor(0, cursor)
    if utils.comparePosition(pos, {0, 0}) > 0 then
        self.searchStart = self.matchStart
    end
    vim.schedule(function()
        self.matchStart = decPos(utils.searchPosSafely(pattern, 'bcnW'))
        self.matchEnd = api.nvim_win_get_cursor(0)
    end)
    return pos
end

function CmdLine:toggleHlSearch(enable)
    if not self.attached then
        return
    end
    if enable then
        cmd('if !&hlsearch | noa set hlsearch | end')
    else
        cmd('noa set nohlsearch')
    end
end

function CmdLine:attach(typ)
    self.attached = self.incSearch and (typ == '/' or typ == '?' or typ == ':') and
        vim.o.hls and vim.o.is
    if not self.attached then
        return
    end
    self.type = typ

    if vim.wo.foldenable then
        local fdo = vim.o.fdo
        if fdo:find('search', 1, true) or fdo:find('all', 1, true) then
            self.fold = fold:new()
        end
    end

    self:resetState()
    local cursor = api.nvim_win_get_cursor(0)
    self.parser = parser:new(typ, cursor)
    self.range = nil
    self.searchStart = cursor
    self.matchStart = cursor
    self.matchEnd = cursor
    self.isSubstitute = false
    self.searching = true
    self.keyCode = {}
    vim.on_key(function(char)
        if not self.searching then
            return
        end
        local b1, b2, b3 = char:byte(1, -1)
        self.keyCode = {b1, b2, b3}
        -- <C-g> = 0x7
        -- <C-t> = 0x14
        if b2 == nil and self.currentIdx > 0 and self.total > 0 and (b1 == 0x07 or b1 == 0x14) then
            -- TODO
            -- %s/pat is buggy here
            -- Hack! Type <C-t><C-g> will get rid of incsearch issue for substitute.
            -- 1. Disable incsearch and current <C-g> or <C-t> will be appended to the cursor
            -- 2. Delete the appended char;
            -- 3. Get rid of the issue;
            -- 4. Redo the previous cancelled action for incsearch.
            -- <C-h><C-t><C-g> + b1
            if self.isSubstitute then
                cmd('noa set nois')
                -- ignore `CmdlineChanged` event to avoid to parse cmdline recursively
                self.attached = false
                vim.schedule(function()
                    self.attached = true
                    cmd('noa set is')
                    api.nvim_feedkeys(('%c%c%c%c'):format(0x08, 0x14, 0x07, b1), 'in', false)
                end)
                self.isSubstitute = nil
            else
                local pos = self:incSearchPos(b1 == 0x07, self.parser.pattern)
                if pos and not self.parser:hasOffset() then
                    self:doRender(pos)
                end
            end
        end
    end, self.ns)
    self.debouncedSearch:cancel()
end

function CmdLine:didChange()
    self.searching = self.parser:doParse()
    if not self.searching then
        return
    end
    if self.parser.type == ':' then
        self.isSubstitute = self.parser:isSubstitute()
        self.range = self.parser.range
        if self.isSubstitute then
            render.clear(true, 0, true)
        elseif not self.parser:patternChanged() then
            self.matchEnd = api.nvim_win_get_cursor(0)
            return
        end
    else
        self.parser:splitPattern()
    end
    local range
    if self.parser:validatePattern() then
        range = self:searchRange(self.parser.pattern)
    end
    if range then
        self:doRender(range[1], range[2])
    else
        self:resetState()
        render.clear(true, 0, true)
    end
end

function CmdLine:detach(typ, abort)
    if not self.attached or self.type ~= typ then
        return
    end
    self:toggleHlSearch(true)
    self.attached = false
    vim.on_key(nil, self.ns)
    if abort then
        if self.fold then
            self.fold:undo()
        end
        if self.isSubstitute then
            api.nvim_win_set_cursor(0, self.parser.originCursor)
        end
    end
    self.hrtime = nil
    self.parser = nil
    self.fold = nil
    if self.isVisualArea then
        render:clearVisualArea()
    end
    self.isVisualArea = false
    self.debouncedSearch:cancel()
end

function CmdLine:onChanged()
    if not self.attached then
        return
    end

    local now = uv.hrtime()
    local deltaTime = self.hrtime and now - self.hrtime
    self.hrtime = now

    local line = fn.getcmdline()
    self.parser:setLine(line)
    if not self.parser:lineChanged() then
        return
    end

    local isVisualArea = line:find([[\%V]], 1, true) ~= nil
    if isVisualArea ~= self.isVisualArea then
        if isVisualArea then
            render:setVisualArea()
        else
            render:clearVisualArea()
        end
    end
    self.isVisualArea = isVisualArea

    -- 10 ms is sufficient to identify whether the user is typing in command line mode or
    -- emitting key sequences from a key mapping
    if deltaTime and deltaTime < 1e7 and not self:typeUpDown() then
        self.debouncedSearch()
        if self.type ~= ':' and isVisualArea then
            local cursor = api.nvim_win_get_cursor(0)
            -- toggle hlsearch depends on whether cursor is moved or not
            self:toggleHlSearch(utils.comparePosition(cursor, self.searchStart) ~= 0)
        else
            vim.v.hlsearch = 0
        end
        return
    else
        self.debouncedSearch:cancel()
    end
    self:didChange()
    self:toggleHlSearch(not self.parser:isEmptyVisualAreaPattern())
end

function CmdLine:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
end

function CmdLine:initialize(ns)
    if self.initialized then
        return self
    end
    self.incSearch = config.enable_incsearch
    self.ns = ns
    self.debouncedSearch = debounce(function()
        if not self.attached or self.type ~= fn.getcmdtype() then
            return
        end
        self:didChange()
        -- ^R ^[
        api.nvim_feedkeys(('%c%c'):format(0x12, 0x1b), 'in', false)
    end, 300)
    table.insert(self.disposables, disposable:create(function()
        self.initialized = false
        self.debouncedSearch:cancel()
        self.debouncedSearch = nil
    end))
    event:on('CmdlineEnter', function(cmdType)
        self:attach(cmdType)
    end, self.disposables)
    event:on('CmdlineLeave', function(cmdType, abort)
        self:detach(cmdType, abort)
        render:start(true)
    end, self.disposables)
    event:on('CmdlineChanged', function(cmdType)
        self:onChanged()
    end, self.disposables)
    self.initialized = true
    return self
end

return CmdLine
