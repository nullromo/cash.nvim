local util = {}

---@param valueName string the option's name, as the user wrote it
---@param requiredType string
util.throw = function(valueName, requiredType)
    error(valueName .. ' must be a ' .. requiredType .. ' for Cash.nvim')
end

---@param value any straight from the user's options table
---@param valueName string
---@param typeName type
util.checkType = function(value, valueName, typeName)
    if type(value) ~= typeName then
        util.throw(valueName, typeName)
    end
end

-- nvim_open_win takes a named border or a list of the pieces to build one
-- from, so both are allowed through
---@param value any
---@param valueName string
util.checkBorder = function(value, valueName)
    if type(value) ~= 'string' and type(value) ~= 'table' then
        error('"' .. valueName .. '" must be a string or a table for Cash.nvim')
    end
end

-- for an option that only has a handful of legal answers. The complaint names
-- all of them, since the whole point is that the user cannot guess
---@param value any
---@param valueName string
---@param allowed string[] every answer this option accepts
util.checkOneOf = function(value, valueName, allowed)
    for _, candidate in ipairs(allowed) do
        if value == candidate then
            return
        end
    end

    error(
        '"'
            .. valueName
            .. '" must be one of '
            .. table.concat(allowed, ', ')
            .. ' for Cash.nvim'
    )
end

-- true if vim will accept the given string as a search pattern.
--
-- A cash register holds whatever the user typed, which includes patterns vim
-- cannot compile, so anything about to hand a pattern to vim has to ask first.
-- Matching against an empty string compiles the pattern without needing a
-- buffer, and throws if it cannot be compiled
---@param pattern string
---@return boolean
util.isUsablePattern = function(pattern)
    return (pcall(vim.fn.match, '', pattern))
end

-- works out the pattern that vim should actually be asked to match, which is
-- the cash register's pattern plus a case flag. An explicit \c or \C in the
-- pattern wins, and makes the value of ignorecase irrelevant.
--
-- Note that \c and \C are not local to the group they are written in: either
-- one applies to the whole pattern wherever it appears. That is why cash
-- registers are never joined into a single pattern with \|, and why every
-- caller resolves them one at a time
---@param pattern string a search pattern, as the user typed it
---@return string matchPattern what vim is actually given
util.resolveCase = function(pattern)
    if string.find(pattern, '\\c') or string.find(pattern, '\\C') then
        return pattern
    end
    return (vim.o.ignorecase and '\\c' or '\\C') .. pattern
end

-- shows a failure from :normal the way vim would have, without the lua
-- traceback wrapped round it
---@param err any whatever pcall handed back
util.echoVimError = function(err)
    local message = tostring(err):match('(E%d+:.*)$') or tostring(err)
    vim.api.nvim_echo({ { message, 'ErrorMsg' } }, true, {})
end

-- one of the nine cash registers, as an index into state.cashRegisters.
--
-- Deliberately not written out as 1|2|3|4|5|6|7|8|9. That would be the truth
-- about the value, but nothing that computes an index -- a cursor row, a
-- tonumber of a command argument, an index plus one -- can be narrowed to it,
-- so every one of those would need a cast that says nothing. The range is
-- enforced where it can be enforced, which is isCashRegisterIndex, and every
-- function taking an index from outside the plugin calls it
---@alias cash.RegisterIndex integer

-- true if the given value names one of the nine cash registers. Anything else
-- is rejected rather than trusted, wherever it came from
---@param value any
---@return boolean
util.isCashRegisterIndex = function(value)
    return type(value) == 'number'
        and value >= 1
        and value <= 9
        and value == math.floor(value)
end

return util
