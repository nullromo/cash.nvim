local ui = require('cash.ui')
local util = require('cash.util')

local keymaps = {}

-- every mapping this plugin makes says so, both so that which-key and friends
-- have something to show and so that addKeyTrigger can recognise its own work.
-- Exported because it is also how the health check tells a key this plugin
-- still owns from one something else has since taken
local ownMapping = 'Cash.nvim: '
keymaps.ownMapping = ownMapping

-- adds a mapping without disturbing existing mappings.
--
-- runsTheKey says whether the callback does the key's own work itself. A
-- callback that does not is followed by the key being handed back to vim, so
-- that pressing it still does everything it used to. One that does must not be
-- handed it as well, or the key's own action happens a second time -- which,
-- for a key that searches, is a second search and a jump that was meant to be
-- suppressed
---@param mode string
---@param key string
---@param callback fun()
---@param prepend boolean true to run the callback before the old mapping
---@param runsTheKey boolean true when the callback does the key's own work
---@param desc string
local addKeyTrigger = function(mode, key, callback, prepend, runsTheKey, desc)
    -- get the current keymap for the key
    local keymap = vim.fn.maparg(key, mode, false, true) --[[@as table]]

    -- a mapping this plugin made earlier is replaced rather than wrapped.
    -- Wrapped, a second setup would leave two of them on the key and the
    -- search would happen twice for one keypress
    if
        next(keymap) ~= nil
        and type(keymap.desc) == 'string'
        and vim.startswith(keymap.desc, ownMapping)
    then
        keymap = {}
    end

    -- if there is no current keymap, create a new keymap with the new callback
    if next(keymap) == nil then
        if runsTheKey then
            vim.keymap.set(mode, key, callback, { desc = desc })
            return
        end

        vim.keymap.set(mode, key, function()
            callback()
            return key
        end, { expr = true, desc = desc })
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
    end, { remap = true, desc = desc })
end

