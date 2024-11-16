local M = {}

local initialized = false

---Enable hlslens
---@return boolean ret return true if successful, otherwise return false
function M.enable()
    return require('hlslens.main').enable()
end

---Disable hlslens
---@return boolean ret return true if successful, otherwise return false
function M.disable()
    return require('hlslens.main').disable()
end

---Check out enabled for hlslens
---@return boolean ret return true if enabled, otherwise return false
function M.isEnabled()
    return require('hlslens.main').isEnabled()
end

---Toggle hlslens
---@return boolean ret return true if enabled, otherwise return false
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

---Start to render
---@return boolean ret return true if enabled, otherwise return false
function M.start()
    return require('hlslens.main').start()
end

---Stop to render
---@return boolean ret return true if enabled, otherwise return false
function M.stop()
    return require('hlslens.main').stop()
end

---Export last search results to quickfix
---@param isLocation? boolean export to location list if true, otherwise export to quickfix list
---@return boolean ret return true if successful, otherwise return false
function M.exportLastSearchToQuickfix(isLocation)
    return require('hlslens.main').exportToQuickfix(isLocation)
end

---Wrap 'n' and 'N' actions with nvim-ufo's peekFoldedLinesUnderCursor API, and start to render
---@param char string|'n'|'N'
---@param ... any parameters of `peekFoldedLinesUnderCursor` API for nvim-ufo
---@return boolean ret return true if enabled, otherwise return false
---@return number winid
function M.nNPeekWithUFO(char, ...)
    return require('hlslens.ext.ufo'):nN(char, ...)
end

function M.setup(opts)
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
