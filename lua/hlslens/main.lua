local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local cmdls = require('hlslens.cmdls')
local render = require('hlslens.render')
local index = require('hlslens.index')
local position = require('hlslens.position')
local config = require('hlslens.config')

local status
local last_bufnr
local calm_down

local function init()
    calm_down = config.calm_down
    status = 'stop'
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
                au CmdlineEnter [/\?] lua require('hlslens.main').cmdl_search_enter()
                au CmdlineChanged [/\?] lua require('hlslens.main').cmdl_search_changed()
                au CmdlineLeave [/\?] lua require('hlslens.main').cmdl_search_leave()
            aug END
        ]])
    else
        cmd([[
            aug HlSearchLens
                au!
                au CmdlineEnter [/\?] lua require('hlslens.main').cmdl_search_enter()
                au CmdlineChanged [/\?] lua require('hlslens.main').cmdl_search_changed()
                au CmdlineLeave [/\?] lua require('hlslens.main').cmdl_search_leave()
                au CmdlineLeave : lua require('hlslens.main').observe_noh()
                au CursorMoved * lua require('hlslens.main').refresh()
                au WinEnter,TermLeave,VimResized * lua require('hlslens.main').refresh(true)
                au TermEnter * lua require('hlslens.main').clear_cur_lens()
            aug END
        ]])
    end
end

local function may_initialize()
    if status == 'stop' then
        autocmd()
        status = 'start'
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
    if status == 'stop' then
        autocmd(true)
        if api.nvim_get_mode().mode == 'c' then
            M.cmdl_search_enter()
        end
        if vim.v.hlsearch == 1 then
            M.start()
        end
    end
end

function M.disable()
    M.clear_lens()
    index.clear()
    cmd('sil! au! HlSearchLens')
    status = 'stop'
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

    local pattern = fn.getreg('/')
    local bufnr = api.nvim_get_current_buf()

    local plist, plist_end

    -- command line window
    if fn.bufname() == '[Command Line]' then
        plist = {}
    else
        plist, plist_end = index.build(bufnr, pattern)
    end
    if #plist == 0 then
        render.clear(true, bufnr, true)
        return
    end

    local pinfo = position.nearest_idx_info(pattern, plist, plist_end)

    local c_off = cmdls.off(pattern)

    local nr_idx = c_off == 'e' and pinfo.r_idx_e or pinfo.r_idx_s
    local n_idx = pinfo.idx

    local hit
    local t_bufnr = last_bufnr
    last_bufnr = bufnr
    if not force and t_bufnr == bufnr then
        hit = index.hit_cache(bufnr, pattern, n_idx, nr_idx)
        if hit and not calm_down then
            return
        end
    end
    index.update_cache(bufnr, pattern, n_idx, nr_idx)

    -- index may be changed after updating cache, assign info again
    local pos_e = pinfo.pos_e
    local r_idx_e = pinfo.r_idx_e
    local pos_s = pinfo.pos_s
    local r_idx_s = pinfo.r_idx_s
    n_idx, nr_idx = pinfo.idx, c_off == 'e' and r_idx_e or r_idx_s

    if calm_down then
        if r_idx_s > 0 or r_idx_e < 0 then
            vim.schedule(function()
                cmd('noh')
                reset()
            end)
            return
        elseif hit then
            return
        end
    end

    render.add_win_hl(0, pos_s, pos_e)
    render.do_lens(plist, c_off ~= '' and c_off ~= 's' and c_off ~= 'e', n_idx, nr_idx)
end

function M.start()
    if vim.o.hlsearch then
        may_initialize()
        M.refresh()
    end
end

function M.observe_noh()
    if not vim.v.event.abort then
        local cl = vim.trim(fn.getcmdline())
        if #cl > 2 and ('nohlsearch'):match(cl) then
            vim.schedule(reset)
        end
    end
end

init()

return M