---@param cash cash.Module
keymaps.setUpKeymaps = function(cash)
    -- set the cash register switching keymap. Use ?<number> to swap to the
    -- <number>-th search pattern, or ?? for whichever cash register is
    -- highlighting the text under the cursor
    vim.keymap.set('n', '?', function()
        -- the chooser shows which number is which color, so that the digit to
        -- press is on screen rather than in the user's memory. chooser.style =
        -- 'none' asks with a message instead, as this always used to
        local choice = ui.chooseRegister(cash)

        if choice == nil then
            vim.notify(
                'Cash.nvim: you must enter a digit from 1 to 9 to choose a '
                    .. 'cash register'
            )
            return
        end

        -- a second ? asks for the cash register that is highlighting the text
        -- under the cursor, which is a question about the buffer rather than
        -- about the nine
        if choice == 'under-cursor' then
            cash.setCashRegisterUnderCursor()
            return
        end

        -- the chooser answers with one of the nine or with the one under the
        -- cursor, and the other of the two has just been dealt with. The
        -- checker cannot work that out for itself
        ---@cast choice cash.RegisterIndex
        cash.setCashRegister(choice)
    end, { desc = ownMapping .. 'choose the working cash register' })

    -- run custom functions after searching. Whenever the user performs a normal
    -- search, we need to make sure to update some things
    vim.keymap.set('c', '<CR>', function()
        -- check if the current command is a search command
        local commandType = vim.fn.getcmdtype()
        if commandType == '/' or commandType == '?' then
            -- the search is about to move the cursor itself
            cash.expectSearchMove()

            -- the search has not run yet: this mapping only hands back the
            -- <CR> that sets it going. Both the pattern and the centering
            -- therefore have to wait for it, which is the next turn of the
            -- event loop.
            --
            -- The pattern is taken from the search register afterwards rather
            -- than from the command line beforehand, because the two are not
            -- the same thing. A search offset (/foo/e) is typed but is no part
            -- of the pattern, and an empty command line is not a search for
            -- nothing but a repeat of the last search -- taken literally, it
            -- emptied the search register in front of the search that was
            -- about to reuse it, so the repeat failed with E35 and the cash
            -- register was thrown away with it. Vim has worked all of that out
            -- by the time this runs, and @/ is the answer it came to. It is
            -- set even for a pattern vim cannot compile, so a cash register
            -- can still hold one of those
            --
            -- A search that finds nothing leaves the cursor where it was, and
            -- vim does not scroll the window for one, so neither does this
            local before = vim.api.nvim_win_get_cursor(0)
            vim.schedule(function()
                cash.setSearch(vim.fn.getreg('/'))

                local after = vim.api.nvim_win_get_cursor(0)
                if not vim.deep_equal(after, before) then
                    cash.centerWindow()
                end
            end)
        end

        -- execute the command as normal
        return '<CR>'
    end, {
        expr = true,
        desc = ownMapping .. 'fill the working cash register from a search',
    })

    -- what *, #, g* and g# do.
    --
    -- The search is run here rather than handed back to vim. Handed back, vim
    -- searches and jumps before this plugin can say a word about it, and a
    -- jump cannot be taken back afterwards: the view can be put where it was,
    -- but the jumplist has an entry by then and the search has already
    -- happened. disableStarPoundJump is a promise that the cursor stays where
    -- it is, so the one search there is has to be this one
    ---@param key string one of *, #, g* and g#
    ---@return fun()
    local starPoundAction = function(key)
        return function()
            -- read before the search, since the search is what would change
            -- them
            local windowView = vim.fn.winsaveview()
            local count = vim.v.count > 0 and tostring(vim.v.count) or ''

            -- a count is the user naming the occurrence to go to, which is an
            -- instruction to move whatever disableStarPoundJump says
            local stayPut = cash.opts.disableStarPoundJump and count == ''

            -- the cursor is about to move for a search, even where it is put
            -- straight back afterwards
            cash.expectSearchMove()

            -- keepjumps only where the jump is being undone anyway: a * that
            -- is allowed to move the cursor belongs in the jumplist, exactly
            -- as vim's own does. The messages go the same way -- vim's "search
            -- hit BOTTOM" is worth having when the cursor really did travel,
            -- and is a puzzle when it did not
            local ok, err = pcall(function()
                vim.cmd(
                    (stayPut and 'silent keepjumps normal! ' or 'normal! ')
                        .. count
                        .. key
                )
            end)

            -- E348 when there is no word under the cursor, which is the
            -- ordinary way to press * by accident. Nothing has been searched
            -- for, so the cash register is left holding what it held
            if not ok then
                util.echoVimError(err)
                return
            end

            -- vim has just put what it searched for in the search register:
            -- \<word\> for * and #, the bare word for g* and g#. That, rather
            -- than the word under the cursor, is what this cash register
            -- takes, so that switching away from it and back searches for the
            -- same thing again. Stored as the bare word, a * search comes back
            -- out of its own register as a g* search, matching inside other
            -- words
            cash.setSearch(vim.fn.getreg('/'))

            -- put the cursor back where it was, if it was never meant to leave
            if stayPut then
                vim.fn.winrestview(windowView)
            end

            -- center the screen
            cash.centerWindow()
        end
    end

    -- set keymaps for *, #, g* and g# to update module state. The g-versions
    -- are here for the same reason as the other two: they search, so the
    -- working cash register has to hear about it, and so does autoNoHighlight
    local starPoundDescriptions = {
        ['*'] = 'the word under the cursor',
        ['#'] = 'the word under the cursor, backwards',
        ['g*'] = 'the word under the cursor, inside other words too',
        ['g#'] = 'the word under the cursor, backwards, inside other words too',
    }

    for key, description in pairs(starPoundDescriptions) do
        addKeyTrigger(
            'n',
            key,
            starPoundAction(key),
            true,
            true,
            ownMapping .. 'search for ' .. description
        )
    end

    -- n and N move between the matches of every cash register in the search
    -- set, not just the working one. Only normal mode is taken: in operator
    -- pending and visual mode, dn and vn keep reading @/, which is the working
    -- cash register on its own
    if cash.opts.manageJumps then
        vim.keymap.set(
            'n',
            'n',
            cash.nextMatch,
            { desc = ownMapping .. 'next match in the search set' }
        )

        vim.keymap.set(
            'n',
            'N',
            cash.previousMatch,
            { desc = ownMapping .. 'previous match in the search set' }
        )
    end

    -- one command with verbs, rather than a command per action, so that this
    -- plugin takes one name in the command namespace instead of nine
    ---@type table<string, fun(argument?: string)>
    local verbs = {
        [''] = function()
            ui.open(cash)
        end,
        use = function(argument)
            cash.setCashRegister(tonumber(argument))
        end,
        here = function()
            cash.setCashRegisterUnderCursor()
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
