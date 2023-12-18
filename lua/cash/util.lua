local util = {}

util.throw = function(valueName, requiredType)
    error(valueName .. ' must be a ' .. requiredType .. 'for Cash.nvim')
end

util.checkType = function(value, valueName, typeName)
    if type(value) ~= typeName then
        util.throw(valueName, typeName)
    end
end

local wrappers = {}

-- no-throw wrapper for vim matchdelete function
wrappers.matchdelete = function(matchID)
    -- set up return value
    local returnValue = 0
    -- use protected call
    local deleteOK, deleteError = pcall(function()
        -- call underlying vim function
        returnValue = vim.fn.matchdelete(matchID)
    end)
    -- report error if necessary
    if not deleteOK then
        vim.notify(tostring(deleteError), vim.log.levels.ERROR)
    end
    -- return actual value from underlying vim function
    return returnValue
end

util.wrappers = wrappers

return util
