local M = {}
local api = vim.api
local fn = vim.fn

local event = require('hlslens.lib.event')
local cmdl = require('hlslens.cmdline')
local render = require('hlslens.render')
local position = require('hlslens.position')
local highlight = require('hlslens.highlight')
local disposable = require('hlslens.lib.disposable')

local enabled = false

local disposables = {}

local function createCommand()
    api.nvim_create_user_command('HlSearchLensToggle', function()
        return require('hlslens').toggle()
    end, {})
    api.nvim_create_user_command('HlSearchLensEnable', function()
        return require('hlslens').enable()
    end, {})
    api.nvim_create_user_command('HlSearchLensDisable', function()
        return require('hlslens').disable()
    end, {})
end

local function createEvents()
    local gid = api.nvim_create_augroup('HlSearchLens', {})
    api.nvim_create_autocmd({'CmdlineEnter', 'CmdlineLeave', 'CmdlineChanged'}, {
        pattern = {'/', '?', ':'},
        group = gid,
        callback = function(ev)
            local e, cchar = ev.event, ev.file
            if e == 'CmdlineLeave' then
                event:emit(e, cchar, vim.v.event.abort)
            else
                event:emit(e, cchar)
            end
        end
    })
    return disposable:create(function()
        api.nvim_del_augroup_by_id(gid)
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
    local ok, res = pcall(require, 'ufo')
    if ok then
        table.insert(disposables, require('hlslens.ext.ufo'):initialize(res))
    end

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

function M.exportToQuickfix(isLocation)
    if not enabled then
        return false
    end
    return require('hlslens.qf').exportRanges(isLocation)
end

return M
