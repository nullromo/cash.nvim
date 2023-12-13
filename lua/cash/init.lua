local CashModule = {}

function CashModule.setup(options)
    vim.api.nvim_create_user_command(
        'TimeToTest',
        function()
            vim.notify('cool')
        end,
        { bang = true }
    )
end

return CashModule
