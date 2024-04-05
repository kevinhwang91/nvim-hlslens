local M = {}

local api = vim.api
local limit

local wffi = require('hlslens.wffi')

function M.valid()
    return true
end

local function doBuild(bufnr, pat)
    local startPosList, endPosList = {}, {}
    local cnt = 0
    local regm = wffi.buildRegmatchT(pat)
    if regm then
        for lnum = 1, api.nvim_buf_line_count(bufnr) do
            local col = 0
            while wffi.vimRegExecMulti(regm, lnum, col) > 0 do
                cnt = cnt + 1
                if cnt > limit then
                    startPosList, endPosList = {}, {}
                    goto finish
                end
                local startPos, endPos = wffi.regmatchPos(regm)
                table.insert(startPosList, {startPos.lnum + lnum, startPos.col + 1})
                table.insert(endPosList, {endPos.lnum + lnum, endPos.col})

                if endPos.lnum > 0 then
                    break
                end
                col = endPos.col + (col == endPos.col and 1 or 0)
                if col > wffi.mlGetBufLen(lnum) then
                    break
                end
            end
        end
        ::finish::
    end
    return startPosList, endPosList
end

function M.buildList(bufnr, pat)
    return doBuild(bufnr, pat)
end

function M.initialize(l)
    limit = l
    jit.off(doBuild, true)
end

return M
