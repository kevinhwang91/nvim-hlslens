local event = require('hlslens.lib.event')
local disposable = require('hlslens.lib.disposable')
local utils = require('hlslens.utils')
local api = vim.api

---@class HlslensHighlight
local Highlight = {
    initialized = false,
    disposables = {}
}
local hlBlendGroups

local function resetHighlightGroup()
    api.nvim_set_hl(0, 'HlSearchNear', {
        default = true,
        link = 'IncSearch'
    })
    api.nvim_set_hl(0, 'HlSearchLens', {
        default = true,
        link = 'WildMenu'
    })
    api.nvim_set_hl(0, 'HlSearchLensNear', {
        default = true,
        link = 'IncSearch'
    })

    hlBlendGroups = setmetatable({Ignore = 'Ignore'}, {
        __index = function(tbl, hlGroup)
            local newHlGroup
            if vim.o.termguicolors then
                newHlGroup = 'HlSearchBlend_' .. hlGroup
                local hl
                if utils.has09() then
                    hl = api.nvim_get_hl(0, {name = hlGroup, link = false})
                else
                    --TODO
                    ---@diagnostic disable-next-line: deprecated
                    hl = api.nvim_get_hl_by_name(hlGroup, true)
                end
                hl.blend = 0
                api.nvim_set_hl(0, newHlGroup, hl)
            else
                newHlGroup = hlGroup
            end
            rawset(tbl, hlGroup, newHlGroup)
            return newHlGroup
        end
    })
end

function Highlight.hlBlendGroups()
    if not Highlight.initialized then
        Highlight:initialize()
    end
    return hlBlendGroups
end

---
---@return HlslensHighlight
function Highlight:initialize()
    if self.initialized then
        return self
    end
    self.disposables = {}
    event:on('ColorScheme', resetHighlightGroup, self.disposables)
    resetHighlightGroup()
    self.initialized = true
    return self
end

function Highlight:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
    self.initialized = false
end

return Highlight
