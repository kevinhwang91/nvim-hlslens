local M = {}
local fn = vim.fn
local api = vim.api
local cmd = vim.cmd

---
---@return fun(): boolean
M.has08 = (function()
    local has08
    return function()
        if has08 == nil then
            has08 = fn.has('nvim-0.8') == 1
        end
        return has08
    end
end)()

---@return fun(): boolean
M.has09 = (function()
    local has09
    return function()
        if has09 == nil then
            has09 = fn.has('nvim-0.9') == 1
        end
        return has09
    end
end)()

---
---@param winid number
---@return boolean
function M.isWinValid(winid)
    return type(winid) == 'number' and winid > 0 and api.nvim_win_is_valid(winid)
end

---
---@param items table
---@param element any
---@param comp fun(any, any)
---@return number
function M.binSearch(items, element, comp)
    vim.validate({items = {items, 'table'}, comp = {comp, 'function'}})
    local min, max, mid = 1, #items, 1
    local r = 0
    while min <= max do
        mid = math.floor((min + max) / 2)
        r = comp(items[mid], element)
        if r == 0 then
            return mid
        elseif r > 0 then
            max = mid - 1
        else
            min = mid + 1
        end
    end
    return -min
end

---
---@param p1 number[]
---@param p2 number[]
---@return number|-1|0|1
function M.comparePosition(p1, p2)
    if p1[1] == p2[1] then
        if p1[2] == p2[2] then
            return 0
        else
            return p1[2] > p2[2] and 1 or -1
        end
    else
        return p1[1] > p2[1] and 1 or -1
    end
end

function M.getWinInfo(winid)
    local winfos = fn.getwininfo(winid)
    assert(type(winfos) == 'table' and #winfos == 1,
        '`getwininfo` expected 1 table with single element.')
    return winfos[1]
end

---
---@param winid number
---@return number
function M.lineWidth(winid)
    local textOff = M.textOff(winid)
    return api.nvim_win_get_width(winid) - textOff
end

---
---@param winid number
---@return number
function M.textOff(winid)
    vim.validate({winid = {winid, 'number'}})
    return M.getWinInfo(winid).textoff
end

---
---@param bufnr? number
---@return boolean
function M.isCmdLineWin(bufnr)
    local function isCmdWin()
        return fn.bufname() == '[Command Line]'
    end

    return bufnr and api.nvim_buf_call(bufnr, isCmdWin) or isCmdWin()
end

---
---@param winid number
---@param pos number[]
---@return number
function M.vcol(winid, pos)
    local vcol = M.winCall(winid, function()
        return fn.virtcol(pos)
    end)
    if not vim.wo[winid].wrap then
        vcol = vcol - M.winCall(winid, fn.winsaveview).leftcol
    end
    return vcol
end

---
---@param winid number
---@param lnum number
---@return number
function M.foldClosed(winid, lnum)
    return M.winCall(winid, function()
        return fn.foldclosed(lnum)
    end)
end

---
---@param hlGroup string
---@param plist table
---@param prior? number
---@param winid? number
---@return number[]
function M.matchAddPos(hlGroup, plist, prior, winid)
    vim.validate({
        hlGroup = {hlGroup, 'string'},
        plist = {plist, 'table'},
        prior = {prior, 'number', true},
        winid = {winid, 'number'}
    })
    prior = prior or 10

    local ids = {}
    local l = {}
    for i, p in ipairs(plist) do
        table.insert(l, p)
        if i % 8 == 0 then
            table.insert(ids, fn.matchaddpos(hlGroup, l, prior, -1, {window = winid}))
            l = {}
        end
    end
    if #l > 0 then
        table.insert(ids, fn.matchaddpos(hlGroup, l, prior, -1, {window = winid}))
    end
    return ids
end

---
---@param winid number
---@param f fun(): any
---@return ...
function M.winCall(winid, f)
    if winid == 0 or winid == api.nvim_get_current_win() then
        return f()
    else
        local curWinid = api.nvim_get_current_win()
        local noaSetWin = 'noa call nvim_set_current_win(%d)'
        cmd(noaSetWin:format(winid))
        local r = {pcall(f)}
        cmd(noaSetWin:format(curWinid))
        assert(r[1], r[2])
        return unpack(r, 2)
    end
end

---
---@param pattern string
---@param flags? string
---@param stopline? number
---@param timeout? number
---@param skip? any
---@return number[]
function M.searchPosSafely(pattern, flags, stopline, timeout, skip)
    -- TODO
    -- Pass `nil` to pcall with Neovim function make serialization issue, need `unpack` as a
    -- helper to prevent `nil` to pass.
    local ok, res = pcall(fn.searchpos, pattern, unpack({flags, stopline, timeout, skip}))
    return ok and res or {0, 0}
end

---
---@param bufnr number
---@return number, number[]?
function M.getWinByBuf(bufnr)
    local curBufnr
    if not bufnr then
        curBufnr = api.nvim_get_current_buf()
        bufnr = curBufnr
    end
    local winids = {}
    for _, winid in ipairs(api.nvim_list_wins()) do
        if bufnr == api.nvim_win_get_buf(winid) then
            table.insert(winids, winid)
        end
    end
    if #winids == 0 then
        return -1
    elseif #winids == 1 then
        return winids[1]
    else
        if not curBufnr then
            curBufnr = api.nvim_get_current_buf()
        end
        local winid = curBufnr == bufnr and api.nvim_get_current_win() or winids[1]
        return winid, winids
    end
end

return M
