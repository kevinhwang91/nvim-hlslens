local M = {}

local api = vim.api
local wffi = require('hlslens.wffi')

local bufs

local function build_cache(bufnr, pattern, plist)
    local c = {
        plist = plist or {},
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

function M.build(bufnr, pat)
    local c = bufs[bufnr] or {}
    if c.changedtick == api.nvim_buf_get_changedtick(bufnr) and c.pattern == pat then
        return c.plist, c.plist_end
    end

    local regm = wffi.build_regmatch_T(pat)

    local start_pos_list, end_pos_list = {}, {}
    local limit = 100000
    local cnt = 0
    for lnum = 1, api.nvim_buf_line_count(0) do
        local col = 0
        while wffi.vim_regexec_multi(regm, lnum, col) > 0 do
            cnt = cnt + 1
            if cnt > limit then
                goto continue
            end
            local start_pos, end_pos = wffi.regmatch_pos(regm)
            table.insert(start_pos_list, {start_pos.lnum + lnum, start_pos.col + 1})
            table.insert(end_pos_list, {end_pos.lnum + lnum, end_pos.col})

            if end_pos.lnum > 0 then
                break
            end
            col = end_pos.col + (col == end_pos.col and 1 or 0)
            if col > wffi.ml_get_buf_len(lnum) then
                break
            end
        end
    end
    ::continue::

    if cnt > limit then
        start_pos_list, end_pos_list = {}, {}
    end
    local plist = {start_pos = start_pos_list, end_pos = end_pos_list}
    local cache = build_cache(bufnr or api.nvim_get_current_buf(), pat, plist)
    return cache.plist
end

function M.clear()
    bufs = {cnt = 0}
end

local function init()
    bufs = {cnt = 0}
end

init()

return M
