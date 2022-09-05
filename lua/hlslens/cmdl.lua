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
local ns

local function refreshLens()
    -- ^R ^[
    api.nvim_feedkeys(('%c%c'):format(0x12, 0x1b), 'in', false)
end

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
    refreshLens()
end

local function clearLens(bufnr)
    render.clear(false, bufnr, true)
    refreshLens()
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
        if #pat == 1 or pat:sub(1, 1) == [[\]] or pat == '..' then
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

function Search:doSearch(bufnr, delay)
    bufnr = bufnr or api.nvim_get_current_buf()
    self.timer = utils.killableDefer(self.timer, function()
        if cmdType == fn.getcmdtype() then
            local ok, msg = pcall(fn.searchcount, {
                recompute = true,
                maxcount = 100000,
                timeout = 100,
                pattern = self.pattern
            })
            if ok then
                local res = msg
                if res.incomplete == 0 and res.total and res.total > 0 then
                    render.clear(false, bufnr)

                    local idx = res.current

                    local pos = fn.searchpos(self.pattern, 'bcnW')

                    if self.foldInfo then
                        closeFold(self.foldInfo.lnum)
                        self.foldInfo.lnum = -1

                        local closedLnum = fn.foldclosed(pos[1])
                        if closedLnum > 0 then
                            self.foldInfo.lnum = closedLnum
                            cmd('norm! zv')
                        end
                    end
                    renderLens(bufnr, idx, res.total, pos)
                else
                    clearLens(bufnr)
                end
            end
        end
    end, delay or 0)
end

local function incSearchEnabled()
    return incsearch and vim.o.is
end

function Search:attach()
    if not incSearchEnabled() then
        return
    elseif not utils.jitEnabled() and utils.isCmdLineWin() then
        return
    end

    if vim.o.fdo:find('search') and vim.wo.foldenable then
        self.foldInfo = {lnum = -1}
    end

    self.cmdLine = ''
    self.onKey(function(char)
        local b1, b2, b3 = char:byte(1, -1)
        if b1 == 0x07 or b1 == 0x14 then
            -- <C-g> = 0x7
            -- <C-t> = 0x14
            if self.offset == '' and not self.multiple then
                self:doSearch()
            end
        elseif b1 == 0x80 and b2 == 0x6b and (b3 == 0x64 or b3 == 0x75) then
            -- <Up> = 0x80 0x6b 0x75
            -- <Down> = 0x80 0x6b 0x64
            -- TODO https://github.com/kevinhwang91/nvim-hlslens/issues/18
            self.skip = true
            render.clear(false, 0, true)
        end
    end, ns)
end

function Search:changed()
    if self.skip then
        self.skip = false
        return
    end

    if not incSearchEnabled() then
        return
    end

    local cmdl = fn.getcmdline()
    if self.cmdLine == cmdl then
        return
    else
        self.cmdLine = cmdl
    end

    self.pattern, self.offset, self.multiple = splitCmdLine(cmdl, cmdType)

    local bufnr = api.nvim_get_current_buf()
    render.clear(true)

    if filter(self.pattern) then
        self:doSearch(bufnr, 50)
    else
        self.timer = utils.killableDefer(self.timer, function()
            if cmdType == fn.getcmdtype() then
                clearLens(bufnr)
            end
        end, 0)
    end
end

function Search:detach(abort)
    self.offset = parseOffset(self.offset)

    self.cmdLine = nil

    self.onKey(nil, ns)

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
end

function M.attach(typ)
    if typ == '/' or typ == '?' then
        Search:attach()
    end
    cmdType = typ
end

function M.changed(typ)
    if typ == '/' or typ == '?' then
        Search:changed()
    end
end

function M.detach(typ, abort)
    if typ == '/' or typ == '?' then
        Search:detach(abort)
    end
    cmdType = nil
end

local function init()
    incsearch = config.enable_incsearch
    DUMMY_POS = {1, 1}
    Search.pattern = ''
    Search.offset = ''
    Search.multiple = false
    Search.skip = false
    Search.foldInfo = nil
    Search.onKey = vim.on_key and vim.on_key or vim.register_keystroke_callback
    ns = api.nvim_create_namespace('hlslens')
end

init()

return M
