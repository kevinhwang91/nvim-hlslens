local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local cmdl = require('hlslens.cmdl')
local render = require('hlslens.render')
local position = require('hlslens.position')
local config = require('hlslens.config')

local STATE = {START = 0, STOP = 1}
local status
local lastBufnr
local calmDown

local function init()
    calmDown = config.calm_down
    status = STATE.STOP
    lastBufnr = -1
end

local function reset()
    M.disable()
    M.enable()
end

local function autocmd(initial)
    cmd([[
        aug HlSearchLens
            au!
            au CmdlineEnter * lua require('hlslens.main').cmdLineEnter()
            au CmdlineLeave * lua require('hlslens.main').cmdLineLeave()
            au CmdlineChanged * lua require('hlslens.main').cmdLineChanged()
        aug END
    ]])
    if not initial then
        cmd([[
            aug HlSearchLens
                au CursorMoved,CursorMovedI * lua require('hlslens.main').refresh()
                au WinEnter,TermLeave,VimResized * lua require('hlslens.main').refresh(true)
                au TermEnter * lua require('hlslens.main').clearCurLens()
            aug END
        ]])
        if calmDown then
            cmd([[
                aug HlSearchLens
                    au TextChanged,TextChangedI * lua require('hlslens.main').nohAndReset()
                aug END
            ]])
        end
    end
end

local function mayInitialize()
    if status == STATE.STOP then
        autocmd()
        status = STATE.START
    end
end

local function cmdLineAbort()
    local cmdline = vim.trim(fn.getcmdline())
    if #cmdline > 2 then
        for _, cl in ipairs(vim.split(cmdline, '|')) do
            if ('nohlsearch'):match(vim.trim(cl)) then
                vim.schedule(reset)
                return
            end
        end
    end

    vim.schedule(function()
        local pattern = fn.getreg('/')
        if pattern == '' then
            reset()
        end
    end)
end

function M.cmdLineEnter()
    cmdl.attach(vim.v.event.cmdtype)
end

function M.cmdLineLeave()
    local e = vim.v.event
    local cmdType, abort = e.cmdtype, e.abort
    cmdl.detach(cmdType, abort)
    if cmdType == '/' or cmdType == '?' then
        if vim.o.hlsearch then
            mayInitialize()
            vim.schedule(function()
                M.refresh(true)
            end)
        end
    elseif cmdType == ':' then
        if status == STATE.START and not abort then
            cmdLineAbort()
        end
    end
end

function M.cmdLineChanged()
    cmdl.changed(vim.v.event.cmdtype)
end

function M.status()
    return status
end

function M.nohAndReset()
    vim.schedule(function()
        cmd('noh')
        reset()
    end)
end

function M.clearCurLens()
    render.clear(true, 0, true)
end

function M.clearLens()
    render.clearAll()
end

function M.enable()
    if status == STATE.STOP then
        autocmd(true)
        if api.nvim_get_mode().mode == 'c' then
            M.cmdLineEnter()
        end
        if vim.v.hlsearch == 1 and fn.getreg('/') ~= '' then
            M.start()
        end
    end
end

function M.disable()
    M.clearLens()
    position.clear()
    cmd('sil! au! HlSearchLens')
    status = STATE.STOP
end

function M.refresh(force)
    if vim.v.hlsearch == 0 then
        vim.schedule(function()
            if vim.v.hlsearch == 0 then
                reset()
            else
                M.refresh(force)
            end
        end)
        return
    end

    local bufnr = api.nvim_get_current_buf()
    local pattern = fn.getreg('/')
    if pattern == '' then
        reset()
        return
    end

    local posList = position.build(bufnr, pattern)
    local splist = posList.startPos

    local tmpBufnr = lastBufnr
    lastBufnr = bufnr

    if #splist == 0 then
        render.clear(true, bufnr, true)
        return
    end

    local curOffset
    local histSearch = fn.histget('/')
    if histSearch ~= pattern then
        local delim = vim.v.searchforward == 1 and '/' or '?'
        local sects = vim.split(histSearch, delim)
        if #sects > 1 then
            local p = table.concat(sects, delim, 1, #sects - 1)
            if p == '' or p == pattern then
                curOffset = sects[#sects]
            end
        end
    end

    local posInfo = position.nearestIdxInfo(posList, curOffset)

    local startPos = posInfo.startPos
    local endPos = posInfo.endPos
    local curPos = posInfo.curPos
    local offsetPos = posInfo.offsetPos

    local idx = posInfo.idx
    local rIdx = posInfo.rIdx

    local hit
    if not force and tmpBufnr == bufnr then
        hit = position.hitCache(bufnr, pattern, idx, rIdx)
        if hit and not calmDown then
            return
        end
    end
    position.updateCache(bufnr, pattern, idx, rIdx)

    if calmDown then
        if not position.inRange(startPos, endPos, curPos) then
            M.nohAndReset()
            return
        elseif hit then
            return
        end
    end

    render.addWinHighlight(0, startPos, endPos)
    render.doLens(splist, #offsetPos == 0, idx, rIdx)
end

function M.start(force)
    if vim.o.hlsearch then
        mayInitialize()
        M.refresh(force)
    end
end

init()

return M
