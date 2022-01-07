local config = {}

local function init()
    local hlslens = require('hlslens')
    config = vim.tbl_deep_extend('keep', hlslens._config or {}, {
        auto_enable = true,
        enable_incsearch = true,
        calm_down = false,
        nearest_only = false,
        nearest_float_when = 'auto',
        float_shadow_blend = 50,
        virt_priority = 100,
        build_position_cb = nil,
        override_lens = nil
    })
    hlslens._config = nil
end

init()

return config
