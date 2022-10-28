local M = {}
local fn = vim.fn
local api = vim.api
local cmd = vim.cmd
local uv = vim.loop

M.has08 = (function()
    local has08
    return function()
        if has08 == nil then
            has08 = fn.has('nvim-0.8') == 1
        end
        return has08
    end
end)()

M.isWindows = (function()
    local cache
    return function()
        if cache == nil then
            cache = uv.os_uname().sysname == 'Windows_NT'
        end
        return cache
    end
end)()

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

function M.textoff(winid)
    vim.validate({winid = {winid, 'number'}})
    return M.getWinInfo(winid).textoff
end

function M.isCmdLineWin(bufnr)
    local function isCmdWin()
        return fn.bufname() == '[Command Line]'
    end

    return bufnr and api.nvim_buf_call(bufnr, isCmdWin) or isCmdWin()
end

function M.vcol(winid, pos)
    local vcol = fn.virtcol(pos)
    if not vim.wo[winid].wrap then
        vcol = vcol - M.winCall(winid, fn.winsaveview).leftcol
    end
    return vcol
end

function M.matchaddpos(hlgroup, plist, prior, winid)
    vim.validate({
        hlgroup = {hlgroup, 'string'},
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
            table.insert(ids, fn.matchaddpos(hlgroup, l, prior, -1, {window = winid}))
            l = {}
        end
    end
    if #l > 0 then
        table.insert(ids, fn.matchaddpos(hlgroup, l, prior, -1, {window = winid}))
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
---@return
function M.searchPosSafely(pattern, flags, stopline, timeout, skip)
    local ok, res = pcall(fn.searchpos, pattern, flags, stopline, timeout, skip)
    return ok and res or {0, 0}
end

return M
