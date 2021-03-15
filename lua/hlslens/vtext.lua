local M = {}
local api = vim.api
local config = require('hlslens').get_config()

-- add virtual text for lnum line
-- @param lnum current line num, 1-indexed
-- @param loc location, enum value: 'a': above, 'b': below, 'c': current
-- @param idx index of position list
-- @param r_idx relative index, negative means above current position, positive means below
-- @param count count of position list
-- @param hls_ns hlsearch namespace
function M.add_line_lens(lnum, loc, idx, r_idx, count, hls_ns)
    if type(config.override_line_lens) == 'function' then
        config.override_line_lens(lnum, loc, idx, r_idx, count, hls_ns)
        return
    end
    local sfw = vim.v.searchforward == 1
    local indicator, text, chunks
    local a_r_idx = math.abs(r_idx)
    if a_r_idx > 1 then
        indicator = string.format('%d%s', a_r_idx, sfw ~= (r_idx > 1) and 'N' or 'n')
    elseif a_r_idx == 1 then
        indicator = sfw ~= (r_idx == 1) and 'N' or 'n'
    else
        indicator = ''
    end

    if loc ~= 'c' then
        text = string.format('[%s %d]', indicator, idx)
        chunks = {{' ', 'Ignore'}, {text, 'HlSearchLens'}}
    else
        if indicator ~= '' then
            text = string.format('[%s %d/%d]', indicator, idx, count)
        else
            text = string.format('[%d/%d]', idx, count)
        end
        chunks = {{' ', 'Ignore'}, {text, 'HlSearchLensCur'}}
        api.nvim_buf_clear_namespace(0, hls_ns, lnum - 1, lnum)
    end
    -- TODO For now, nvim_buf_set_virtual_text without priority, if you want to override lens,
    -- please get the namespace of other plugins, delete and set them again.
    -- api.nvim_buf_set_virtual_text(0, hls_ns, lnum - 1, chunks, {})
    api.nvim_buf_set_extmark(0, hls_ns, lnum - 1, 0, {virt_text = chunks})
    -- TODO api.nvim_buf_set_extmark will coredump in somecases, more fragile than
    -- nvim_buf_set_virtual_text, but I am not interested at how to reproduce and report issue
end

function M.create_namespace()
    return api.nvim_create_namespace('hlsearch_lens')
end

function M.clear_buf(bufnr, ns)
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

return M
