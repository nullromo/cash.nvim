-- create module object for export
local CashModule = {}

-- main setup function for Cash.nvim
function CashModule.setup(options)
    -- make sure options is not nil
    options = options or {}

    -- set default message if one is not provided
    options.message = options.message or 'hello'

    -- validate options
    for key, value in pairs(options) do
        if key == 'message' then
            if type(value) ~= 'string' then
                error('options.message must be a string for Cash.nvim')
            end
        else
            -- error!
            error('"' .. key .. '" is not a valid option for Cash.nvim')
        end
    end

    vim.api.nvim_create_user_command(
        'TimeToTest',
        function()
            vim.notify(options.message)
        end,
        { bang = true }
    )
end

-- export module
return CashModule
