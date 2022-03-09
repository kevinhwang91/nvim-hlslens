local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local cmdls = require('hlslens.cmdls')
local render = require('hlslens.render')
local position = require('hlslens.position')
local config = require('hlslens.config')

local STATE = {START = 0, STOP = 1}
local status
local last_bufnr
local calm_down

local function init()
    calm_down = config.calm_down
    status = STATE.STOP
    last_bufnr = -1
end

local function reset()
    M.disable()
    M.enable()
end

local function autocmd(initial)
    if initial then
        cmd([[
            aug HlSearchLens
                au!
                au CmdlineEnter /,\? lua require('hlslens.main').cmdl_search_enter()
                au CmdlineChanged /,\? lua require('hlslens.main').cmdl_search_changed()
                au CmdlineLeave /,\? lua require('hlslens.main').cmdl_search_leave()
            aug END
        ]])
    else
        cmd([[
            aug HlSearchLens
                au!
                au CmdlineEnter /,\? lua require('hlslens.main').cmdl_search_enter()
                au CmdlineChanged /,\? lua require('hlslens.main').cmdl_search_changed()
                au CmdlineLeave /,\? lua require('hlslens.main').cmdl_search_leave()
                au CmdlineLeave : lua require('hlslens.main').observe_cmdl_leave()
                au CursorMoved * lua require('hlslens.main').refresh()
                au WinEnter,TermLeave,VimResized * lua require('hlslens.main').refresh(true)
                au TermEnter * lua require('hlslens.main').clear_cur_lens()
            aug END
        ]])
    end
end

local function may_initialize()
    if status == STATE.STOP then
        autocmd()
        status = STATE.START
    end
end

function M.cmdl_search_enter()
    cmdls.search_attach()
end

function M.cmdl_search_changed()
    cmdls.search_changed()
end

function M.cmdl_search_leave()
    cmdls.search_detach()
    if vim.o.hlsearch then
        may_initialize()
        vim.schedule(function()
            M.refresh(true)
        end)
    end
end

function M.status()
    return status
end

function M.clear_cur_lens()
    render.clear(true, 0, true)
end

function M.clear_lens()
    render.clear_all()
end

function M.enable()
    if status == STATE.STOP then
        autocmd(true)
        if api.nvim_get_mode().mode == 'c' then
            M.cmdl_search_enter()
        end
        if vim.v.hlsearch == 1 and fn.getreg('/') ~= '' then
            M.start()
        end
    end
end

function M.disable()
    M.clear_lens()
    position.clear()
    cmd('sil! au! HlSearchLens')
    status = STATE.STOP
end

function M.refresh(force)
    if vim.v.hlsearch == 0 then
        vim.schedule(function()
            if vim.v.hlsearch == 0 then
                reset()
            else
                M.refresh(force)
            end
        end)
        return
    end

    local bufnr = api.nvim_get_current_buf()
    local pattern = fn.getreg('/')
    if pattern == '' then
        reset()
        return
    end

    local plist = position.build(bufnr, pattern)
    local splist = plist.start_pos

    local t_bufnr = last_bufnr
    last_bufnr = bufnr

    if #splist == 0 then
        render.clear(true, bufnr, true)
        return
    end

    local c_off
    local hist_search = fn.histget('/')
    if hist_search ~= pattern then
        local delim = vim.v.searchforward == 1 and '/' or '?'
        local sects = vim.split(hist_search, delim)
        if #sects > 1 then
            local p = sects[#sects - 1]
            if p == '' or p == pattern then
                c_off = sects[#sects]
            end
        end
    end

    local pinfo = position.nearest_idx_info(plist, c_off)

    local s_pos = pinfo.s_pos
    local e_pos = pinfo.e_pos
    local c_pos = pinfo.c_pos
    local o_pos = pinfo.o_pos

    local idx = pinfo.idx
    local r_idx = pinfo.r_idx

    local hit
    if not force and t_bufnr == bufnr then
        hit = position.hit_cache(bufnr, pattern, idx, r_idx)
        if hit and not calm_down then
            return
        end
    end
    position.update_cache(bufnr, pattern, idx, r_idx)

    if calm_down then
        if not position.in_range(s_pos, e_pos, c_pos) then
            vim.schedule(function()
                cmd('noh')
                reset()
            end)
            return
        elseif hit then
            return
        end
    end

    render.add_win_hl(0, s_pos, e_pos)
    render.do_lens(splist, #o_pos == 0, idx, r_idx)
end

function M.start(force)
    if vim.o.hlsearch then
        may_initialize()
        M.refresh(force)
    end
end

function M.observe_cmdl_leave()
    if not vim.v.event.abort then
        local cmdl = vim.trim(fn.getcmdline())
        if #cmdl > 2 then
            for _, cl in ipairs(vim.split(cmdl, '|')) do
                if ('nohlsearch'):match(vim.trim(cl)) then
                    vim.schedule(reset)
                    return
                end
            end
        end

        vim.schedule(function()
            local pattern = fn.getreg('/')
            if pattern == '' then
                reset()
            end
        end)
    end
end

init()

return M
