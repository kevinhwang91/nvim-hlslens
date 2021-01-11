local M = {}
local initialized = false
local api = vim.api
local config = {
    auto_enable = true,
    calm_down = false,
    override_line_lens = nil
}

function M.setup(opts)
    if initialized then
        return
    end
    config = vim.tbl_deep_extend('force', config, opts or {})
    if config.auto_enable then
        api.nvim_exec([[
        augroup HlSearchLens
            autocmd!
            autocmd CmdlineEnter [/\?] ++once lua require('hlslens').enable()
        augroup END
        ]], false)
    end
    initialized = true
end

function M.get_config()
    if not initialized then
        M.setup()
    end
    return config
end

function M.enable()
    require('hlslens.main').enable()
end

function M.disable()
    require('hlslens.main').disable()
end

function M.start()
    require('hlslens.main').start()
end

return M
