local api = vim.api

local utils     = require('hlslens.utils')
local highlight = require('hlslens.highlight')
local extmark   = require('hlslens.render.extmark')

---@class HlslensRenderFloatWin
---@field initialized boolean
---@field winid number
---@field bufnr number
---@field shadowBlend number
---@field virtTextId number
local FloatWin = {
    initialized = false
}

function FloatWin:close()
    local ok = true
    if self.winid and api.nvim_win_is_valid(self.winid) then
        -- suppress error in cmdwin
        ok = pcall(api.nvim_win_close, self.winid, true)
    end
    if ok then
        self.winid = nil
    end
end

function FloatWin:open(row, col, width)
    local conf = {
        relative = 'win',
        width = math.max(1, width),
        height = 1,
        row = row,
        col = col,
        focusable = false,
        style = 'minimal',
        zindex = 150
    }
    if self.winid and api.nvim_win_is_valid(self.winid) then
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

function FloatWin:updateFloatWin(winid, pos, chunks, text, lineWidth, gutterSize)
    local width, height = api.nvim_win_get_width(winid), api.nvim_win_get_height(winid)
    local floatCol = utils.vcol(winid, pos) % lineWidth + gutterSize - 1
    if vim.o.termguicolors then
        self:open(height, 0, width)
        vim.wo[self.winid].winbl = self.shadowBlend
        local padding = (' '):rep(math.min(floatCol, width - #text) - 1)
        local newChunks = {{padding, 'Ignore'}}
        for _, chunk in ipairs(chunks) do
            local t, hlgroup = unpack(chunk)
            if not t:match('^%s+$') and hlgroup ~= 'Ignore' then
                table.insert(newChunks, {t, highlight.hlBlendGroups()[hlgroup]})
            end
        end
        self.virtTextId = extmark:setVirtEol(self.bufnr, 0, newChunks, {id = self.virtTextId})
    else
        self:open(height, floatCol, #text)
        vim.wo[self.winid].winhl = 'Normal:HlSearchFloat'
        api.nvim_buf_set_lines(self.bufnr, 0, 1, true, {text})
    end
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
