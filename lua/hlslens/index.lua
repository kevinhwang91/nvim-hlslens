local M = {}

local cmd = vim.cmd
local api = vim.api
local fn = vim.fn

local bufs
local tname
local hls_qf_id

local utils = require('hlslens.utils')

local function init()
    bufs = {cnt = 0}
    hls_qf_id = 0
    tname = fn.tempname()
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

local function build_cache(bufnr, pattern, plist, plist_end)
    local c = {
        plist = plist or {},
        plist_end = plist_end,
        changedtick = api.nvim_buf_get_changedtick(bufnr),
        pattern = pattern
    }
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
        return c.plist, c.plist_end
    else
        -- vim.bo.bt is not cheap
        local bt = vim.bo.bt
        if not valid_pat(pattern) or bt == 'quickfix' then
            return build_cache(bufnr, pattern, {}).plist
        end
    end

    local tf
    if api.nvim_buf_get_name(0) == '' then
        tf = tname
        cmd('f ' .. tf)
    end

    local raw_pat = pattern
    -- vimgrep can't respect magic option
    pattern = utils.keep_magic_opt(pattern)
    if vim.o.smartcase then
        local pattern_chars = pattern:gsub('\\.', '')
        if pattern_chars:lower(pattern) ~= pattern_chars then
            pattern = '\\C' .. pattern
        end
    end

    local origin_info = fn.getqflist({id = 0, winid = 0})
    local origin_qf_id, qf_winid = origin_info.id, origin_info.winid
    local qf_wv
    if qf_winid ~= 0 then
        utils.win_execute(qf_winid, function()
            qf_wv = fn.winsaveview()
        end)
    end

    local hls_qf_nr = get_qfnr_by_id(hls_qf_id)

    local grep_cmd
    local limit = 10000
    if hls_qf_nr == 0 then
        grep_cmd = 'vimgrep'
    else
        cmd(('sil noa %dchi'):format(hls_qf_nr))
        cmd([[noa call setqflist([], 'r')]])
        grep_cmd = 'vimgrepadd'
    end

    local ok, msg = pcall(cmd, ('sil noa %d%s /%s/gj %%'):format(limit + 1, grep_cmd, pattern))
    if not ok then
        if msg:match(':E682:') then
            ok = pcall(cmd, ('sil noa %d%s /\\V%s/gj %%'):format(limit + 1, grep_cmd, pattern))
        end
    end

    local is_dev = utils.is_dev()
    local plist = {}
    local plist_end = utils.is_dev() and {}
    local hls_qf = fn.getqflist({id = 0, size = 0})
    hls_qf_id = hls_qf.id
    if ok then
        -- greater than limit will return empty table
        if hls_qf.size <= limit then
            for _, item in ipairs(fn.getqflist()) do
                table.insert(plist, {item.lnum, item.col})
                if is_dev then
                    table.insert(plist_end, {item.end_lnum, item.end_col - 1})
                end
            end
        end
    end
    fn.setqflist({}, 'r', {title = 'hlslens pattern = ' .. raw_pat})

    local origin_nr = get_qfnr_by_id(origin_qf_id)
    if origin_nr ~= 0 and hls_qf_nr ~= origin_nr then
        local winid = fn.getqflist({winid = 0}).winid
        local au = (winid == 0 or hls_qf_nr ~= 0) and 'noa' or ''
        cmd(('sil %s %dchi'):format(au, origin_nr))

        if qf_wv then
            utils.win_execute(qf_winid, function()
                fn.winrestview(qf_wv)
            end)
        end
    end

    if tf then
        cmd('sil 0f')
        cmd('noa bw! ' .. tf)
    end

    local cache = build_cache(bufnr, raw_pat, plist, plist_end)
    return cache.plist, cache.plist_end
end

function M.clear()
    bufs = {cnt = 0}
end

init()

return M
