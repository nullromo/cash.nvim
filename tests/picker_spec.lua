-- Tests for the telescope picker: :Telescope cash_registers.
--
-- The rules these are about:
--
--     the picker has a row for every cash register, holding anything or not,
--     and each row's match count is about the window the picker was opened
--     from rather than about whichever window telescope has focused
--
--     selecting a row searches in that same window
--
--     telescope's own windows carry no cash register highlighting, for the
--     reason the drawer's window carries none: they list the patterns as
--     literal text
--
-- Telescope itself is not here. The suite runs with -u NONE and no plugins, so
-- what these cover is lua/cash/picker.lua, which is the half of the picker that
-- does not need it. See CONTRIBUTING.md.
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')
    local highlights = require('cash.highlights')
    local picker = require('cash.picker')

    -- 'foo' twice, so that a count of matches and a count of lines cannot be
    -- confused, and 'TODO' on the last line so that a search for it has to
    -- move the cursor
    local lines = { 'foo bar baz', 'foo again', 'TODO here' }

    local function fresh()
        vim.cmd('silent! tabonly')
        vim.cmd('silent! only')
        vim.opt.ignorecase = false
        cash.setup({})
        cash.resetCashRegisters()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.v.hlsearch = 1
        return vim.api.nvim_get_current_win()
    end

    -- fills a cash register without leaving the working one behind
    local function store(index, pattern)
        local previous = cash.state.currentIndex
        cash.setCashRegister(index)
        cash.setSearch(pattern)
        cash.setCashRegister(previous)
    end

    -- a window of someone else's making: opened after the highlights are
    -- already up, on a buffer this plugin never had the chance to mark. That is
    -- the shape of every window telescope opens
    ---@return integer window
    local function foreignWindow(content)
        vim.cmd('new')
        vim.api.nvim_buf_set_lines(0, 0, -1, false, content)
        cash.updateHighlights()
        return vim.api.nvim_get_current_win()
    end

    ---@return boolean
    local function isTracked(window)
        return vim.tbl_contains(highlights.trackedWindows(), window)
    end

    ----------------------------------------------------------------------

    h.group('the picker rows')

    do
        local window = fresh()
        cash.setSearch('foo')
        store(2, 'TODO')
        cash.setIncludeInSearch(2, true)
        store(4, '\\(')
        store(9, 'nowhere')

        local rows = picker.rows(cash, window)

        h.check('there is a row for every cash register', #rows == 9, #rows)

        local inOrder = true
        for index = 1, 9 do
            if rows[index].index ~= index then
                inOrder = false
            end
        end
        h.check('in order, empty ones included', inOrder, vim.inspect(rows))

        h.check(
            'the working cash register is the selected row',
            rows[1].selected and not rows[2].selected
        )
        h.check(
            'include-in-search comes across as it stands',
            rows[2].includeInSearch and not rows[9].includeInSearch
        )
        h.check(
            'the row holds the pattern as it was typed',
            rows[2].pattern == 'TODO',
            rows[2].pattern
        )
        h.check(
            'and the prompt can be answered with the number or the pattern',
            rows[2].ordinal == '2 TODO',
            rows[2].ordinal
        )
        h.check(
            'a filled cash register is counted',
            rows[1].count == '2' and rows[2].count == '1',
            rows[1].count .. ' and ' .. rows[2].count
        )
        h.check(
            'a pattern that is not in the buffer counts zero',
            rows[9].count == '0',
            rows[9].count
        )
        h.check(
            'an empty one is not counted at all',
            rows[3].count == '',
            rows[3].count
        )
        h.check(
            'and neither is a pattern vim cannot compile',
            rows[4].count == '',
            rows[4].count
        )
    end

    do
        local window = fresh()
        cash.setSearch('FOO')

        h.check(
            'the count is of the match pattern, so the case flag decides it',
            picker.rows(cash, window)[1].count == '0',
            picker.rows(cash, window)[1].count
        )

        vim.opt.ignorecase = true
        h.check(
            'which means ignorecase moves the answer',
            picker.rows(cash, window)[1].count == '2',
            picker.rows(cash, window)[1].count
        )
        vim.opt.ignorecase = false
    end

    do
        local origin = fresh()
        cash.setSearch('foo')

        -- the buffer the counts are meant to be about is the one the user came
        -- from, and by the time telescope asks, the window in front is one of
        -- its own
        local other = foreignWindow({ 'foo', 'foo', 'foo' })

        h.check(
            'the counts are about the window they are asked for',
            picker.rows(cash, origin)[1].count == '2',
            picker.rows(cash, origin)[1].count
        )
        h.check(
            'and not about whichever window happens to be current',
            picker.rows(cash, other)[1].count == '3'
                and picker.rows(cash)[1].count == '3',
            picker.rows(cash)[1].count
        )

        vim.api.nvim_win_close(other, true)
    end

    ----------------------------------------------------------------------

    h.group('selecting a row')

    do
        local origin = fresh()
        cash.setSearch('foo')
        store(9, 'TODO')

        local other = foreignWindow({ 'nothing to find here' })

        picker.select(cash, 9, origin)

        h.check(
            'selecting makes that cash register the working one',
            cash.state.currentIndex == 9,
            cash.state.currentIndex
        )
        h.check(
            'and the search register follows it',
            vim.fn.getreg('/') == 'TODO',
            vim.fn.getreg('/')
        )
        h.check(
            'the search happens in the window the picker was opened from',
            vim.api.nvim_win_get_cursor(origin)[1] == 3,
            vim.api.nvim_win_get_cursor(origin)[1]
        )
        h.check(
            'and nowhere else',
            vim.api.nvim_win_get_cursor(other)[1] == 1,
            vim.api.nvim_win_get_cursor(other)[1]
        )

        vim.api.nvim_win_close(other, true)
    end

    do
        local origin = fresh()
        store(2, 'TODO')

        local other = foreignWindow(lines)
        vim.api.nvim_win_close(origin, true)

        picker.select(cash, 2, origin)

        h.check(
            'a window that has closed since is searched in no longer',
            cash.state.currentIndex == 2 and vim.fn.getreg('/') == 'TODO',
            cash.state.currentIndex .. ' and ' .. vim.fn.getreg('/')
        )
        h.check(
            'and the search falls back to the window that is left',
            vim.api.nvim_win_get_cursor(other)[1] == 3,
            vim.api.nvim_win_get_cursor(other)[1]
        )
    end

    ----------------------------------------------------------------------

    h.group("the picker's own windows")

    do
        fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        cash.updateHighlights()

        local theirs = foreignWindow({ 'bar', 'foo' })
        vim.wo[theirs].winhighlight = 'Normal:TelescopeResultsNormal'

        h.check(
            'a window nobody has excluded is highlighted like any other',
            h.litCount(theirs) == 1,
            h.litCount(theirs) .. ' lit'
        )

        picker.excludeFromHighlighting(cash, { theirs })

        h.check(
            'excluding it takes away the matches it already had',
            h.litCount(theirs) == 0,
            '[' .. h.litSummary(theirs) .. ']'
        )
        h.check(
            'marks the buffer the way the drawer marks its own',
            vim.b[vim.api.nvim_win_get_buf(theirs)].cashDrawer == true
        )
        h.check(
            'sends the search highlights nowhere',
            vim.wo[theirs].winhighlight:find(
                'Search:CashDrawerNoSearch',
                1,
                true
            ) ~= nil,
            vim.wo[theirs].winhighlight
        )
        h.check(
            'while keeping the winhighlight telescope set for itself',
            vim.wo[theirs].winhighlight:find(
                'Normal:TelescopeResultsNormal',
                1,
                true
            ) ~= nil,
            vim.wo[theirs].winhighlight
        )
        h.check('and stops tracking it', not isTracked(theirs))

        cash.updateHighlights()
        h.check(
            'a later update does not put the matches back',
            h.litCount(theirs) == 0,
            '[' .. h.litSummary(theirs) .. ']'
        )

        vim.api.nvim_win_close(theirs, true)
    end

    fresh()
end
