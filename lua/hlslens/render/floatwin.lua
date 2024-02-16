local api = vim.api
local fn = vim.fn

local utils = require('hlslens.utils')
local highlight = require('hlslens.highlight')
local extmark = require('hlslens.render.extmark')

---@class HlslensRenderFloatWin
---@field initialized boolean
---@field winid number
---@field bufnr number
---@field shadowBlend number
local FloatWin = {
    initialized = false
}

function FloatWin:close()
    local ok = true
    if utils.isWinValid(self.winid) then
        -- suppress error in cmdwin
        ok = pcall(api.nvim_win_close, self.winid, true)
    end
    if ok then
        self.winid = nil
    end
end

function FloatWin.getConfig(winid)
    local config = api.nvim_win_get_config(winid)
    if config.relative == '' then
        return
    end
    local row, col = config.row, config.col
    -- row and col are a table value converted from the floating-point
    if type(row) == 'table' then
        ---@diagnostic disable-next-line: need-check-nil, inject-field
        config.row, config.col = tonumber(row[vim.val_idx]), tonumber(col[vim.val_idx])
    end
    return config
end

local function borderHasBottomLine(border)
    if border == nil then
        return false
    end

    local s = border[6]
    if type(s) == 'string' then
        return s ~= ''
    else
        return s[1] ~= ''
    end
end

function FloatWin:open(winid, row, col, width)
    local conf = {
        win = winid,
        relative = 'win',
        width = math.max(1, width),
        height = 1,
        row = row,
        col = col,
        focusable = false,
        style = 'minimal',
        zindex = 150
    }
    if utils.isWinValid(self.winid) then
        self.bufnr = api.nvim_win_get_buf(self.winid)
        api.nvim_win_set_config(self.winid, conf)
    else
        self.bufnr = api.nvim_create_buf(false, true)
        vim.bo[self.bufnr].bufhidden = 'wipe'
        conf.noautocmd = true
        self.winid = api.nvim_open_win(self.bufnr, false, conf)
    end
    return self.winid, self.bufnr
end

function FloatWin:renderLine(chunks)
    local sects = {}
    local marks = {}
    local i = 0
    for _, chunk in ipairs(chunks) do
        local t, hlGroup = unpack(chunk)
        table.insert(sects, t)
        if hlGroup ~= '' then
            table.insert(marks, {hlGroup = hlGroup, col = i, endCol = i + #t})
        end
        i = i + #t
    end
    extmark:clearHighlight(self.bufnr)
    api.nvim_buf_set_lines(self.bufnr, 0, -1, true, {table.concat(sects, '')})
    for _, mark in ipairs(marks) do
        extmark:setHighlight(self.bufnr, mark.hlGroup, {0, mark.col}, {0, mark.endCol})
    end
end

function FloatWin:updateFloatWin(winid, pos, chunks, text, lineWidth, textOff)
    local width, height = api.nvim_win_get_width(winid), api.nvim_win_get_height(winid)
    local floatCol = utils.vcol(winid, pos) % lineWidth + textOff - 1
    local s, e = text:find('^%s*', 1)
    s = e + 1
    e = text:find('%s*$', s) - 1
    local textWidth = fn.strdisplaywidth(text:sub(s, e))
    local newChunks = {}
    local winConfig = self.getConfig(winid)
    if winConfig and borderHasBottomLine(winConfig.border) or not vim.o.termguicolors then
        self:open(winid, height, floatCol, textWidth)
        vim.wo[self.winid].winbl = 0
    else
        self:open(winid, height, 0, width)
        vim.wo[self.winid].winbl = self.shadowBlend
        vim.wo[self.winid].winhl = 'Normal:StatusLine'
        local padding = (' '):rep(math.min(floatCol, width - textWidth))
        table.insert(newChunks, {padding, ''})
    end
    local i = 1
    for _, chunk in ipairs(chunks) do
        local t, hlGroup = unpack(chunk)
        local len = #t
        if i + len > s then
            if i < s then
                t = t:sub(s - i + 1)
            end
            if i + len - 1 > e then
                t = t:sub(1, e)
            end
            table.insert(newChunks, {t, highlight.hlBlendGroups()[hlGroup]})
        end
        i = i + len
        if i > e then
            break
        end
    end
    self:renderLine(newChunks)
end

function FloatWin:dispose()
    self.initialized = false
    self:close()
end

function FloatWin:initialize(shadowBlend)
    if self.initialized then
        return self
    end
    self.shadowBlend = shadowBlend
    self.initialized = true
    return self
end

return FloatWin
