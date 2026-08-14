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
            cash.opts.prompt.position = position
            local _, config = chooserLines('strip')
            placements[position] = { config.row, config.col }
        end
        cash.opts.prompt.position = 'center'

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
            not pcall(cash.setup, { prompt = { position = 'middle' } })
        )
        h.check(
            'and an unknown style too',
            not pcall(cash.setup, { prompt = { style = 'fancy' } })
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
