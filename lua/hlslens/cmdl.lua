local M = {}
local fn = vim.fn
local cmd = vim.cmd
local api = vim.api

local utils = require('hlslens.utils')
local render = require('hlslens.render')
local config = require('hlslens.config')

local DUMMY_POS

local incsearch

local Search = {}

local cmdType

local incSearchCmd = {
    'substitute',
    'vglobal',
    'vimgrep',
    'vimgrepadd',
    'lvimgrep',
    'lvimgrepadd',
    'global'
}

local function fillDummyList(cnt)
    local posList = {}
    for _ = 1, cnt do
        table.insert(posList, DUMMY_POS)
    end
    return posList
end

local function renderLens(bufnr, idx, cnt, pos)
    -- To build a dummy list for compatibility
    local plist = fillDummyList(cnt)
    plist[idx] = pos
    render.addLens(bufnr, plist, true, idx, 0)
end

local function parseOffset(rawOffset)
    local _, _, char, sign, num = rawOffset:find('^([bes]?)([+-]?)(%d*)')
    local off = char
    if off == '' and sign == '' and num ~= '' then
        off = '+'
    end
    if num == '' and sign ~= '' then
        off = off .. sign .. '1'
    else
        off = off .. sign .. num
    end
    return off
end

local function splitCmdLine(cmdl, cmdt)
    local pat
    local off = ''
    local mul = false
    local delim = cmdt or '/'
    local i = 0
    local start = i + 1

    while true do
        i = cmdl:find(delim, i + 1)
        if not i then
            pat = cmdl:sub(start)
            break
        end
        if cmdl:sub(i - 1, i - 1) ~= [[\]] then
            -- For example: "/pat/;/foo/+3;?bar"
            if cmdl:sub(i + 1, i + 1) == ';' then
                i = i + 2
                start = i + 1
                delim = cmdl:sub(i, i)
                if i <= #cmdl then
                    mul = true
                end
            else
                pat = cmdl:sub(start, i - 1)
                if pat == '' then
                    pat = fn.getreg('/')
                end
                off = cmdl:sub(i + 1)
                break
            end
        end
    end
    return pat, off, mul
end

local function filter(pat)
    if #pat <= 2 then
        if #pat < 2 or pat:sub(1, 1) == [[\]] or pat == '..' then
            return false
        end
    end
    return true
end

local function closeFold(closedLnum)
    if closedLnum > 0 then
        while fn.foldclosed(closedLnum) == -1 do
            cmd(closedLnum .. 'foldclose')
        end
    end
end

function Search:resetState()
    self.currentIdx = 0
    self.total = 0
end

function Search:doRender(bufnr, pos)
    if self.foldInfo then
        closeFold(self.foldInfo.lnum)
        self.foldInfo.lnum = -1

        local closedLnum = fn.foldclosed(pos[1])
        if closedLnum > 0 then
            self.foldInfo.lnum = closedLnum
            cmd('norm! zv')
        end
    end
    render.clear(true, bufnr, true)
    renderLens(bufnr, self.currentIdx, self.total, pos)
end

---may_do_incsearch_highlighting
---@param bufnr number
function Search:doSearch(bufnr)
    local ret = false
    api.nvim_win_set_cursor(0, self.searchStart)
    local pos = fn.searchpos(self.pattern, cmdType == '?' and 'bc' or 'c')
    local res
    ret, res = pcall(fn.searchcount, {
        recompute = true,
        maxcount = 100000,
        timeout = 100,
        pattern = self.pattern
    })
    if ret then
        if res.incomplete == 0 and res.total and res.total > 0 then
            self.currentIdx = res.current
            self.total = res.total
            self:doRender(bufnr, pos)
        else
            self:resetState()
            render.clear(true, bufnr, true)
        end
    end
    return ret
end

---may_do_command_line_next_incsearch
---@param bufnr number
---@param forward boolean
function Search:doCmdLineNextIncSearch(bufnr, forward)
    local pos
    if self.delimClosed then
        fn.searchpos(self.pattern, 'e')
        self.delimClosed = false
    end
    local cursor = api.nvim_win_get_cursor(0)
    if forward then
        pos = fn.searchpos(self.pattern, '')
    else
        fn.searchpos(self.pattern, 'b')
        pos = fn.searchpos(self.pattern, 'b')
    end
    if utils.comparePosition(pos, {0, 0}) == 0 then
        return
    end
    local pos1 = {pos[1], pos[2] - 1}
    if forward then
        self.searchStart = cmdType == '?' and pos1 or cursor
        self.currentIdx = self.currentIdx == self.total and 1 or self.currentIdx + 1
        -- wrap around
        if utils.comparePosition(pos1, self.searchStart) < 0 then
            self.searchStart = pos1
        end
    else
        self.searchStart = cmdType ~= '?' and pos1 or cursor
        self.currentIdx = self.currentIdx == 1 and self.total or self.currentIdx - 1
    end
    if self.offset == '' and not self.multiple then
        self:doRender(bufnr, pos)
    end
end

local function incSearchEnabled()
    return incsearch and vim.o.is
end

