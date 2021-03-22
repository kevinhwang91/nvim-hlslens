local M = {}

local cmd = vim.cmd
local fn = vim.fn

local function find_hls_qfnr()
    for i = 1, fn.getqflist({nr = '$'}).nr do
        local context = fn.getqflist({nr = i, context = 0}).context
        if type(context) == 'table' and context.hlslens then
            return i
        end
    end
    return 0
end

function M.build_index(pattern)
    if pattern == '' then
        return
    end

    local tf
    if fn.expand('%') == '' then
        tf = fn.tempname()
        cmd('f ' .. tf)
    end

    if vim.o.smartcase then
        local pattern_chars = pattern:gsub('\\.', '')
        if pattern_chars:lower(pattern) ~= pattern_chars then
            pattern = '\\C' .. pattern
        end
    end

    local qf_list_nr = fn.getqflist({nr = 0}).nr
    local hls_list_nr = find_hls_qfnr()
    local offset_nr = qf_list_nr - hls_list_nr
    local err_prefix = 'sil noa'
    local grep_cmd
    if hls_list_nr == 0 then
        grep_cmd = 'vimgrep'
    else
        if offset_nr > 0 then
            cmd(string.format('%s col %d', err_prefix, offset_nr))
        elseif offset_nr < 0 then
            cmd(string.format('%s cnew %d', err_prefix, -offset_nr))
        end
        cmd([[noautocmd call setqflist([], 'r')]])
        grep_cmd = 'vimgrepadd'
    end

    local ok, msg = pcall(cmd, string.format('%s %s /%s/gj %%', err_prefix, grep_cmd, pattern))
    if not ok then
        if msg:match('^Vim%(%a+%):E682') then
            ok = pcall(cmd, string.format('%s %s /\\V%s/gj %%', err_prefix, grep_cmd, pattern))
        end
    end

    local pos_list = ok and vim.tbl_map(function(item)
        return {item.lnum, item.col}
    end, fn.getqflist()) or {}

    fn.setqflist({}, 'r', {context = {hlslens = true}, title = 'hlslens pattern = ' .. pattern})

    if qf_list_nr ~= 0 then
        local qf_info = fn.getqflist({nr = 0, winid = 0})
        local now_nr = qf_info.nr
        if qf_info.winid ~= 0 then
            err_prefix = 'sil'
        end
        offset_nr = now_nr - qf_list_nr
        if offset_nr > 0 then
            cmd(string.format('%s col %d', err_prefix, offset_nr))
        elseif offset_nr < 0 then
            cmd(string.format('%s cnew %d', err_prefix, -offset_nr))
        elseif offset_nr == 0 and now_nr == 10 then
            cmd(string.format('%s col', err_prefix))
        end
    end

    if tf and tf ~= '' then
        cmd('0f')
        cmd('bw! ' .. tf)
    end

    return pos_list
end

return M
