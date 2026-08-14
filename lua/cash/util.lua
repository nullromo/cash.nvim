local util = {}

util.throw = function(valueName, requiredType)
    error(valueName .. ' must be a ' .. requiredType .. 'for Cash.nvim')
end

util.checkType = function(value, valueName, typeName)
    if type(value) ~= typeName then
        util.throw(valueName, typeName)
    end
end

-- nvim_open_win takes a named border or a list of the pieces to build one
-- from, so both are allowed through
util.checkBorder = function(value, valueName)
    if type(value) ~= 'string' and type(value) ~= 'table' then
        error('"' .. valueName .. '" must be a string or a table for Cash.nvim')
    end
end

-- for an option that only has a handful of legal answers. The complaint names
-- all of them, since the whole point is that the user cannot guess
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
util.resolveCase = function(pattern)
    if string.find(pattern, '\\c') or string.find(pattern, '\\C') then
        return pattern
    end
    return (vim.opt.ignorecase:get() and '\\c' or '\\C') .. pattern
end

-- true if the given value names one of the nine cash registers. Anything else
-- is rejected rather than trusted, wherever it came from
util.isCashRegisterIndex = function(value)
    return type(value) == 'number'
        and value >= 1
        and value <= 9
        and value == math.floor(value)
end

return util
