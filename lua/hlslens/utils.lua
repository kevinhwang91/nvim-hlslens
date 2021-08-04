local M = {}
local fn = vim.fn
local api = vim.api
local cmd = vim.cmd
local uv = vim.loop

M.is_dev = (function()
    local is_dev
    return function()
        if is_dev == nil then
            is_dev = fn.has('nvim-0.6') == 1
        end
        return is_dev
    end
end)()

function M.bin_search(items, e, comp)
    vim.validate({items = {items, 'table'}, comp = {comp, 'function'}})
    local min, max, mid = 1, #items, 1
    local r = 0
    while min <= max do
        mid = math.floor((min + max) / 2)
        r = comp(items[mid], e)
        if r == 0 then
            break
        elseif r == 1 then
            max = mid - 1
        else
            min = mid + 1
        end
    end
    return mid, r
end

function M.compare_pos(p1, p2)
    if p1[1] == p2[1] then
        if p1[2] == p2[2] then
            return 0
        elseif p1[2] > p2[2] then
            return 1
        else
            return -1
        end
    elseif p1[1] > p2[1] then
        return 1
    else
        return -1
    end
end

function M.gutter_size(winid)
    vim.validate({winid = {winid, 'number'}})
    local size
    M.win_execute(winid, function()
        local wv = fn.winsaveview()
        api.nvim_win_set_cursor(winid, {wv.lnum, 0})
        size = fn.wincol() - 1
        fn.winrestview(wv)
    end)
    return size
end

function M.vcol(winid, pos)
    local vcol = fn.virtcol(pos)
    if not vim.wo[winid].wrap then
        M.win_execute(winid, function()
            vcol = vcol - fn.winsaveview().leftcol
        end)
    end
    return vcol
end

function M.hl_attrs(hlgroup)
    vim.validate({hlgroup = {hlgroup, 'string'}})
    local attr_dict = {
        'bold', 'standout', 'underline', 'undercurl', 'italic', 'reverse', 'strikethrough'
    }
    local t = {}
    local hl2tbl = function(gui)
        local ok, hl = pcall(api.nvim_get_hl_by_name, hlgroup, gui)
        if not ok then
            return
        end
        local fg, bg, color_fmt = hl.foreground, hl.background, gui and '#%x' or '%s'
        if fg then
            t[gui and 'guifg' or 'ctermfg'] = color_fmt:format(fg)
        end
        if bg then
            t[gui and 'guibg' or 'ctermbg'] = color_fmt:format(bg)
        end
        hl.foreground, hl.background = nil, nil
        local attrs = {}
        for attr in pairs(hl) do
            if vim.tbl_contains(attr_dict, attr) then
                table.insert(attrs, attr)
            end
        end
        t[gui and 'gui' or 'cterm'] = #attrs > 0 and attrs or nil
    end
    hl2tbl(true)
    hl2tbl(false)
    return t
end

function M.matchaddpos(hlgroup, plist, prior, winid)
    vim.validate({
        hlgroup = {hlgroup, 'string'},
        plist = {plist, 'table'},
        prior = {prior, 'number', true},
        winid = {winid, 'number'}
    })
    prior = prior or 10

    local ids = {}
    local l = {}
    for i, p in ipairs(plist) do
        table.insert(l, p)
        if i % 8 == 0 then
            table.insert(ids, fn.matchaddpos(hlgroup, l, prior, -1, {window = winid}))
            l = {}
        end
    end
    if #l > 0 then
        table.insert(ids, fn.matchaddpos(hlgroup, l, prior, -1, {window = winid}))
    end
    return ids
end

function M.killable_defer(timer, func, delay)
    vim.validate({
        timer = {timer, 'userdata', true},
        func = {func, 'function'},
        delay = {delay, 'number'}
    })
    if timer and timer:has_ref() then
        timer:stop()
        if not timer:is_closing() then
            timer:close()
        end
    end
    timer = uv.new_timer()
    timer:start(delay, 0, function()
        vim.schedule(function()
            if not timer:has_ref() then
                return
            end
            timer:stop()
            if not timer:is_closing() then
                timer:close()
            end
            func()
        end)
    end)
    return timer
end

function M.win_execute(winid, func)
    vim.validate({
        winid = {
            winid, function(w)
                return w and api.nvim_win_is_valid(w)
            end, 'a valid window'
        },
        func = {func, 'function'}
    })

    local cur_winid = api.nvim_get_current_win()
    local noa_set_win = 'noa call nvim_set_current_win(%d)'
    if cur_winid ~= winid then
        cmd(noa_set_win:format(winid))
    end
    local ret = func()
    if cur_winid ~= winid then
        cmd(noa_set_win:format(cur_winid))
    end
    return ret
end

function M.keep_magic_opt(pattern)
    if not vim.o.magic then
        local found_atom = false
        local i = 1
        while i < #pattern do
            if pattern:sub(i, i) == [[\]] then
                local atom = pattern:sub(i + 1, i + 1):upper()
                if atom == 'M' or atom == 'V' then
                    found_atom = true
                    break
                else
                    i = i + 2
                end
            else
                break
            end
        end
        if not found_atom then
            pattern = [[\M]] .. pattern
        end
    end
    return pattern
end

return M
