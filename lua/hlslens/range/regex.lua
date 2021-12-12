local M = {}

local api = vim.api

local wffi = require('hlslens.wffi')

local function do_build(pat, limit)
    local start_pos_list, end_pos_list = {}, {}
    local cnt = 0
    local regm = wffi.build_regmatch_T(pat)
    if regm then
        for lnum = 1, api.nvim_buf_line_count(0) do
            local col = 0
            while wffi.vim_regexec_multi(regm, lnum, col) > 0 do
                cnt = cnt + 1
                if cnt > limit then
                    start_pos_list, end_pos_list = {}, {}
                    goto finish
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
        ::finish::
    end
    return start_pos_list, end_pos_list
end

function M.build_list(pat, limit)
    return do_build(pat, limit)
end

local function init()
    jit.off(do_build, true)
end

init()

return M
