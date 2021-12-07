local M = {}

local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local utils = require('hlslens.utils')

local tname
local hls_qf_id

function M.valid(pat)
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

local function get_qfnr_by_id(id)
    return id == 0 and 0 or fn.getqflist({id = id, nr = 0}).nr
end

local function keep_magic_opt(pattern)
    if not vim.o.magic then
        local found_atom = false
        local i = 1
        while i < #pattern do
            if pattern:sub(i, i) == [[\]] then
                local atom = pattern:sub(i + 1, i + 1):upper()
                if atom == 'M' or atom == 'V' then
                    found_atom = true
                    break
                else
                    i = i + 2
                end
            else
                break
            end
        end
        if not found_atom then
            pattern = [[\M]] .. pattern
        end
    end
    return pattern
end

function M.build_list(pat, limit)
    local tf
    if api.nvim_buf_get_name(0) == '' then
        tf = tname
        cmd('f ' .. tf)
    end

    local raw_pat = pat
    -- vimgrep can't respect magic option
    pat = keep_magic_opt(pat)
    if vim.o.smartcase then
        local pattern_chars = pat:gsub('\\.', '')
        if pattern_chars:lower(pat) ~= pattern_chars then
            pat = '\\C' .. pat
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
    if hls_qf_nr == 0 then
        grep_cmd = 'vimgrep'
    else
        cmd(('sil noa %dchi'):format(hls_qf_nr))
        cmd([[noa call setqflist([], 'r')]])
        grep_cmd = 'vimgrepadd'
    end

    local ok, msg = pcall(cmd, ('sil noa %d%s /%s/gj %%'):format(limit + 1, grep_cmd, pat))
    if not ok then
        if msg:match(':E682:') then
            ok = pcall(cmd, ('sil noa %d%s /\\V%s/gj %%'):format(limit + 1, grep_cmd, pat))
        end
    end

    local start_pos_list, end_pos_list = {}, {}
    local hls_qf = fn.getqflist({id = 0, size = 0})
    hls_qf_id = hls_qf.id
    if ok then
        if hls_qf.size <= limit then
            for _, item in ipairs(fn.getqflist()) do
                table.insert(start_pos_list, {item.lnum, item.col})
                table.insert(end_pos_list, {item.end_lnum, item.end_col - 1})
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

    return start_pos_list, end_pos_list
end

local function init()
    hls_qf_id = 0
    tname = fn.tempname()
end

init()

return M
