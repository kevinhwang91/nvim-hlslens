local fn = vim.fn
local api = vim.api
local cmd = vim.cmd

---@class HlslensCmdLineParser
---@field type string
---@field line string
---@field lastLine string
---@field name? string
---@field pattern? string
---@field range? number[]
---@field lastPattern? string
---@field offset? string
---@field originCursor number[] (1, 0)-indexed position
local CmdLineParser = {
    builtinCmds = {
        substitute = 1,
        snomagic = 1,
        smagic = 1,
        vglobal = 2,
        vimgrep = 2,
        vimgrepadd = 2,
        lvimgrep = 2,
        lvimgrepadd = 2,
        global = 2,
    }
}

function CmdLineParser:new(typ, originCursor)
    local o = setmetatable({}, self)
    self.__index = self
    o.type = typ
    o.originCursor = originCursor
    o.line = ''
    o.lastLine = ''
    o.pattern = nil
    o.lastPattern = nil
    return o
end

function CmdLineParser:setLine(line)
    self.lastLine, self.line = self.line, line
end

function CmdLineParser:lineChanged()
    return self.lastLine ~= self.line
end

function CmdLineParser:setPattern(pattern)
    self.lastPattern, self.pattern = self.pattern, pattern
end

function CmdLineParser:patternChanged()
    return self.lastPattern ~= self.pattern
end

function CmdLineParser:isEmptyVisualAreaPattern()
    return self.pattern == [[\%V]]
end

function CmdLineParser:hasOffset()
    return self.offset ~= '' or self.multiple
end

function CmdLineParser:isSubstitute()
    return self.builtinCmds[self.name] == 1
end

function CmdLineParser:validatePattern()
    if not self.pattern or self:isSubstitute() and self.delimClosed then
        return false
    end
    -- \V, \%V, .., etc.
    if #self.pattern <= 3 then
        if #self.pattern < 2 or self.pattern:sub(1, 1) == [[\]] or self.pattern == '..' then
            return false
        end
    end
    return true
end

function CmdLineParser:doParse()
    if self.type == ':' then
        if #self.line > 200 or not api.nvim_parse_cmd then
            return false
        end
        local ok, parsed = pcall(api.nvim_parse_cmd, self.line, {})
        if ok then
            if self.builtinCmds[parsed.cmd] then
                self.name, self.range = parsed.cmd, parsed.range
                if self.range == nil or vim.tbl_isempty(self.range) then
                    if self:isSubstitute() then
                        local lnum = self.originCursor[1]
                        self.range = {lnum, lnum}
                    else
                        self.range = {1, api.nvim_buf_line_count(0)}
                    end
                elseif #self.range == 1 then
                    table.insert(self.range, self.range[1])
                end
            end
            if #parsed.args == 0 or not self.name then
                return false
            end
        else
            -- TODO
            -- may throw error, need an extra pcall command to eat it
            pcall(cmd, '')
            return false
        end
        self:parseBuiltinCmd(parsed.args)
        self.offset, self.multiple = '', false
    else
        local pat
        pat, self.offset, self.multiple = self:splitPattern()
        self:setPattern(pat)
    end
    return self.pattern ~= nil
end

---
---@param args string[]
function CmdLineParser:parseBuiltinCmd(args)
    local str = table.concat(args, ' ')
    local firstByte = str:byte(1, 1)
    local opening
    local i = 2
    if self.name == 'global' then
        str = str:match('^%s*(.*)$')
    elseif not self:isSubstitute() then
        if 48 <= firstByte and firstByte <= 57 or 65 <= firstByte and firstByte <= 90 or
            97 <= firstByte and firstByte <= 122 then
            opening = ' '
            i = 1
        end
    end
    self.delimClosed = false
    if #str == 1 and self:isSubstitute() then
        self:setPattern(fn.getreg('/'))
    elseif #str == 2 and firstByte == str:byte(-1) then
        self.delimClosed = true
        self:setPattern(fn.getreg('/'))
    else
        opening = opening and opening or string.char(firstByte)
        local s = str:find(opening, 2, true)
        if s then
            self.delimClosed = true
            self:setPattern(str:sub(i, s - 1))
        else
            self:setPattern(str:sub(i))
        end
    end
end

function CmdLineParser:splitPattern()
    local pat
    local off = ''
    local mul = false
    local typ, line = self.type, self.line
    local delim = typ or '/'
    local i = 0
    local start = i + 1

    while true do
        i = line:find(delim, i + 1)
        if not i then
            pat = line:sub(start)
            break
        end
        if line:sub(i - 1, i - 1) ~= [[\]] then
            -- For example: "/pat/;/foo/+3;?bar"
            if line:sub(i + 1, i + 1) == ';' then
                i = i + 2
                start = i + 1
                delim = line:sub(i, i)
                if i <= #line then
                    mul = true
                end
            else
                pat = line:sub(start, i - 1)
                if pat == '' then
                    pat = fn.getreg('/')
                end
                off = line:sub(i + 1)
                break
            end
        end
    end
    return pat, off, mul
end

return CmdLineParser
