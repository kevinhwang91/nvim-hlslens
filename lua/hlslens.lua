local M = {}

local initialized = false


function M.enable()
    return require('hlslens.main').enable()
end

function M.disable()
    return require('hlslens.main').disable()
end

function M.isEnabled()
    return require('hlslens.main').isEnabled()
end

function M.toggle()
    if M.isEnabled() then
        M.disable()
        vim.notify('Disable nvim-hlslens', vim.log.levels.INFO)
    else
        M.enable()
        vim.notify('Enable nvim-hlslens', vim.log.levels.INFO)
    end
    return M.isEnabled()
end

function M.start()
    return require('hlslens.main').start()
end

function M.stop()
    return require('hlslens.main').stop()
end

function M.setup(opts, warnFlag)
    if not opts and warnFlag then
        vim.schedule(function()
            if not initialized then
                vim.notify([[nvim-hlslens need to invoke `require('hlslens').setup()` to boot!]],
                           vim.log.levels.WARN)
            end
            M.setup()
        end)
        return
    end
    if initialized and (not M._config or not opts) then
        return
    end

    opts = opts or {}
    -- M._config will become nil latter
    M._config = opts
    if opts.auto_enable ~= false then
        M.enable()
    end
    initialized = true
end

return M
