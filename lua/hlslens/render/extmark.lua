local api = vim.api

---@class HlslensRenderExtmark
local Extmark = {
    bufs = {},
    initialized = false
}

function Extmark:setVirtEol(bufnr, lnum, chunks, opts)
    bufnr = bufnr == 0 and api.nvim_get_current_buf() or bufnr
    self.bufs[bufnr] = true
    opts = opts or {}
    return api.nvim_buf_set_extmark(bufnr, self.ns, lnum, -1, {
        id = opts.id,
        virt_text = chunks,
        hl_mode = 'combine',
        priority = opts.priority or self.priority
    })
end

function Extmark:clearBuf(bufnr)
    if not bufnr then
        return
    end
    bufnr = bufnr == 0 and api.nvim_get_current_buf() or bufnr
    if self.bufs[bufnr] then
        if api.nvim_buf_is_valid(bufnr) then
            api.nvim_buf_clear_namespace(bufnr, self.ns, 0, -1)
        end
        self.bufs[bufnr] = nil
    end
end

function Extmark:clearAll()
    for bufnr in pairs(self.bufs) do
        self:clearBuf(bufnr)
    end
    self.bufs = {}
end

function Extmark:dispose()
    self:clearAll()
    self.initialized = false
end

function Extmark:initialize(namespace, priority)
    if self.initialized then
        return self
    end
    self.ns = namespace
    self.priority = priority
    self.bufs = {}
    self.initialized = true
    return self
end

return Extmark
