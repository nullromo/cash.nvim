local util = {}

util.throw = function(valueName, requiredType)
    error(valueName .. ' must be a ' .. requiredType .. 'for Cash.nvim')
end

util.checkType = function(value, valueName, typeName)
    if type(value) ~= typeName then
        util.throw(valueName, typeName)
    end
end

return util