function Search:attach()
    if not incSearchEnabled() then
        return
    end

    if vim.o.fdo:find('search') and vim.wo.foldenable then
        self.foldInfo = {lnum = -1}
    end

    self.cmdLine = ''
    self:resetState()
    self.saveCurosr = api.nvim_win_get_cursor(0)
    self.searchStart = self.saveCurosr
    local bufnr = api.nvim_get_current_buf()
    self.cmdIncSearching = true
    self.onKey(function(char)
        if not self.cmdIncSearching then
            return
        end
        local b1, b2 = char:byte(1, -1)
        -- <C-g> = 0x7
        -- <C-t> = 0x14
        if b2 == nil and self.currentIdx > 0 and self.total > 0 and (b1 == 0x07 or b1 == 0x14) then
            -- TODO
            -- %s/pat is buggy here
            if self.subCmdDoSearch then
                self:resetState()
                render.clear(true, bufnr, true)
                self.subCmdDoSearch = nil
            else
                self:doCmdLineNextIncSearch(bufnr, b1 == 0x07)
            end
        end
    end, self.ns)
end

function Search:changed()
    if not cmdType or not incSearchEnabled() then
        return
    end

    local cmdl = fn.getcmdline()
    if cmdl == '' then
        self.searchStart = self.saveCurosr
    end
    if self.cmdLine == cmdl then
        return
    else
        self.cmdLine = cmdl
    end

    local bufnr = api.nvim_get_current_buf()
    if cmdType == ':' and api.nvim_parse_cmd then
        local ok, parsed = pcall(api.nvim_parse_cmd, cmdl, {})
        if not ok or #parsed.args == 0 or not vim.tbl_contains(incSearchCmd, parsed.cmd) then
            if not ok then
                -- TODO
                -- may throw error, need an extra pcall command to eat it
                pcall(cmd, '')
            end
            self.cmdIncSearching = false
            return
        end
        ---@type string
        local arg = table.concat(parsed.args, ' ')
        local firstByte = arg:byte(1, 1)
        local opening
        local i = 2
        self.delimClosed = false
        if parsed.cmd == 'global' then
            arg = arg:match('^%s*(.*)$')
        elseif parsed.cmd == 'substitute' then
            self.subCmdDoSearch = true
        elseif 48 <= firstByte and firstByte <= 57 or
            65 <= firstByte and firstByte <= 90 or 97 <= firstByte and firstByte <= 122 then
            opening = ' '
            i = 1
        end
        local pat
        if #arg == 1 and parsed.cmd == 'substitute' then
            pat = fn.getreg('/')
        elseif #arg == 2 and firstByte == arg:byte(-1) then
            self.delimClosed = true
            pat = fn.getreg('/')
        else
            opening = opening and opening or string.char(firstByte)
            local s = arg:find(opening, 2, true)
            if s then
                self.delimClosed = true
                pat = arg:sub(i, s - 1)
            else
                pat = arg:sub(i)
            end
        end
        self.cmdIncSearching = true
        self.pattern, self.offset, self.multiple = pat, '', false
        if parsed.cmd == 'substitute' then
            render.clear(true, bufnr, true)
            if self.delimClosed then
                return
            end
        end
    else
        self.pattern, self.offset, self.multiple = splitCmdLine(cmdl, cmdType)
    end

    if self.pattern then
        if filter(self.pattern) then
            local res = self:doSearch(bufnr)
            if res and self.subCmdDoSearch and self.currentIdx > 0 and self.total > 0 then
                local winid = api.nvim_get_current_win()
                local startPos = api.nvim_win_get_cursor(winid)
                startPos[2] = startPos[2] + 1
                local endPos = fn.searchpos(self.pattern, 'cen')
                render.addWinHighlight(winid, startPos, endPos)
            end
        else
            render.clear(true, bufnr, true)
        end
    end
end

function Search:detach(abort)
    self.offset = parseOffset(self.offset)
    self.cmdLine = nil
    self.onKey(nil, self.ns)

    if self.timer and self.timer:has_ref() then
        self.timer:stop()
        if not self.timer:is_closing() then
            self.timer:close()
        end
    end

    if self.foldInfo and abort then
        closeFold(self.foldInfo.lnum)
    end
    self.foldInfo = nil
    render.clear(true, api.nvim_get_current_buf(), true)
end

local function skipType(typ)
    return not (typ == '/' or typ == '?' or typ == ':')
end

function M.attach(typ)
    cmdType = typ
    if skipType(typ) then
        return
    end
    Search:attach()
end

function M.changed()
    Search:changed()
end

function M.detach(typ, abort)
    cmdType = nil
    if skipType(typ) then
        return
    end
    Search:detach(abort)
end

local function init()
    incsearch = config.enable_incsearch
    DUMMY_POS = {1, 1}
    Search.pattern = ''
    Search.offset = ''
    Search.multiple = false
    Search.foldInfo = nil
    Search.cmdLine = ''
    Search.saveCurosr = {1, 0}
    Search.searchStart = Search.saveCurosr
    Search:resetState()
    Search.ns = api.nvim_create_namespace('hlslens')
    Search.onKey = vim.on_key and vim.on_key or vim.register_keystroke_callback
end

init()

return M
