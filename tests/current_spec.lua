-- Tests for the current match: the one the cursor is sitting on.
--
-- The rule these are about:
--
--     window W has a current-match highlight exactly when v:hlsearch is on and
--     W's cursor is on a match of a cash register that is in the search set
--     and is not the working one
--
-- The working cash register is left out of that because vim already paints its
-- current match itself, in the same CurSearch highlight, from @/. Issue #21 is
-- that it was the only one that got the treatment.
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')

    -- foo and bar on lines of their own and together on one, so that "which
    -- match is the cursor on" has something to be wrong about
    local lines = {
        'foo and bar',
        'bar alone',
        'nothing here',
        'foo alone',
    }

    local function fresh()
        vim.cmd('silent! tabonly')
        vim.cmd('silent! only')
        vim.opt.ignorecase = false
        vim.opt.wrapscan = true
        cash.setup({})
        cash.resetCashRegisters()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.v.hlsearch = 1
        return vim.fn.win_getid()
    end

    -- puts a pattern into a cash register without disturbing which one is
    -- working
    local function store(index, pattern)
        local previous = cash.state.currentIndex
        cash.setCashRegister(index)
        cash.setSearch(pattern)
        cash.setCashRegister(previous)
    end

    -- the anchored pattern of a window's current-match highlight, or nil when
    -- it has none
    ---@return string|nil
    local function currentMatchIn(windowID)
        for _, match in ipairs(vim.fn.getmatches(windowID)) do
            if match.group == 'CurSearch' then
                return match.pattern
            end
        end
        return nil
    end

    ---@return integer|nil
    local function currentMatchPriority(windowID)
        for _, match in ipairs(vim.fn.getmatches(windowID)) do
            if match.group == 'CurSearch' then
                return match.priority
            end
        end
        return nil
    end

    -- moves the cursor and brings the current match up to date, which is what
    -- the SafeState autocmd does in a session with a user in it. Columns are
    -- counted from 0 here, the way nvim_win_set_cursor counts them
    local function at(row, column)
        vim.api.nvim_win_set_cursor(0, { row, column })
        cash.updateCurrentMatch()
    end

    -- where the anchored pattern actually matches, so that a test can tell an
    -- anchor that reads correctly from one that lands where it should
    ---@return integer row 0 when it matches nowhere
    local function whereItMatches(pattern)
        local view = vim.fn.winsaveview()
        local found = vim.fn.search(pattern, 'cnw')
        vim.fn.winrestview(view)
        return found
    end

    ----------------------------------------------------------------------

    h.group('the search set decides')

    do
        local window = fresh()
        cash.setSearch('foo')
        store(2, 'bar')

        at(1, 0)
        h.check(
            'the working cash register gets no current match of its own',
            currentMatchIn(window) == nil,
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )

        at(1, 8)
        h.check(
            'and neither does an excluded one',
            currentMatchIn(window) == nil,
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )

        cash.setIncludeInSearch(2, true)
        at(1, 8)
        h.check(
            'an included cash register gets one under the cursor',
            currentMatchIn(window) == '\\%1l\\%9c\\%(\\Cbar\\)',
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )
        h.check(
            'and it is anchored where the match actually is',
            whereItMatches(currentMatchIn(window) or 'x') == 1,
            'matched line ' .. whereItMatches(currentMatchIn(window) or 'x')
        )

        cash.setIncludeInSearch(2, false)
        cash.updateCurrentMatch()
        h.check(
            'taking it back out of the search set takes the highlight away',
            currentMatchIn(window) == nil,
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('following the cursor')

    do
        local window = fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        cash.setIncludeInSearch(2, true)

        at(1, 8)
        h.check(
            'the cursor on one match',
            currentMatchIn(window) == '\\%1l\\%9c\\%(\\Cbar\\)',
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )

        at(1, 10)
        h.check(
            'moving within that match leaves it where it is',
            currentMatchIn(window) == '\\%1l\\%9c\\%(\\Cbar\\)',
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )

        at(2, 1)
        h.check(
            'moving to another match moves it',
            currentMatchIn(window) == '\\%2l\\%1c\\%(\\Cbar\\)',
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )

        at(3, 0)
        h.check(
            'moving off every match takes it away',
            currentMatchIn(window) == nil,
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )

        at(4, 0)
        h.check(
            'and a match of the working cash register does not bring it back',
            currentMatchIn(window) == nil,
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )

        -- the wiring rather than the rule: everything above drives the update
        -- by hand, because SafeState does not fire in a headless run
        at(3, 0)
        vim.api.nvim_win_set_cursor(0, { 2, 1 })
        vim.api.nvim_exec_autocmds('SafeState', {})
        h.check(
            'SafeState is what keeps it up to date in a real session',
            currentMatchIn(window) == '\\%2l\\%1c\\%(\\Cbar\\)',
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('search highlighting')

    do
        local window = fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        cash.setIncludeInSearch(2, true)
        at(2, 1)

        vim.v.hlsearch = 0
        cash.updateHighlights()
        h.check(
            ':nohlsearch takes the current match with the rest',
            currentMatchIn(window) == nil,
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )

        vim.v.hlsearch = 1
        cash.updateHighlights()
        h.check(
            'and turning it back on brings the current match back',
            currentMatchIn(window) == '\\%2l\\%1c\\%(\\Cbar\\)',
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('priority')

    do
        local window = fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        cash.setIncludeInSearch(2, true)
        at(2, 1)

        h.check(
            "the current match sits above vim's own search highlighting",
            (currentMatchPriority(window) or 0) > 0,
            'priority ' .. tostring(currentMatchPriority(window))
        )

        local registerPriority = nil
        for _, match in ipairs(vim.fn.getmatches(window)) do
            if match.group == 'CashRegister2' then
                registerPriority = match.priority
            end
        end
        h.check(
            "and above the cash register's own match",
            registerPriority ~= nil
                and (currentMatchPriority(window) or 0) > registerPriority,
            'current '
                .. tostring(currentMatchPriority(window))
                .. ', register '
                .. tostring(registerPriority)
        )
    end

    ----------------------------------------------------------------------

    h.group('every window has its own')

    do
        local first = fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        cash.setIncludeInSearch(2, true)

        at(1, 8)
        vim.cmd('split')
        local second = vim.fn.win_getid()
        vim.api.nvim_win_set_cursor(second, { 2, 1 })
        cash.updateHighlights()

        h.check(
            'each window is answered about its own cursor',
            currentMatchIn(first) == '\\%1l\\%9c\\%(\\Cbar\\)'
                and currentMatchIn(second) == '\\%2l\\%1c\\%(\\Cbar\\)',
            'first ['
                .. tostring(currentMatchIn(first))
                .. '] second ['
                .. tostring(currentMatchIn(second))
                .. ']'
        )

        vim.cmd('only')
        cash.updateHighlights()
        h.check(
            'and the one that is left keeps its own',
            currentMatchIn(vim.fn.win_getid()) ~= nil,
            'got [' .. tostring(currentMatchIn(vim.fn.win_getid())) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('patterns the anchor has to survive')

    do
        local window = fresh()
        cash.setSearch('foo')

        -- an anchor written in front of an alternation would bind to its first
        -- branch alone, which is what the \%( \) around the pattern is for
        store(2, 'bar\\|nothing')
        cash.setIncludeInSearch(2, true)
        at(3, 0)
        h.check(
            'an alternation is still anchored as a whole',
            whereItMatches(currentMatchIn(window) or 'x') == 3,
            'pattern ['
                .. tostring(currentMatchIn(window))
                .. '] matched line '
                .. whereItMatches(currentMatchIn(window) or 'x')
        )

        -- the anchor is a byte column, and searchpos answers in byte columns,
        -- so a multibyte character in front of the match must not shift it
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'héllo bar' })
        store(2, 'bar')
        at(1, 7)
        h.check(
            'a match after a multibyte character is anchored where it is',
            currentMatchIn(window) == '\\%1l\\%8c\\%(\\Cbar\\)'
                and whereItMatches(currentMatchIn(window) or 'x') == 1,
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )

        -- vim works the extent out itself, so a match spanning two lines needs
        -- no arithmetic here and the cursor can be on either of them
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
            'first line',
            'second line',
        })
        store(2, 'line\\nsecond')
        at(2, 2)
        h.check(
            'a multi-line match is found from its second line',
            currentMatchIn(window) == '\\%1l\\%7c\\%(\\Cline\\nsecond\\)',
            'got [' .. tostring(currentMatchIn(window)) .. ']'
        )
    end

    ----------------------------------------------------------------------

    -- leave the plugin as the next spec expects to find it
    fresh()
    cash.resetCashRegisters()
end
