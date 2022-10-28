local M = {}

local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local utils = require('hlslens.utils')

local tname
local hlsQfId
local limit

function M.valid(pat)
    if pat == '' or vim.bo.bt == 'quickfix' or utils.isCmdLineWin() then
        return false
    end
    for g in pat:gmatch('.?/') do
        if g ~= [[\/]] then
            return false
        end
    end
    return true
end

local function getQfnrById(id)
    return id == 0 and 0 or fn.getqflist({id = id, nr = 0}).nr
end

local function keepMagicOpt(pattern)
    if not vim.o.magic then
        local foundAtom = false
        local i = 1
        while i < #pattern do
            if pattern:sub(i, i) == [[\]] then
                local atom = pattern:sub(i + 1, i + 1):upper()
                if atom == 'M' or atom == 'V' then
                    foundAtom = true
                    break
                else
                    i = i + 2
                end
            else
                break
            end
        end
        if not foundAtom then
            pattern = [[\M]] .. pattern
        end
    end
    return pattern
end

function M.buildList(pat)
    local tf
    if api.nvim_buf_get_name(0) == '' then
        tf = tname
        cmd('f ' .. tf)
    end

    local rawPat = pat
    -- vimgrep can't respect magic option
    pat = keepMagicOpt(pat)
    if vim.o.smartcase then
        local patternChars = pat:gsub('\\.', '')
        if patternChars:lower() ~= patternChars then
            pat = '\\C' .. pat
        end
    end

    local originInfo = fn.getqflist({id = 0, winid = 0})
    local originQfId, qwinid = originInfo.id, originInfo.winid
    local qfWinView
    if qwinid ~= 0 then
        qfWinView = utils.winCall(qwinid, fn.winsaveview)
    end

    local hlsQfNr = getQfnrById(hlsQfId)

    local grepCmd
    if hlsQfNr == 0 then
        grepCmd = 'vimgrep'
    else
        cmd(('sil noa %dchi'):format(hlsQfNr))
        cmd([[noa call setqflist([], 'r')]])
        grepCmd = 'vimgrepadd'
    end

    local ok, msg = pcall(cmd, ('sil noa %d%s /%s/gj %%'):format(limit + 1, grepCmd, pat))
    if not ok then
        ---@diagnostic disable-next-line: need-check-nil
        if msg:match(':E682:') then
            ok = pcall(cmd, ('sil noa %d%s /\\V%s/gj %%'):format(limit + 1, grepCmd, pat))
        end
    end

    local startPosList, endPosList = {}, {}
    local hlsQf = fn.getqflist({id = 0, size = 0})
    hlsQfId = hlsQf.id
    if ok then
        if hlsQf.size <= limit then
            for _, item in ipairs(fn.getqflist()) do
                table.insert(startPosList, {item.lnum, item.col})
                table.insert(endPosList, {item.end_lnum, item.end_col - 1})
            end
        end
    end
    fn.setqflist({}, 'r', {title = 'hlslens pattern = ' .. rawPat})

    local originNr = getQfnrById(originQfId)
    if originNr ~= 0 and hlsQfNr ~= originNr then
        local winid = fn.getqflist({winid = 0}).winid
        local au = (winid == 0 or hlsQfNr ~= 0) and 'noa' or ''
        cmd(('sil %s %dchi'):format(au, originNr))

        if qfWinView then
            utils.winCall(qwinid, function()
                fn.winrestview(qfWinView)
            end)
        end
    end

    if tf then
        cmd('sil 0f')
        cmd('noa bw! ' .. tf)
    end

    return startPosList, endPosList
end

function M.initialize(l)
    hlsQfId = 0
    tname = fn.tempname()
    limit = l
end

return M
