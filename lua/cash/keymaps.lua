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
        -- the chooser shows which number is which color, so that the digit to
        -- press is on screen rather than in the user's memory. chooser.style =
        -- 'none' asks with a message instead, as this always used to
        local index = ui.chooseRegister(cash)

        if index == nil then
            vim.notify(
                'Cash.nvim: you must enter a digit from 1 to 9 to choose a '
                    .. 'cash register'
            )
            return
        end

        cash.setCashRegister(index)
    end)

    -- run custom functions after searching. Whenever the user performs a normal
    -- search, we need to make sure to update some things
    vim.keymap.set('c', '<CR>', function()
        -- check if the current command is a search command
        local commandType = vim.fn.getcmdtype()
        if commandType == '/' or commandType == '?' then
            -- update Cash.nvim for the new search
            cash.setSearch(vim.fn.getcmdline())

            -- the search is about to move the cursor itself
            cash.expectSearchMove()

            -- the search has not run yet: this mapping only hands back the
            -- <CR> that sets it going. Centering therefore has to wait for
            -- the cursor to arrive, which is the next turn of the event loop.
            -- A search that finds nothing leaves the cursor where it was, and
            -- vim does not scroll the window for one, so neither does this
            local before = vim.api.nvim_win_get_cursor(0)
            vim.schedule(function()
                local after = vim.api.nvim_win_get_cursor(0)
                if not vim.deep_equal(after, before) then
                    cash.centerWindow()
                end
            end)
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
            cash.expectSearchMove()

            -- if a count was supplied, execute */# normally and exit
            if vim.v.count > 0 then
                vim.cmd('normal! ' .. vim.v.count .. keyPressed)
            else
                -- save current window view
                local windowView = vim.fn.winsaveview()

                -- execute */# normally
                vim.cmd('silent keepjumps normal! ' .. keyPressed)

                -- restore the window view
                if windowView ~= nil and cash.opts.disableStarPoundJump then
                    vim.fn.winrestview(windowView)
                end
            end

            -- center the screen
            cash.centerWindow()
        end)
    end

    -- set keymaps for * and # to update module state
    addKeyTrigger('n', '*', starPoundAction(true), true)
    addKeyTrigger('n', '#', starPoundAction(false), true)

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
            cash.showHighlighting()
        end,
        -- issue #16's real-time switch
        autohide = function(argument)
            if argument == 'on' then
                cash.opts.autoNoHighlight = true
            elseif argument == 'off' then
                cash.opts.autoNoHighlight = false
            elseif argument == 'toggle' or argument == nil then
                cash.opts.autoNoHighlight = not cash.opts.autoNoHighlight
            else
                vim.api.nvim_echo({
                    {
                        'Cash.nvim: :Cash autohide takes on, off or toggle',
                        'ErrorMsg',
                    },
                }, true, {})
                return
            end

            vim.notify(
                'Cash.nvim: highlighting '
                    .. (cash.opts.autoNoHighlight and 'clears' or 'stays')
                    .. ' when the cursor moves'
            )
        end,
    }

    -- autohide is the one verb whose argument is not a cash register
    local autohideArguments = { 'on', 'off', 'toggle' }

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
                elseif words[2] == 'autohide' then
                    candidates = vim.deepcopy(autohideArguments)
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
