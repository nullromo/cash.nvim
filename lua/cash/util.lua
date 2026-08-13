local util = {}

util.throw = function(valueName, requiredType)
    error(valueName .. ' must be a ' .. requiredType .. 'for Cash.nvim')
end

util.checkType = function(value, valueName, typeName)
    if type(value) ~= typeName then
        util.throw(valueName, typeName)
    end
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

return util
