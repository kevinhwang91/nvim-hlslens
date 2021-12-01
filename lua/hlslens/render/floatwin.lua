local M = {}
local api = vim.api

local winid

function M.close()
    local ok = true
    if winid and api.nvim_win_is_valid(winid) then
        -- suppress error in cmdwin
        ok = pcall(api.nvim_win_close, winid, true)
    end
    if ok then
        winid = nil
    end
end

function M.update(row, col, width)
    local conf = {
        relative = 'win',
        width = width,
        height = 1,
        row = row,
        col = col,
        focusable = false,
        style = 'minimal'
    }
    local bufnr
    if winid and api.nvim_win_is_valid(winid) then
        bufnr = api.nvim_win_get_buf(winid)
        api.nvim_win_set_config(winid, conf)
    else
        bufnr = api.nvim_create_buf(false, true)
        vim.bo[bufnr].bufhidden = 'wipe'
        conf.noautocmd = true
        winid = api.nvim_open_win(bufnr, false, conf)
    end
    return winid, bufnr
end

return M
