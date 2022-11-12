local event = require('hlslens.lib.event')
local disposable = require('hlslens.lib.disposable')
local cmd = vim.cmd
local api = vim.api

---@class HlslensHighlight
local Highlight = {
    disposables = {}
}
local initialized

local hlBlendGroups

local function hlAttrs(hlGroup)
    vim.validate({hlGroup = {hlGroup, 'string'}})
    local attrTbl = {
        'bold', 'standout', 'underline', 'undercurl', 'italic', 'reverse', 'strikethrough'
    }
    local t = {}
    local hlToTbl = function(gui)
        local ok, hl = pcall(api.nvim_get_hl_by_name, hlGroup, gui)
        if not ok then
            return
        end
        local fg, bg, colorFmt = hl.foreground, hl.background, gui and '#%x' or '%s'
        if fg then
            t[gui and 'guifg' or 'ctermfg'] = colorFmt:format(fg)
        end
        if bg then
            t[gui and 'guibg' or 'ctermbg'] = colorFmt:format(bg)
        end
        hl.foreground, hl.background = nil, nil
        local attrs = {}
        for attr in pairs(hl) do
            if vim.tbl_contains(attrTbl, attr) then
                table.insert(attrs, attr)
            end
        end
        t[gui and 'gui' or 'cterm'] = #attrs > 0 and attrs or nil
    end
    hlToTbl(true)
    hlToTbl(false)
    return t
end

local function resetHighlightGroup()
    cmd([[
        hi default link HlSearchNear IncSearch
        hi default link HlSearchLens WildMenu
        hi default link HlSearchLensNear IncSearch
        hi default link HlSearchFloat IncSearch
    ]])

    hlBlendGroups = setmetatable({Ignore = 'Ignore'}, {
        __index = function(tbl, hlGroup)
            local newHlGroup
            if vim.o.termguicolors then
                newHlGroup = 'HlSearchBlend_' .. hlGroup
                local hlCmdTbl = {'hi ' .. newHlGroup, 'blend=0'}
                for k, v in pairs(hlAttrs(hlGroup)) do
                    table.insert(hlCmdTbl, ('%s=%s'):format(k, type(v) == 'table' and
                        table.concat(v, ',') or v))
                end
                cmd(table.concat(hlCmdTbl, ' '))
            else
                newHlGroup = hlGroup
            end
            rawset(tbl, hlGroup, newHlGroup)
            return rawget(tbl, hlGroup)
        end
    })
end

function Highlight.hlBlendGroups()
    if not initialized then
        Highlight:initialize()
    end
    return hlBlendGroups
end

---
---@return HlslensHighlight
function Highlight:initialize()
    if initialized then
        return self
    end
    self.disposables = {}
    event:on('ColorScheme', resetHighlightGroup, self.disposables)
    resetHighlightGroup()
    initialized = true
    return self
end

function Highlight:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
    initialized = false
end

return Highlight
