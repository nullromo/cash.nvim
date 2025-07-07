local keymaps = {}

-- adds a mapping without disturbing existing mappings
local addKeyTrigger = function(mode, key, callback, prepend)
    -- get the current keymap for the key
    local keymap = vim.fn.maparg(key, mode, false, true)

    -- if there is no current keymap, create a new keymap with the new callback
    if next(keymap) == nil then
        vim.keymap.set(mode, key, function()
            callback()
            return key
        end, { expr = true })
        return
    end

    -- execute the old mapping's action
    local do_old_mapping = function()
        -- if the old mapping was defined with a function, then it will have a
        -- callback to call. Otherwise, it will have a right-hand-side to
        -- execute in normal mode
        if keymap.callback ~= nil then
            keymap.callback()
        else
            vim.schedule(function()
                vim.cmd('normal! ' .. keymap.rhs)
            end)
        end
    end

    -- create a new keymap that calls both the old and new callbacks
    vim.keymap.set(mode, key, function()
        -- the ordering of the old and new callbacks can be chosen
        if prepend then
            callback()
            do_old_mapping()
        else
            do_old_mapping()
            callback()
        end
    end, { remap = true })
end

keymaps.setUpKeymaps = function(cash)
    -- set the cash register switching keymap. Use ?<number> to swap to the
    -- <number>-th search pattern
    vim.keymap.set('n', '?', function()
        -- get a character from the user
        vim.notify('Enter a digit to choose a cash register')
        local userNumber = tonumber(vim.fn.nr2char(vim.fn.getchar()))

        -- clear the command line
        vim.api.nvim_echo({ { '', '' } }, false, {})

        -- if the user didn't enter a number, do nothing
        if userNumber == nil then
            vim.notify(
                'Error: you must enter a digit to select a cash register'
            )
            return
        end

        -- set the active cash register to the user's desired number
        cash.setCashRegister(userNumber)
    end)

    -- run custom functions after searching. Whenever the user performs a normal
    -- search, we need to make sure to update some things
    vim.keymap.set('c', '<CR>', function()
        -- check if the current command is a search command
        local commandType = vim.fn.getcmdtype()
        if commandType == '/' or commandType == '?' then
            -- update Cash.nvim for the new search
            cash.setSearch(vim.fn.getcmdline())
        end

        -- execute the command as normal
        return '<CR>'
    end, { expr = true })

    -- action to run when the user presses * or # from normal mode
    local starPoundAction = function(usingStar)
        return vim.schedule_wrap(function()
            -- choose the key pressed based on the argument
            local keyPressed = usingStar and '*' or '#'

            -- set the search pattern as */# normally would
            cash.setSearch(vim.fn.expand('<cword>'))

            -- if a count was supplied, execute */# normally and exit
            if vim.v.count > 0 then
                vim.cmd('normal! ' .. vim.v.count .. keyPressed .. '<CR>')
            else
                -- save current window view
                local windowView = vim.fn.winsaveview()

                -- execute */# normally
                vim.cmd('silent keepjumps normal! ' .. keyPressed .. '<CR>')

                -- restore the window view
                if windowView ~= nil and cash.opts.disableStarPoundJump then
                    vim.fn.winrestview(windowView)
                end
            end

            -- center the screen
            if cash.opts.centerAfterSearch then
                vim.cmd('normal! zz<CR>')
            end
        end)
    end

    -- set keymaps for * and # to update module state
    addKeyTrigger('n', '*', starPoundAction(true), true)
    addKeyTrigger('n', '#', starPoundAction(true), true)

    -- Use clc in command mode to clear the search
    vim.keymap.set('c', 'clc<CR>', function()
        -- check which command line the command was entered in
        local commandType = vim.fn.getcmdtype()

        -- if it was entered in ex mode
        if commandType == ':' then
            -- clear the current search
            cash.setSearch('')

            -- exit ex mode normally
            return '<CR>'
        end

        -- if it was entered in a search command
        if commandType == '/' or commandType == '?' then
            -- search for the literal string
            cash.setSearch('clc')
        end

        -- exit the search normally
        return 'clc<CR>'
    end, { expr = true })

    -- clear all searches and start back at index 1
    vim.api.nvim_create_user_command(
        'ResetCashRegisters',
        cash.resetCashRegisters,
        { bang = true }
    )
end

return keymaps
