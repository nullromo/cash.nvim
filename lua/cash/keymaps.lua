local ui = require('cash.ui')

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
                vim.cmd(
                    'execute "normal! '
                        .. vim.api.nvim_replace_termcodes(
                            keymap.rhs,
                            true,
                            false,
                            true
                        )
                        .. '"'
                )
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
    addKeyTrigger('n', '#', starPoundAction(false), true)

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

    -- n and N move between the matches of every cash register in the search
    -- set, not just the working one. Only normal mode is taken: in operator
    -- pending and visual mode, dn and vn keep reading @/, which is the working
    -- cash register on its own
    if cash.opts.manageJumps then
        vim.keymap.set(
            'n',
            'n',
            cash.nextMatch,
            { desc = 'Cash.nvim: next match in the search set' }
        )

        vim.keymap.set(
            'n',
            'N',
            cash.previousMatch,
            { desc = 'Cash.nvim: previous match in the search set' }
        )
    end

    -- one command with verbs, rather than a command per action, so that this
    -- plugin takes one name in the command namespace instead of nine
    local verbs = {
        [''] = function()
            ui.open(cash)
        end,
        use = function(argument)
            cash.setCashRegister(tonumber(argument))
        end,
        include = function(argument)
            cash.setIncludeInSearch(tonumber(argument), true)
        end,
        exclude = function(argument)
            cash.setIncludeInSearch(tonumber(argument), false)
        end,
        toggle = function(argument)
            cash.toggleIncludeInSearch(tonumber(argument))
        end,
        clear = function(argument)
            cash.clearCashRegister(argument and tonumber(argument))
        end,
        reset = function()
            cash.resetCashRegisters()
        end,
        -- hide and show drive v:hlsearch, which every cash register follows,
        -- so :Cash hide is exactly :nohlsearch and the next search undoes it
        hide = function()
            pcall(function()
                vim.v.hlsearch = 0
            end)
            cash.updateHighlights()
        end,
        show = function()
            pcall(function()
                vim.v.hlsearch = 1
            end)
            cash.updateHighlights()
        end,
    }

    local takesIndex = {
        use = true,
        include = true,
        exclude = true,
        toggle = true,
        clear = true,
    }

    vim.api.nvim_create_user_command('Cash', function(opts)
        local words =
            vim.split(vim.trim(opts.args), '%s+', { trimempty = true })
        local verb = words[1] or ''
        local action = verbs[verb]

        if action == nil then
            -- echoed rather than raised. vim.notify at ERROR level throws
            -- from inside a command, which brings up a hit-enter prompt for
            -- what is only a typo; vim reports an unknown command itself
            -- without stopping to ask
            vim.api.nvim_echo({
                {
                    'Cash.nvim: "' .. verb .. '" is not a :Cash command',
                    'ErrorMsg',
                },
            }, true, {})
            return
        end

        action(words[2])
    end, {
        nargs = '*',
        desc = 'Cash.nvim: open the cash drawer, or act on a cash register',
        complete = function(argLead, cmdLine)
            local words =
                vim.split(vim.trim(cmdLine), '%s+', { trimempty = true })

            -- words[1] is the command itself, so a verb is already in place
            -- once there are two words and the cursor has moved past the
            -- second
            local haveVerb = #words > 2 or (#words == 2 and argLead == '')

            local candidates = {}
            if haveVerb then
                if takesIndex[words[2]] then
                    for index = 1, 9 do
                        table.insert(candidates, tostring(index))
                    end
                end
            else
                for verb in pairs(verbs) do
                    if verb ~= '' then
                        table.insert(candidates, verb)
                    end
                end
                table.sort(candidates)
            end

            return vim.tbl_filter(function(candidate)
                return candidate:sub(1, #argLead) == argLead
            end, candidates)
        end,
    })
end

return keymaps
