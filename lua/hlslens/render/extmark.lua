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

---
---@param bufnr number
---@param hlGroup string
---@param start number|number[]
---@param finish number|number[]
---@param opts? table
---@return number[]
function Extmark:setHighlight(bufnr, hlGroup, start, finish, opts)
    local function doUnPack(pos)
        vim.validate({
            pos = {
                pos, function(p)
                    local t = type(p)
                    return t == 'table' or t == 'number'
                end, 'must be table or number type'
            }
        })
        local row, col
        if type(pos) == 'table' then
            row, col = unpack(pos)
        else
            row = pos
        end
        col = col or 0
        return row, col
    end

    local function rangeToRegion(row, col, endRow, endCol)
        local region = {}
        if row > endRow or (row == endRow and col >= endCol) then
            return region
        end
        if row == endRow then
            region[row] = {col, endCol}
            return region
        end
        region[row] = {col, -1}
        for i = row + 1, endRow - 1 do
            region[i] = {0, -1}
        end
        if endCol > 0 then
            region[endRow] = {0, endCol}
        end
        return region
    end

    local row, col = doUnPack(start)
    local endRow, endCol = doUnPack(finish)
    local o = opts and vim.deepcopy(opts) or {}
    o.hl_group = hlGroup
    local ids = {}
    local region = rangeToRegion(row, col, endRow, endCol)
    for sr, range in pairs(region) do
        local sc, ec = range[1], range[2]
        local er
        if ec == -1 or ec == 2147483647 then
            er = sr + 1
            ec = 0
        end
        o.end_row = er
        o.end_col = ec
        table.insert(ids, api.nvim_buf_set_extmark(bufnr, self.hlNs, sr, sc, o))
    end
    return ids
end

function Extmark:clearHighlight(bufnr)
    api.nvim_buf_clear_namespace(bufnr, self.hlNs, 0, -1)
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
    self.hlNs = self.hlNs or api.nvim_create_namespace('')
    self.priority = priority
    self.bufs = {}
    self.initialized = true
    return self
end

return Extmark
