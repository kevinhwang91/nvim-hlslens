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
    if pattern == '' or fn.expand('%') == '' then
        return
    end

    if vim.o.smartcase and string.lower(pattern) ~= pattern then
        pattern = '\\C' .. pattern
    end

    local qf_list_nr = fn.getqflist({nr = 0}).nr
    local hls_list_nr = find_hls_qfnr()
    local offset_nr = qf_list_nr - hls_list_nr
    if hls_list_nr == 0 then
        grep_cmd = 'vimgrep'
    else
        if offset_nr > 0 then
            cmd(string.format('silent noautocmd colder %d', offset_nr))
        elseif offset_nr < 0 then
            cmd(string.format('silent noautocmd cnewer %d', -offset_nr))
        end
        cmd([[noautocmd call setqflist([], 'r')]])
        grep_cmd = 'vimgrepadd'
    end

    local ok, msg = pcall(cmd, string.format('silent noautocmd %s /%s/gj %%', grep_cmd, pattern))
    if not ok then
        if msg:match('^Vim%(%a+%):E682') then
            ok, msg = pcall(cmd,
                string.format('silent noautocmd %s /\\V%s/gj %%', grep_cmd, pattern))
        end
    end

    local pos_list = msg and {} or vim.tbl_map(function(item)
        return {item.lnum, item.col}
    end, fn.getqflist())

    local title = 'hlslens pattern=' .. pattern
    fn.setqflist({}, 'r', {context = {hlslens = 1}, title = title})

    if hls_list_nr > 0 then
        if offset_nr > 0 then
            cmd(string.format('silent noautocmd cnewer %d', offset_nr))
        elseif offset_nr < 0 then
            cmd(string.format('silent noautocmd colder %d', -offset_nr))
        end
    end

    return pos_list
end

return M
