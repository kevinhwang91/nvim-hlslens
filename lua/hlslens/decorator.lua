local disposable = require('hlslens.lib.disposable')
local event = require('hlslens.lib.event')
local api = vim.api

local Decorator = {
    initialized = false,
    disposables = {}
}

---@diagnostic disable-next-line: unused-local
local function onStart(name, tick)
    if api.nvim_get_mode().mode == 't' then
        return false
    end
    local self = Decorator
    self.winid = api.nvim_get_current_win()
end

---@diagnostic disable-next-line: unused-local
local function onWin(name, winid, bufnr, topRow, botRow)
    local self = Decorator
    if self.winid ~= winid then
        return false
    end
    local winWidth = api.nvim_win_get_width(winid)
    if not (bufnr == self.bufnr and topRow == self.topRow and botRow == self.botRow and
            winWidth == self.winWidth) then
        -- if window contained empty lines at the bottom, like scrolled up near the last line,
        -- closing fold may make topRow == self.topRow and botRow == self.botRow.
        event:emit('RegionChanged')
        -- event:emit('RegionChanged', bufnr, winid, topRow, botRow, winWidth)
    end
    self.bufnr, self.topRow, self.botRow, self.winWidth = bufnr, topRow, botRow, winWidth
    return false
end

---@diagnostic disable-next-line: unused-local
local function onEnd(name)
    if vim.v.hlsearch == 0 then
        event:emit('HlSearchCleared')
    end
end

function Decorator:initialize(namespace)
    if self.initialized then
        return self
    end
    self.ns = namespace
    api.nvim_set_decoration_provider(self.ns, {
        on_start = onStart,
        on_win = onWin,
        on_end = onEnd
    })
    table.insert(self.disposables, disposable:create(function()
        api.nvim_set_decoration_provider(self.ns, {})
        self.initialized = false
    end))
    self.initialized = true
    return self
end

function Decorator:dispose()
    disposable.disposeAll(self.disposables)
    self.disposables = {}
end

return Decorator
