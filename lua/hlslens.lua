local M = {}
local cmd = vim.cmd
local enabled
local initialized = false

function M.setup(opts)
    if initialized then
        return
    end

    opts = opts or {}

    local auto_enable = opts.auto_enable == false and false or true
    if auto_enable then
        enabled = true
        vim.cmd([[au CmdlineEnter [/\?] ++once lua require('hlslens').enable()]])
    else
        enabled = false
    end
    -- M._config will become nil latter
    M._config = opts
    initialized = true
end

function M.enable()
    enabled = true
    require('hlslens.main').enable()
end

function M.disable()
    enabled = false
    require('hlslens.main').disable()
end

function M.toggle()
    if enabled then
        M.disable()
        cmd([[echohl WarningMsg | echo 'Disable nvim-hlslens' | echohl None]])
    else
        M.enable()
        cmd([[echohl WarningMsg | echo 'Enable nvim-hlslens' | echohl None]])
    end
end

function M.start()
    if enabled then
        require('hlslens.main').start()
    end
end

function M.status()
    if enabled then
        return require('hlslens.main').status()
    end
end

return M
