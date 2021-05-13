local M = {}
local api = vim.api

local winid

function M.close()
    if winid and api.nvim_win_is_valid(winid) then
        api.nvim_win_close(winid, true)
    end
    winid = nil
end

function M.update(row, col, width)
    local layout = {
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
        api.nvim_win_set_config(winid, layout)
    else
        local ei = vim.o.ei
        vim.o.ei = 'all'
        pcall(function()
            bufnr = api.nvim_create_buf(false, true)
            vim.bo[bufnr].bufhidden = 'wipe'
            winid = api.nvim_open_win(bufnr, false, layout)
        end)
        vim.o.ei = ei
    end
    return winid, bufnr
end

return M
