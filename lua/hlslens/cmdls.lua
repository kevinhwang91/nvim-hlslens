local M = {}
local fn = vim.fn
local cmd = vim.cmd
local api = vim.api

local utils = require('hlslens.utils')
local render = require('hlslens.render')
local config = require('hlslens.config')

local DUMMY_POS

local incsearch

local foldInfo

local lastCmdLine
local cmdType

local lastPattern
local lastOffset
local lastMul

local ns
local timer

local skip

local onKey

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

local function closeFold(level, targetLine, curLine)
    if targetLine > 0 then
        curLine = curLine or api.nvim_win_get_cursor(0)[1]
        level = level or 1
        cmd(('keepj norm! %dgg%dzc%dgg'):format(targetLine, level, curLine))
    end
end

local function doSearch(bufnr, delay)
    bufnr = bufnr or api.nvim_get_current_buf()
    timer = utils.killableDefer(timer, function()
        if cmdType == fn.getcmdtype() then
            local ok, msg = pcall(fn.searchcount, {
                recompute = true,
                maxcount = 100000,
                timeout = 100,
                pattern = lastPattern
            })
            if ok then
                local res = msg
                if res.incomplete == 0 and res.total and res.total > 0 then
                    render.clear(false, bufnr)

                    local idx = res.current

                    local pos = fn.searchpos(lastPattern, 'bcnW')

                    if foldInfo then
                        closeFold(foldInfo.level, foldInfo.lnum)
                        foldInfo.lnum = -1

                        local lnum = pos[1]
                        if fn.foldclosed(lnum) > 0 then
                            foldInfo.lnum = lnum
                            foldInfo.level = fn.foldlevel(lnum)
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
    return vim.o.is and incsearch
end

function M.searchAttach()
    if not incSearchEnabled() then
        return
    elseif not utils.jitEnabled() and utils.isCmdLineWin() then
        return
    end

    if vim.o.fdo:find('search') and vim.wo.foldenable then
        foldInfo = {lnum = -1}
    end

    lastCmdLine = ''
    cmdType = vim.v.event.cmdtype
    onKey(function(char)
        local b1, b2, b3 = char:byte(1, -1)
        if b1 == 0x07 or b1 == 0x14 then
            -- <C-g> = 0x7
            -- <C-t> = 0x14
            if lastOffset == '' and not lastMul then
                doSearch()
            end
        elseif b1 == 0x80 and b2 == 0x6b and (b3 == 0x64 or b3 == 0x75) then
            -- <Up> = 0x80 0x6b 0x75
            -- <Down> = 0x80 0x6b 0x64
            -- TODO https://github.com/kevinhwang91/nvim-hlslens/issues/18
            skip = true
            render.clear(false, 0, true)
        end
    end, ns)
end

function M.searchChanged()
    if skip then
        skip = false
        return
    end

    if not incSearchEnabled() then
        return
    end

    local cmdl = fn.getcmdline()
    if lastCmdLine == cmdl then
        return
    else
        lastCmdLine = cmdl
    end

    lastPattern, lastOffset, lastMul = splitCmdLine(cmdl, cmdType)

    local bufnr = api.nvim_get_current_buf()
    render.clear(true)

    if filter(lastPattern) then
        doSearch(bufnr, 50)
    else
        timer = utils.killableDefer(timer, function()
            if cmdType == fn.getcmdtype() then
                clearLens(bufnr)
            end
        end, 0)
    end
end

function M.searchDetach()
    lastOffset = parseOffset(lastOffset)

    lastCmdLine = nil
    cmdType = nil

    onKey(nil, ns)

    if timer and timer:has_ref() then
        timer:stop()
        if not timer:is_closing() then
            timer:close()
        end
    end

    if foldInfo and vim.v.event.abort then
        closeFold(foldInfo.level, foldInfo.lnum)
    end
    foldInfo = nil
end

local function init()
    DUMMY_POS = {1, 1}
    lastPattern = ''
    lastOffset = ''
    lastMul = false
    skip = false
    ns = api.nvim_create_namespace('hlslens')
    incsearch = config.enable_incsearch
    foldInfo = nil
    onKey = vim.on_key and vim.on_key or vim.register_keystroke_callback
end

init()

return M
