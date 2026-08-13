-- Tests for the search set and for n/N moving between the matches of more
-- than one cash register.
--
-- The rule these are about:
--
--     n and N move between the matches of every cash register in the search
--     set, and the search set is the working cash register plus every register
--     with includeInSearch switched on
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')
    local jump = require('cash.jump')

    -- five lines holding foo twice, bar twice and baz once, so that "whichever
    -- is closer" has something to be wrong about
    local lines = {
        'local foo = 1',
        'local bar = 2',
        'local baz = 3',
        'print(foo)',
        'print(bar)',
    }

    local function fresh(bufferLines)
        vim.cmd('silent! tabonly')
        vim.cmd('silent! only')
        vim.opt.ignorecase = false
        vim.opt.wrapscan = true
        cash.setup({})
        cash.resetCashRegisters()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, bufferLines or lines)
        vim.v.hlsearch = 1
        vim.v.searchforward = 1
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        return vim.fn.win_getid()
    end

    local function line()
        return vim.api.nvim_win_get_cursor(0)[1]
    end

    local function at(row, column)
        vim.api.nvim_win_set_cursor(0, { row, column })
    end

    local function searchSet()
        return jump.searchSet(cash.state.cashRegisters, cash.state.currentIndex)
    end

    -- puts a pattern into a cash register without disturbing which one is
    -- working, the way the drawer will
    local function store(index, pattern)
        local previous = cash.state.currentIndex
        cash.setCashRegister(index)
        cash.setSearch(pattern)
        cash.setCashRegister(previous)
    end

    ----------------------------------------------------------------------

    h.group('the search set')

    do
        fresh()
        h.check(
            'starts as the working cash register on its own',
            vim.deep_equal(searchSet(), { 1 }),
            vim.inspect(searchSet())
        )

        cash.setIncludeInSearch(3, true)
        h.check(
            'including a cash register adds it',
            vim.deep_equal(searchSet(), { 1, 3 }),
            vim.inspect(searchSet())
        )

        -- the working cash register is in the set whatever its own switch
        -- says: you have just searched for its pattern, so n has to find it
        cash.setIncludeInSearch(1, false)
        h.check(
            'the working cash register cannot switch itself out',
            vim.deep_equal(searchSet(), { 1, 3 }),
            vim.inspect(searchSet())
        )

        cash.setCashRegister(5)
        h.check(
            'but it drops out once it stops being the working one',
            vim.deep_equal(searchSet(), { 3, 5 }),
            vim.inspect(searchSet())
        )

        cash.setCashRegister(1)
        cash.setIncludeInSearch(3, false)
        h.check(
            'excluding removes it again',
            vim.deep_equal(searchSet(), { 1 }),
            vim.inspect(searchSet())
        )
    end

    ----------------------------------------------------------------------

    h.group('what actually gets searched')

    do
        fresh()
        cash.setSearch('foo')
        cash.setIncludeInSearch(2, true)
        h.check(
            'an empty cash register is not searched',
            #jump.searchablePatterns(cash.state.cashRegisters, 1) == 1
        )

        store(2, '\\(')
        h.check(
            'nor is one holding a pattern vim cannot compile',
            #jump.searchablePatterns(cash.state.cashRegisters, 1) == 1
        )

        store(2, 'bar')
        h.check(
            'a usable one joins in',
            #jump.searchablePatterns(cash.state.cashRegisters, 1) == 2
        )
    end

    ----------------------------------------------------------------------

    h.group('jumping between cash registers')

    do
        fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        cash.setIncludeInSearch(2, true)

        at(1, 0)
        jump.go(cash, true)
        h.check('n finds foo on line 1', line() == 1, 'landed on ' .. line())

        jump.go(cash, true)
        h.check(
            'then bar on line 2, because it is closer than the next foo',
            line() == 2,
            'landed on ' .. line()
        )

        jump.go(cash, true)
        h.check(
            'skipping baz on line 3, which is in no cash register',
            line() == 4,
            'landed on ' .. line()
        )

        jump.go(cash, true)
        h.check('then bar on line 5', line() == 5, 'landed on ' .. line())

        jump.go(cash, true)
        h.check(
            'and wraps round to line 1',
            line() == 1,
            'landed on ' .. line()
        )

        -- N reverses the direction of the last search rather than always
        -- going backwards, which is what vim's own N does
        jump.go(cash, false)
        h.check(
            'N from the top wraps to the last match',
            line() == 5,
            'landed on ' .. line()
        )

        jump.go(cash, false)
        h.check('and keeps going back', line() == 4, 'landed on ' .. line())
    end

    ----------------------------------------------------------------------

    h.group('mixed case flags')

    do
        -- the case that rules out joining the cash registers into one pattern
        -- with \|: \c and \C apply to the whole pattern wherever they are
        -- written, so \%(\cfoo\)\|\%(\CBAR\) matches a lowercase bar
        fresh({ 'FOO', 'foo', 'BAR', 'bar' })
        cash.setSearch('\\cfoo')
        store(2, '\\CBAR')
        cash.setIncludeInSearch(2, true)

        local visited = {}
        at(1, 0)
        for _ = 1, 6 do
            jump.go(cash, true)
            table.insert(visited, line())
        end

        h.check(
            'a case-insensitive register does not infect a case-sensitive one',
            not vim.tbl_contains(visited, 4),
            'visited lines ' .. table.concat(visited, ', ')
        )
        h.check(
            'and both registers are still visited',
            vim.tbl_contains(visited, 2) and vim.tbl_contains(visited, 3),
            'visited lines ' .. table.concat(visited, ', ')
        )
    end

    ----------------------------------------------------------------------

    h.group('wrapscan')

    do
        fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        cash.setIncludeInSearch(2, true)

        vim.opt.wrapscan = false
        at(5, 6)
        jump.go(cash, true)
        h.check(
            'with wrapscan off, n stays put at the last match',
            line() == 5,
            'landed on ' .. line()
        )

        vim.opt.wrapscan = true
        jump.go(cash, true)
        h.check(
            'with it back on, the same press wraps',
            line() == 1,
            'landed on ' .. line()
        )
    end

    ----------------------------------------------------------------------

    h.group('the native fast path')

    do
        fresh()
        cash.setSearch('foo')
        vim.fn.setreg('/', 'foo')

        -- with one cash register in the search set the mapping hands back to
        -- vim, so this is really a check that it did not try to do the work
        -- itself and land somewhere else
        at(1, 0)
        jump.go(cash, true)
        h.check(
            'n on its own goes where vim would send it',
            line() == 1,
            'landed on ' .. line()
        )

        jump.go(cash, true)
        h.check('and on to the next foo', line() == 4, 'landed on ' .. line())

        jump.go(cash, true)
        h.check('and wraps like vim', line() == 1, 'landed on ' .. line())

        -- an empty search set must not throw; vim complains and that is all
        cash.resetCashRegisters()
        vim.fn.setreg('/', '')
        h.check(
            'an empty search set does not throw',
            pcall(jump.go, cash, true)
        )
    end

    ----------------------------------------------------------------------

    h.group('nohlsearch clears every cash register')

    do
        local window = fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        cash.setCashRegister(3)
        h.check(
            'two cash registers are lit to begin with',
            #vim.fn.getmatches(window) == 2,
            #vim.fn.getmatches(window) .. ' matches'
        )

        -- vim only ever applied :nohlsearch to the working cash register,
        -- since the other eight are matches rather than hlsearch. Following
        -- v:hlsearch is what makes it mean all nine
        vim.cmd('nohlsearch')
        cash.updateHighlights()
        h.check(
            'nohlsearch takes all of them away',
            #vim.fn.getmatches(window) == 0,
            #vim.fn.getmatches(window) .. ' matches'
        )

        vim.v.hlsearch = 1
        cash.updateHighlights()
        h.check(
            'and turning search highlighting back on restores them',
            #vim.fn.getmatches(window) == 2,
            #vim.fn.getmatches(window) .. ' matches'
        )

        -- the reconcile itself is wired to SafeState, which does not fire in
        -- a headless run, so the checks above drive updateHighlights directly.
        -- This is the part of that wiring a test can still see
        local subscribed = false
        for _, autocmd in
            ipairs(vim.api.nvim_get_autocmds({ group = 'CashNvim' }))
        do
            if autocmd.event == 'SafeState' then
                subscribed = true
            end
        end
        h.check('and something is watching v:hlsearch for changes', subscribed)
    end

    -- leave search highlighting on, so that a spec running after this one
    -- does not find every cash register mysteriously dark
    vim.v.hlsearch = 1
    vim.opt.wrapscan = true
end
