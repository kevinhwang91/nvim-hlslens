local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local cmdl = require('hlslens.cmdline')
local render = require('hlslens.render')
local position = require('hlslens.position')
local highlight = require('hlslens.highlight')
local disposable = require('hlslens.lib.disposable')

local enabled = false

local disposables = {}

local function createCommand()
    cmd([[
        com! HlSearchLensToggle lua require('hlslens').toggle()
        com! HlSearchLensEnable lua require('hlslens').enable()
        com! HlSearchLensDisable lua require('hlslens').disable()
    ]])
end

local function createEvents()
    cmd([[
        aug HlSearchLens
            au!
            au CmdlineEnter /,\?,: lua require('hlslens.lib.event'):emit('CmdlineEnter', vim.v.event)
            au CmdlineLeave /,\?,: lua require('hlslens.lib.event'):emit('CmdlineLeave', vim.v.event)
            au CmdlineChanged /,\?,: lua require('hlslens.lib.event'):emit('CmdlineChanged')
            au ColorScheme * lua require('hlslens.lib.event'):emit('ColorScheme')
        aug END
    ]])
    return disposable:create(function()
        cmd([[
            au! HlSearchLens
            aug! HlSearchLens
        ]])
    end)
end

function M.enable()
    if enabled then
        return false
    end
    enabled = true
    local ns = api.nvim_create_namespace('hlslens')
    createCommand()
    disposables = {}
    table.insert(disposables, createEvents())
    table.insert(disposables, highlight:initialize())
    table.insert(disposables, position:initialize())
    table.insert(disposables, render:initialize(ns))
    table.insert(disposables, cmdl:initialize(ns))

    if vim.v.hlsearch == 1 and fn.getreg('/') ~= '' then
        render:start()
    end
    return true
end

function M.disable()
    if not enabled then
        return false
    end
    disposable.disposeAll(disposables)
    disposables = {}
    enabled = false
    return true
end

function M.isEnabled()
    return enabled
end

function M.start()
    if enabled then
        render:start()
    end
    return enabled
end

function M.stop()
    if enabled then
        render:stop()
    end
    return enabled
end

return M
