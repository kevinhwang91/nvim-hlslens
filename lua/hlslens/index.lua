local M = {}

local cmd = vim.cmd
local api = vim.api
local fn = vim.fn

local bufs
local hls_qf_id

local function setup()
    bufs = {cnt = 0}
    hls_qf_id = 0
end

local function get_qfnr_by_id(id)
    return id == 0 and 0 or fn.getqflist({id = id, nr = 0}).nr
end

local function valid_pat(pat)
    if pat == '' then
        return false
    end
    for g in pat:gmatch('.?/') do
        if g ~= [[\/]] then
            return false
        end
    end
    return true
end

local function build_cache(bufnr, plist, pattern)
    local c = bufs[bufnr] or {}
    c = {plist = plist or {}, changedtick = api.nvim_buf_get_changedtick(bufnr), pattern = pattern}
    if not bufs[bufnr] then
        bufs.cnt = bufs.cnt + 1
    end
    bufs[bufnr] = c
    return c
end

function M.hit_cache(bufnr, pattern, n_idx, nr_idx)
    local c = bufs[bufnr]
    return c and pattern == c.pattern and n_idx == c.n_idx and nr_idx == c.nr_idx and
               vim.v.searchforward == c.sfw
end

function M.update_cache(bufnr, pattern, n_idx, nr_idx)
    local c = bufs[bufnr]
    c.pattern, c.n_idx, c.nr_idx, c.sfw = pattern, n_idx, nr_idx, vim.v.searchforward
end

function M.build(bufnr, pattern)
    bufnr = bufnr or api.nvim_get_current_buf()

    -- fast and simple way to prevent memory leaking :)
    if bufs.cnt > 5 then
        bufs = {cnt = 0}
    end

    local c = bufs[bufnr] or {}

    if c.changedtick == api.nvim_buf_get_changedtick(bufnr) and c.pattern == pattern then
        return c.plist
    else
        -- vim.bo.bt is not cheap
        local bt = vim.bo.bt
        if not valid_pat(pattern) or bt == 'quickfix' then
            return build_cache(bufnr, {}, pattern).plist
        end
    end

    local tf
    if api.nvim_buf_get_name(0) == '' then
        tf = fn.tempname()
        cmd('f ' .. tf)
    end

    if vim.o.smartcase then
        local pattern_chars = pattern:gsub('\\.', '')
        if pattern_chars:lower(pattern) ~= pattern_chars then
            pattern = '\\C' .. pattern
        end
    end

    local origin_qf_id = fn.getqflist({id = 0}).id
    local hls_qf_nr = get_qfnr_by_id(hls_qf_id)

    local grep_cmd
    if hls_qf_nr == 0 then
        grep_cmd = 'vimgrep'
    else
        cmd(('sil noa %dchi'):format(hls_qf_nr))
        cmd([[noa call setqflist([], 'r')]])
        grep_cmd = 'vimgrepadd'
    end

    local ok, msg = pcall(cmd, ('sil noa %s /%s/gj %%'):format(grep_cmd, pattern))
    if not ok then
        if msg:match('^Vim%(%a+%):E682') then
            ok = pcall(cmd, ('sil noa %s /\\V%s/gj %%'):format(grep_cmd, pattern))
        end
    end

    local plist = {}
    local hls_qf = fn.getqflist({id = 0, size = 0})
    hls_qf_id = hls_qf.id

    -- don't waste the memory :)
    if hls_qf.size <= 100000 then
        plist = ok and vim.tbl_map(function(item)
            return {item.lnum, item.col}
        end, fn.getqflist()) or {}
    end

    fn.setqflist({}, 'r', {title = 'hlslens pattern = ' .. pattern})

    local cur_nr = get_qfnr_by_id(origin_qf_id)
    if cur_nr ~= 0 and hls_qf_nr ~= cur_nr then
        local winid = fn.getqflist({winid = 0}).winid
        cmd(('sil %s %dchi'):format(winid == 0 and 'noa' or '', cur_nr))
    end

    if tf and tf ~= '' then
        cmd('sil 0f')
        cmd('noa bw! ' .. tf)
    end

    return build_cache(bufnr, plist, pattern).plist
end

function M.clear()
    bufs = {cnt = 0}
end

setup()

return M
