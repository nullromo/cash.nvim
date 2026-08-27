-- Tests for the rule the whole plugin exists to keep true:
--
--     window W has a highlight for cash register i exactly when i is not the
--     working cash register and cash register i's pattern is not empty
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')
    local constants = require('cash.constants')
    local highlights = require('cash.highlights')
    local options = require('cash.options')

    -- every match in a window, as "group=pattern", sorted so it can be
    -- compared as a single string
    local function matchesIn(windowID)
        local out = {}
        for _, match in ipairs(vim.fn.getmatches(windowID)) do
            table.insert(out, match.group .. '=' .. match.pattern)
        end
        table.sort(out)
        return table.concat(out, ' ')
    end

    -- the pattern one cash register is highlighting in a window, or nil
    local function matchFor(windowID, index)
        for _, match in ipairs(vim.fn.getmatches(windowID)) do
            if match.group == 'CashRegister' .. index then
                return match.pattern
            end
        end
        return nil
    end

    local function ledgerWindowCount()
        return #highlights.trackedWindows()
    end

    -- a single empty window with the plugin freshly set up. Returns its ID
    local function fresh(opts)
        vim.cmd('silent! tabonly')
        vim.cmd('silent! only')
        vim.opt.ignorecase = false
        cash.setup(opts or {})
        cash.resetCashRegisters()
        return vim.fn.win_getid()
    end

    local function colorOf(name)
        return tonumber(constants.colors[name]:sub(2), 16)
    end

    ----------------------------------------------------------------------

    h.group('setup')

    do
        local window = fresh()

        cash.setCashRegister(2)
        cash.setSearch('bar')
        cash.setCashRegister(3)
        h.check(
            'a cash register is highlighted without waiting for a window event',
            matchesIn(window) == 'CashRegister2=\\Cbar',
            'got [' .. matchesIn(window) .. ']'
        )

        h.check(
            'each cash register gets its configured highlight group',
            vim.api.nvim_get_hl(0, { name = 'CashRegister1' }).bg
                == colorOf('roninYellow'),
            'got '
                .. tostring(
                    vim.api.nvim_get_hl(0, { name = 'CashRegister1' }).bg
                )
        )
    end

    ----------------------------------------------------------------------

    h.group('switching cash registers')

    do
        local window = fresh()

        cash.setSearch('hello')
        h.check(
            'the working cash register has no match of its own',
            matchesIn(window) == '',
            'got [' .. matchesIn(window) .. ']'
        )

        cash.setCashRegister(5)
        h.check(
            'moving off a cash register turns its pattern into a match',
            matchFor(window, 1) == '\\Chello',
            'got [' .. tostring(matchFor(window, 1)) .. ']'
        )

        cash.setCashRegister(1)
        h.check(
            'moving back onto it removes the match again',
            matchFor(window, 1) == nil,
            'got [' .. tostring(matchFor(window, 1)) .. ']'
        )

        -- selecting the cash register you are already in used to add a match
        -- for the working cash register, which then went stale on the next
        -- search and was never cleaned up
        cash.setCashRegister(1)
        h.check(
            'selecting the cash register you are already in adds no match',
            matchesIn(window) == '',
            'got [' .. matchesIn(window) .. ']'
        )

        cash.setSearch('goodbye')
        cash.setCashRegister(2)
        h.check(
            'and a later search in it highlights the new pattern',
            matchFor(window, 1) == '\\Cgoodbye',
            'got [' .. tostring(matchFor(window, 1)) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('cash register indices')

    do
        local window = fresh()
        cash.setSearch('kept')

        -- note the explicit count: a nil in a table literal would end an
        -- ipairs loop early and silently skip the rest
        local bad = { 0, 10, -1, 1.5, 'x', nil, {}, n = 7 }
        for index = 1, bad.n do
            h.check(
                'setCashRegister('
                    .. vim.inspect(bad[index])
                    .. ') does not throw',
                pcall(cash.setCashRegister, bad[index])
            )
        end

        h.check(
            'a rejected index leaves the working cash register alone',
            cash.state.currentIndex == 1,
            'got ' .. tostring(cash.state.currentIndex)
        )
        h.check(
            'and leaves the highlights alone',
            matchesIn(window) == '',
            'got [' .. matchesIn(window) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('idempotency')

    do
        local window = fresh()
        cash.setSearch('once')
        cash.setCashRegister(4)

        local before = matchesIn(window)
        for _ = 1, 20 do
            cash.updateHighlights()
        end
        h.check(
            'repeated updates change nothing',
            matchesIn(window) == before,
            'got [' .. matchesIn(window) .. '] want [' .. before .. ']'
        )
        h.check(
            'and do not accumulate matches',
            #vim.fn.getmatches(window) == 1,
            #vim.fn.getmatches(window) .. ' matches'
        )
    end

    ----------------------------------------------------------------------

    h.group('windows and tabs')

    do
        fresh()
        cash.setSearch('everywhere')
        cash.setCashRegister(6)

        vim.cmd('split')
        vim.cmd('tabnew')

        local everyWindow = true
        local windows = vim.api.nvim_list_wins()
        for _, windowID in ipairs(windows) do
            if matchFor(windowID, 1) ~= '\\Ceverywhere' then
                everyWindow = false
            end
        end
        h.check(
            'every window is highlighted, including one in an unvisited tab',
            everyWindow,
            #windows .. ' windows'
        )

        vim.cmd('tabclose')
        vim.cmd('only')
        cash.updateHighlights()
        h.check(
            'closed windows are dropped from the ledger',
            ledgerWindowCount() == #vim.api.nvim_list_wins(),
            'ledger has '
                .. ledgerWindowCount()
                .. ', vim has '
                .. #vim.api.nvim_list_wins()
        )
        h.check(
            'and the surviving window keeps its highlight',
            matchFor(vim.fn.win_getid(), 1) == '\\Ceverywhere',
            'got [' .. tostring(matchFor(vim.fn.win_getid(), 1)) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('case sensitivity')

    do
        local window = fresh()
        cash.setSearch('word')
        cash.setCashRegister(2)

        h.check(
            'ignorecase off gives a case-sensitive match',
            matchFor(window, 1) == '\\Cword',
            'got [' .. tostring(matchFor(window, 1)) .. ']'
        )

        -- the plugin used to have no way to react to this at all. Nothing is
        -- called below on purpose: the OptionSet hook has to notice by itself
        vim.opt.ignorecase = true
        h.check(
            'turning ignorecase on updates a non-working cash register',
            matchFor(window, 1) == '\\cword',
            'got [' .. tostring(matchFor(window, 1)) .. ']'
        )

        vim.opt.ignorecase = false
        h.check(
            'and turning it off again puts it back',
            matchFor(window, 1) == '\\Cword',
            'got [' .. tostring(matchFor(window, 1)) .. ']'
        )

        cash.setCashRegister(3)
        cash.setSearch('\\cSHOUT')
        cash.setCashRegister(4)
        local explicit = matchFor(window, 3)
        vim.opt.ignorecase = true
        h.check(
            'an explicit \\c is left alone when ignorecase changes',
            matchFor(window, 3) == explicit and explicit == '\\cSHOUT',
            'got [' .. tostring(matchFor(window, 3)) .. ']'
        )
        h.check(
            'while its neighbour still follows ignorecase',
            matchFor(window, 1) == '\\cword',
            'got [' .. tostring(matchFor(window, 1)) .. ']'
        )
        vim.opt.ignorecase = false
    end

    ----------------------------------------------------------------------

    h.group('patterns vim cannot compile')

    do
        local window = fresh()

        local notifications = 0
        local realNotify = vim.notify
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.notify = function(...)
            notifications = notifications + 1
            return realNotify(...)
        end

        cash.setSearch('\\(')
        h.check(
            'switching away from an unusable pattern does not throw',
            pcall(cash.setCashRegister, 7)
        )
        h.check(
            'the pattern is stored as typed, the way vim stores it in @/',
            cash.state.cashRegisters[1].pattern == '\\(',
            'got [' .. tostring(cash.state.cashRegisters[1].pattern) .. ']'
        )
        h.check(
            'it highlights nothing',
            matchFor(window, 1) == nil,
            'got [' .. tostring(matchFor(window, 1)) .. ']'
        )
        h.check(
            'switching back onto it does not throw',
            pcall(cash.setCashRegister, 1)
        )
        h.check(
            'and the search register agrees with the cash register',
            vim.fn.getreg('/') == '\\(',
            'got [' .. vim.fn.getreg('/') .. ']'
        )

        for _ = 1, 10 do
            cash.updateHighlights()
        end
        vim.cmd('split')
        h.check(
            'an unusable pattern is never announced',
            notifications == 0,
            notifications .. ' notification(s)'
        )
        vim.notify = realNotify

        cash.setSearch('usable')
        cash.setCashRegister(8)
        h.check(
            'fixing the pattern brings the highlight back',
            matchFor(vim.fn.win_getid(), 1) == '\\Cusable',
            'got [' .. tostring(matchFor(vim.fn.win_getid(), 1)) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('resetting')

    do
        local window = fresh()
        cash.setSearch('one')
        cash.setCashRegister(2)
        cash.setSearch('two')
        cash.setCashRegister(3)

        cash.resetCashRegisters()
        h.check(
            'reset removes every match',
            matchesIn(window) == '',
            'got [' .. matchesIn(window) .. ']'
        )
        local allEmpty = true
        for index = 1, 9 do
            local register = cash.state.cashRegisters[index]
            if register.pattern ~= '' or register.includeInSearch then
                allEmpty = false
            end
        end
        h.check('reset empties every cash register', allEmpty)
        h.check(
            'reset returns to cash register 1',
            cash.state.currentIndex == 1
        )

        -- the ledger used to be thrown away on reset, which left the matches
        -- it described stranded in vim with nothing tracking them
        cash.setSearch('after')
        cash.setCashRegister(2)
        h.check(
            'and the plugin still works afterwards',
            matchFor(window, 1) == '\\Cafter',
            'got [' .. tostring(matchFor(window, 1)) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('options')

    do
        fresh()
        h.check(
            'defaults are filled in',
            cash.opts.centerAfterSearch == true
                and cash.opts.disableStarPoundJump == true
                and cash.opts.respectHLSearch == false
        )

        h.check(
            'an unknown option is rejected',
            not pcall(cash.setup, { bogus = true })
        )
        h.check(
            'an option of the wrong type is rejected',
            ---@diagnostic disable-next-line: assign-type-mismatch
            not pcall(cash.setup, { centerAfterSearch = 'yes' })
        )

        local custom = {}
        for index = 1, 9 do
            custom[index] = { bg = string.format('#0000%02X', index) }
        end
        fresh({ colors = { highlightColors = custom } })

        local everyGroup = true
        for index = 1, 9 do
            if
                vim.api.nvim_get_hl(0, { name = 'CashRegister' .. index }).bg
                ~= index
            then
                everyGroup = false
            end
        end
        h.check('configured colors reach the highlight groups', everyGroup)

        -- `or` defaulting could not express false, so an option whose default
        -- was true could never be turned off at all
        fresh({ centerAfterSearch = false })
        h.check(
            'centerAfterSearch = false is respected',
            cash.opts.centerAfterSearch == false,
            'resolves to ' .. tostring(cash.opts.centerAfterSearch)
        )

        fresh({ disableStarPoundJump = false })
        h.check(
            'disableStarPoundJump = false is respected',
            cash.opts.disableStarPoundJump == false,
            'resolves to ' .. tostring(cash.opts.disableStarPoundJump)
        )

        -- resolving used to write defaults into whatever table the caller
        -- passed in, and to hand back this module's own default tables
        local caller = { centerAfterSearch = false }
        fresh(caller)
        h.check(
            "the caller's own options table is not written to",
            vim.deep_equal(caller, { centerAfterSearch = false }),
            'became ' .. vim.inspect(caller)
        )
        h.check(
            'and the result does not alias the defaults',
            cash.opts.colors.highlightColors[1]
                ~= options.defaultOptions.colors.highlightColors[1]
        )

        -- a short list of colors used to leave the rest nil, which crashed
        -- later with "attempt to index a nil value" rather than saying what
        -- was actually wrong
        h.check(
            'a highlightColors list that is not 9 long is rejected',
            not pcall(cash.setup, {
                colors = { highlightColors = { { bg = '#ABCDEF' } } },
            })
        )

        fresh()
    end

    ----------------------------------------------------------------------

    -- issue #27: the groups are made during setup, and loading a colorscheme
    -- clears every group the colorscheme does not go on to set itself. The
    -- matches were left pointing at nine empty groups, still matching and
    -- painting nothing, with nothing to say why
    h.group('a colorscheme loaded after setup')

    do
        local window = fresh()
        cash.setCashRegister(2)
        cash.setSearch('bar')
        cash.setCashRegister(3)

        local groupsBefore = {}
        for index = 1, 9 do
            groupsBefore['CashRegister' .. index] =
                vim.api.nvim_get_hl(0, { name = 'CashRegister' .. index })
            groupsBefore['CashRegisterFg' .. index] =
                vim.api.nvim_get_hl(0, { name = 'CashRegisterFg' .. index })
        end
        local searchBefore = vim.api.nvim_get_hl(0, { name = 'Search' })
        local matchesBefore = vim.fn.getmatches(window)

        vim.cmd.colorscheme('habamax')

        local groupsAfter = {}
        for name in pairs(groupsBefore) do
            groupsAfter[name] = vim.api.nvim_get_hl(0, { name = name })
        end

        h.check(
            'leaves every cash register group as it was',
            vim.deep_equal(groupsAfter, groupsBefore),
            'CashRegister2 became ' .. vim.inspect(groupsAfter['CashRegister2'])
        )

        h.check(
            'and puts the working cash register back on Search',
            vim.deep_equal(
                vim.api.nvim_get_hl(0, { name = 'Search' }),
                searchBefore
            ),
            'became '
                .. vim.inspect(vim.api.nvim_get_hl(0, { name = 'Search' }))
        )

        -- matchadd binds a match to a group by name and looks the color up at
        -- draw time, so re-creating the groups is the whole fix. A match that
        -- was deleted and added again would come back with a new ID
        h.check(
            'without rebuilding a single match',
            vim.deep_equal(vim.fn.getmatches(window), matchesBefore),
            'became ' .. vim.inspect(vim.fn.getmatches(window))
        )

        -- the rest of the suite shares this neovim, and is entitled to the
        -- colorscheme it started with
        vim.cmd.colorscheme('default')
        fresh()
    end
end
