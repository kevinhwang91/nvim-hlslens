local M = {}
local api = vim.api

local bufs
local ns

local function init()
    bufs = {}
    ns = api.nvim_create_namespace('hlslens')
end

function M.set_virt_eol(bufnr, lnum, chunks, priority, id)
    bufnr = bufnr == 0 and api.nvim_get_current_buf() or bufnr
    bufs[bufnr] = true
    -- id may be nil
    return api.nvim_buf_set_extmark(bufnr, ns, lnum, -1, {
        id = id,
        virt_text = chunks,
        hl_mode = 'combine',
        priority = priority
    })
end

function M.clear_buf(bufnr)
    if not bufnr then
        return
    end
    bufnr = bufnr == 0 and api.nvim_get_current_buf() or bufnr
    if bufs[bufnr] then
        if api.nvim_buf_is_valid(bufnr) then
            api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
            -- seemly a bug for nvim_create_namespace, can't clear extmarks totally
            for _, extm in pairs(api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})) do
                api.nvim_buf_del_extmark(bufnr, ns, extm[1])
            end
        end
        bufs[bufnr] = nil
    end
end

function M.clear_all_buf()
    for bufnr in pairs(bufs) do
        M.clear_buf(bufnr)
    end
    bufs = {}
end

init()

return M
