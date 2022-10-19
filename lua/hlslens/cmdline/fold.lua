local fn = vim.fn
local cmd = vim.cmd

---@class HlslensCmdLineIncSearchFold
---@field undoLnums number[]
local IncSearchFold = {}

function IncSearchFold:new()
    local o = setmetatable({}, self)
    self.__index = self
    o.undoLnums = {}
    return o
end

function IncSearchFold:expand(lnum)
    self:undo()
    self:openRecursively(lnum)
end

function IncSearchFold:openRecursively(lnum)
    repeat
        local l = fn.foldclosed(lnum)
        if l > 0 then
            cmd(lnum .. 'foldopen')
            table.insert(self.undoLnums, l)
        end
    until l == -1
end

function IncSearchFold:undo()
    while #self.undoLnums > 0 do
        local l = table.remove(self.undoLnums)
        cmd(l .. 'foldclose')
    end
end

return IncSearchFold
