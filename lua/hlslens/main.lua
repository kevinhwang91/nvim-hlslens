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
local calm_down

local function setup()
    calm_down = config.calm_down
    status = 'stop'
end

local function reset()
    M.disable()
    M.enable()
end

local function autocmd(initial)
    if initial then
        api.nvim_exec([[
            aug HlSearchLens
                au!
                au CmdlineEnter [/\?] lua require('hlslens.main').cmdl_search_enter()
                au CmdlineChanged [/\?] lua require('hlslens.main').cmdl_search_changed()
                au CmdlineLeave [/\?] lua require('hlslens.main').cmdl_search_leave()
            aug END
        ]], false)
    else
        api.nvim_exec([[
            aug HlSearchLens
                au!
                au CmdlineEnter [/\?] lua require('hlslens.main').cmdl_search_enter()
                au CmdlineChanged [/\?] lua require('hlslens.main').cmdl_search_changed()
                au CmdlineLeave [/\?] lua require('hlslens.main').cmdl_search_leave()
                au CmdlineLeave : lua require('hlslens.main').observe_noh()
                au CursorMoved * lua require('hlslens.main').refresh()
                au TermLeave,VimResized * lua require('hlslens.main').refresh(true)
                au TermEnter,CmdwinEnter * lua require('hlslens.main').clear_lens()
            aug END
        ]], false)
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
    if vim.v.event.abort then
        vim.schedule(function()
            M.refresh(true)
        end)
    else
        M.start()
    end
end

function M.status()
    return status
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
    -- local s = os.clock()
    if vim.v.hlsearch == 0 then
        reset()
        return
    else
        local bt = vim.bo.bt
        if bt == 'quickfix' or bt == 'prompt' then
            return
        end
    end

    local pattern = fn.getreg('/')
    local bufnr = api.nvim_get_current_buf()
    local plist = index.build(bufnr, pattern)
    if #plist == 0 then
        render.clear(true, bufnr, true)
        return
    end

    local p_info = position.nearest_idx_info(plist, pattern)
    local n_idx, nr_idxs, n_pos, n_pos_e = p_info.idx, p_info.r_idxs, p_info.p_start, p_info.p_end
    local r_start, r_end = unpack(nr_idxs)

    local c_off = cmdls.off(pattern)
    local nr_idx
    if c_off == 'e' then
        nr_idx = r_end
    else
        nr_idx = r_start
    end

    local hit
    if not force then
        hit = index.hit_cache(pattern, n_idx, nr_idx)
        if hit and not calm_down then
            return
        end
    end

    if calm_down then
        if r_start > 0 or r_end < 0 then
            vim.schedule(function()
                cmd('noh')
                reset()
            end)
            return
        elseif hit then
            return
        end
    end

    render.add_win_hl(0, n_pos, n_pos_e)
    render.do_lens(plist, c_off ~= '' and c_off ~= 's' and c_off ~= 'e', n_idx, nr_idx)

    index.update_cache(bufnr, pattern, n_idx, nr_idx)
    -- print(os.clock() - s)
end

function M.start()
    if vim.o.hlsearch then
        if status == 'stop' then
            autocmd()
            status = 'start'
        end
        vim.schedule(function()
            M.refresh(true)
        end)
    end
end

function M.observe_noh()
    if not vim.v.event.abort then
        local cl = vim.trim(fn.getcmdline())
        if #cl > 2 and string.match('nohlsearch', cl) then
            vim.schedule(reset)
        end
    end
end

setup()

return M
