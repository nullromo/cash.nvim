-- Tests for the ? chooser and for clearing the highlighting on cursor
-- movement.
--
-- The chooser exists so that "which number is the green one" has an answer on
-- screen rather than in the user's memory. See CONTEXT.md for the vocabulary.

return function(h)
    local cash = require('cash')
    local ui = require('cash.ui')

    local function fresh(opts)
        vim.cmd('silent! tabonly')
        vim.cmd('silent! only')
        vim.opt.ignorecase = false
        cash.setup(opts or {})
        cash.resetCashRegisters()
        vim.api.nvim_buf_set_lines(
            0,
            0,
            -1,
            false,
            { 'foo bar baz', 'foo again' }
        )
        vim.v.hlsearch = 1
        return vim.api.nvim_get_current_win()
    end

    local function store(index, pattern)
        local previous = cash.state.currentIndex
        cash.setCashRegister(index)
        cash.setSearch(pattern)
        cash.setCashRegister(previous)
    end

    -- opens the chooser, hands its lines back, and puts it away again
    local function chooserLines(style)
        local window = ui.openChooser(cash, style)
        local lines = vim.api.nvim_buf_get_lines(
            vim.api.nvim_win_get_buf(window),
            0,
            -1,
            false
        )
        local config = vim.api.nvim_win_get_config(window)
        vim.api.nvim_win_close(window, true)
        return lines, config
    end

    ----------------------------------------------------------------------

    h.group('the chooser')

    do
        fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        store(9, 'TODO')

        local grid = chooserLines('grid')
        h.check(
            'the grid lays the nine out three by three, like a numpad',
            #grid == 3,
            #grid .. ' lines'
        )
        h.check(
            'naming what each cash register holds',
            grid[1]:find('foo', 1, true) ~= nil
                and grid[1]:find('bar', 1, true) ~= nil
                and grid[3]:find('TODO', 1, true) ~= nil,
            vim.inspect(grid)
        )
        h.check(
            'and marking the empty ones without hiding their numbers',
            grid[2]:find('4', 1, true) ~= nil
                and grid[2]:find('·', 1, true) ~= nil,
            vim.inspect(grid)
        )

        local strip = chooserLines('strip')
        h.check(
            'the strip is one line of numbers',
            #strip == 1 and strip[1]:find('9', 1, true) ~= nil,
            vim.inspect(strip)
        )
        h.check(
            'with no patterns on it',
            strip[1]:find('foo', 1, true) == nil,
            vim.inspect(strip)
        )

        -- a column is only so wide, and a pattern is whatever the user typed
        store(5, 'a_very_long_pattern_indeed')
        local truncated = chooserLines('grid')
        h.check(
            'a pattern too long for its column is cut short',
            truncated[2]:find('~', 1, true) ~= nil and #truncated[2] < 60,
            vim.inspect(truncated)
        )
    end

    ----------------------------------------------------------------------

    h.group('where the chooser appears')

    do
        fresh()

        local placements = {}
        for _, position in ipairs(require('cash.constants').positions) do
            cash.opts.chooser.position = position
            local _, config = chooserLines('strip')
            placements[position] = { config.row, config.col }
        end
        cash.opts.chooser.position = 'center'

        h.check(
            'top-left goes to the corner',
            placements['top-left'][1] == 0 and placements['top-left'][2] == 0,
            vim.inspect(placements['top-left'])
        )
        h.check(
            'bottom is lower than top, and centered across',
            placements['bottom'][1] > placements['top'][1]
                and placements['bottom'][2] == placements['top'][2],
            vim.inspect(placements)
        )
        h.check(
            'right is further across than left, on the same row',
            placements['right'][2] > placements['left'][2]
                and placements['right'][1] == placements['left'][1],
            vim.inspect(placements)
        )
        h.check(
            'and center is between them both',
            placements['center'][1] > placements['top'][1]
                and placements['center'][1] < placements['bottom'][1]
                and placements['center'][2] > placements['left'][2]
                and placements['center'][2] < placements['right'][2],
            vim.inspect(placements)
        )

        h.check(
            'an unknown position is rejected at setup',
            not pcall(cash.setup, { chooser = { position = 'middle' } })
        )
        h.check(
            'and an unknown style too',
            not pcall(cash.setup, { chooser = { style = 'fancy' } })
        )
    end

    ----------------------------------------------------------------------

    h.group('the chooser has its own border')

    do
        -- two popups, two borders. Sharing one would mean the drawer and the
        -- chooser could never be told apart at a glance
        fresh({
            chooser = { border = 'double' },
            drawer = { border = 'single' },
        })

        local window = ui.openChooser(cash, 'strip')
        local chooserBorder = vim.api.nvim_win_get_config(window).border[1]
        vim.api.nvim_win_close(window, true)

        ui.open(cash)
        local drawerBorder = vim.api.nvim_win_get_config(
            vim.api.nvim_get_current_win()
        ).border[1]
        ui.close()

        h.check(
            'the chooser uses chooser.border',
            chooserBorder == '╔',
            'got [' .. tostring(chooserBorder) .. ']'
        )
        h.check(
            'and the drawer keeps drawer.border',
            drawerBorder == '┌',
            'got [' .. tostring(drawerBorder) .. ']'
        )

        h.check(
            'a border of the wrong type is rejected',
            not pcall(cash.setup, { chooser = { border = 7 } })
        )

        fresh()
        h.check(
            'and it defaults to rounded like the drawer',
            cash.opts.chooser.border == 'rounded',
            'got [' .. tostring(cash.opts.chooser.border) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('clearing the highlighting when the cursor moves')

    do
        local window = fresh({ autoNoHighlight = true })
        cash.setSearch('foo')
        store(2, 'bar')
        cash.showHighlighting()
        h.check(
            'a cash register is lit to begin with',
            #vim.fn.getmatches(window) == 1,
            #vim.fn.getmatches(window) .. ' matches'
        )

        -- the search that turned the highlighting on moves the cursor itself,
        -- and that move must not count -- otherwise the highlighting is gone
        -- in the same breath as it arrived
        cash.expectSearchMove()
        vim.api.nvim_exec_autocmds('CursorMoved', {})
        vim.wait(100, function()
            return vim.v.hlsearch == 0
        end)
        h.check(
            "the search's own cursor movement is not counted",
            vim.v.hlsearch == 1,
            'v:hlsearch=' .. vim.v.hlsearch
        )

        vim.api.nvim_exec_autocmds('CursorMoved', {})
        vim.wait(200, function()
            return vim.v.hlsearch == 0
        end)
        h.check(
            'but the next one clears everything',
            vim.v.hlsearch == 0 and #vim.fn.getmatches(window) == 0,
            'v:hlsearch='
                .. vim.v.hlsearch
                .. ' '
                .. #vim.fn.getmatches(window)
                .. ' matches'
        )

        -- and it stays off until something searches again
        cash.showHighlighting()
        vim.wait(100, function()
            return false
        end)
        h.check(
            'searching brings it back',
            vim.v.hlsearch == 1,
            'v:hlsearch=' .. vim.v.hlsearch
        )
    end

    ----------------------------------------------------------------------

    -- lets everything scheduled so far happen
    local function settle()
        vim.wait(100, function()
            return false
        end)
    end

    -- highlighting on, and nothing expecting to move the cursor.
    --
    -- Storing a pattern searches for it, and a search says so in advance, so
    -- the setup each test below shares leaves an expectation standing that
    -- would otherwise be spent on that test's first movement -- which is the
    -- one movement the test is about
    local function lit()
        settle()
        vim.api.nvim_exec_autocmds('CursorMoved', {})
        settle()
        cash.showHighlighting()
        settle()
    end

    h.group('a search outruns the clear it was racing')

    -- The clear cannot happen the moment the movement is seen, because
    -- v:hlsearch does not survive being assigned from inside an autocmd. It
    -- waits for a schedule, and in that gap more keys get dealt with. A search
    -- among them turns the highlighting back on and moves the cursor onto a
    -- match -- and the clear, still on its way, used to land on top of it and
    -- leave the cursor sitting on a match with nothing marking it. Pressing n
    -- with any other movement in front of it flickered for exactly this reason
    do
        local window = fresh({ autoNoHighlight = true })
        cash.setSearch('foo')
        store(2, 'bar')
        lit()

        -- the user moves the cursor: the clear is now on its way
        vim.api.nvim_exec_autocmds('CursorMoved', {})

        -- and searches before it arrives
        cash.expectSearchMove()
        vim.api.nvim_exec_autocmds('CursorMoved', {})

        vim.wait(100, function()
            return vim.v.hlsearch == 0
        end)
        h.check(
            'the search has the last word, not the clear',
            vim.v.hlsearch == 1 and #vim.fn.getmatches(window) == 1,
            'v:hlsearch='
                .. vim.v.hlsearch
                .. ' '
                .. #vim.fn.getmatches(window)
                .. ' matches'
        )

        -- and the next ordinary movement still clears, so nothing has been
        -- made permanent by outrunning one clear
        vim.api.nvim_exec_autocmds('CursorMoved', {})
        vim.wait(200, function()
            return vim.v.hlsearch == 0
        end)
        h.check(
            'and the movement after it clears as usual',
            vim.v.hlsearch == 0 and #vim.fn.getmatches(window) == 0,
            'v:hlsearch='
                .. vim.v.hlsearch
                .. ' '
                .. #vim.fn.getmatches(window)
                .. ' matches'
        )
    end

    ----------------------------------------------------------------------

    h.group('a search that never moves is not held against the next move')

    -- Not every search moves the cursor. One that finds nothing leaves it
    -- where it was, and so does * with disableStarPoundJump, which is the
    -- default. The expectation would otherwise sit there waiting, and be spent
    -- on whatever the user did next -- so the move that should have cleared
    -- the highlighting would be the one move that did not
    do
        local window = fresh({ autoNoHighlight = true })
        cash.setSearch('foo')
        store(2, 'bar')
        lit()

        -- a search is announced, and finds nothing: no CursorMoved follows
        cash.expectSearchMove()

        -- vim goes back to waiting for a key, which is where the expectation
        -- is given up
        vim.api.nvim_exec_autocmds('SafeState', {})

        -- now the user really does move
        vim.api.nvim_exec_autocmds('CursorMoved', {})
        vim.wait(200, function()
            return vim.v.hlsearch == 0
        end)
        h.check(
            'the movement after a search that stood still still clears',
            vim.v.hlsearch == 0 and #vim.fn.getmatches(window) == 0,
            'v:hlsearch='
                .. vim.v.hlsearch
                .. ' '
                .. #vim.fn.getmatches(window)
                .. ' matches'
        )
    end

    ----------------------------------------------------------------------

    h.group('* keeps the highlighting it just turned on')

    -- vim's own * runs the moment the mapping hands the key back, and it moves
    -- the cursor before the rest of the mapping gets to say a word about it.
    -- Said only afterwards, the expectation arrives too late and * clears the
    -- very highlighting it had just asked for
    do
        local window = fresh({ autoNoHighlight = true })
        cash.setSearch('foo')
        store(2, 'bar')
        lit()

        -- vim's * has moved the cursor already, and this is that movement
        vim.api.nvim_exec_autocmds('CursorMoved', {})

        -- and this is the mapping, which has not run yet
        local mapping = vim.fn.maparg('*', 'n', false, true)
        h.check('* is mapped', mapping.callback ~= nil)
        if mapping.callback ~= nil then
            mapping.callback()
        end

        vim.wait(150, function()
            return vim.v.hlsearch == 0
        end)
        h.check(
            'pressing * does not clear what pressing * lit up',
            vim.v.hlsearch == 1 and #vim.fn.getmatches(window) == 1,
            'v:hlsearch='
                .. vim.v.hlsearch
                .. ' '
                .. #vim.fn.getmatches(window)
                .. ' matches'
        )
    end

    ----------------------------------------------------------------------

    h.group(':Cash autohide')

    do
        fresh({ autoNoHighlight = false })

        vim.cmd('Cash autohide on')
        h.check(':Cash autohide on switches it on', cash.opts.autoNoHighlight)

        vim.cmd('Cash autohide off')
        h.check(
            ':Cash autohide off switches it off',
            not cash.opts.autoNoHighlight
        )

        vim.cmd('Cash autohide toggle')
        h.check(':Cash autohide toggle flips it', cash.opts.autoNoHighlight)

        vim.cmd('Cash autohide')
        h.check(
            'and with no argument it flips it too',
            not cash.opts.autoNoHighlight
        )

        h.check(
            'a word it does not understand is refused, not thrown',
            pcall(vim.cmd, 'Cash autohide sideways')
        )
        h.check('and changes nothing', not cash.opts.autoNoHighlight)
    end

    -- leave the highlighting alone for whatever runs next
    fresh()
    vim.v.hlsearch = 1
end
