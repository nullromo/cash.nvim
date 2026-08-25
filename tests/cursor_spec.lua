-- Tests for the cash register under the cursor: `??`, :Cash here and
-- cash.setCashRegisterUnderCursor().
--
-- The rules these are about:
--
--     the working cash register becomes the one whose match covers the
--     cursor, and the cursor stays exactly where it was -- it is already on a
--     match, so there is nothing to search for
--
--     where more than one cash register matches under the cursor, asking
--     again walks through them. The search starts after the working cash
--     register and considers it last, so "nothing matches here" and "you are
--     already in the only one that does" are different answers
--
--     a cash register only counts where vim would really be painting it. An
--     empty one, one holding a pattern vim cannot compile, one whose case
--     flag rules the text out, and one whose pattern matches without covering
--     anything are all passed over
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')
    local ui = require('cash.ui')

    -- line 3 is for the case flags, line 4 is where a short pattern sits
    -- inside a longer one -- which is the overlap the cycling is about -- and
    -- line 5 is for patterns that match without covering anything
    local lines = {
        'foo bar baz',
        'bar and foo again',
        'FOO shouting',
        'foobar joined',
        '   indented',
    }

    local function fresh()
        vim.cmd('silent! tabonly')
        vim.cmd('silent! only')
        vim.opt.ignorecase = false
        cash.setup({})
        cash.resetCashRegisters()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.v.hlsearch = 1
    end

    -- fills a cash register without leaving the working one behind. Selecting
    -- a cash register searches for its pattern, so the cursor is only put
    -- where a test wants it after every register has been filled
    local function store(index, pattern)
        local previous = cash.state.currentIndex
        cash.setCashRegister(index)
        cash.setSearch(pattern)
        cash.setCashRegister(previous)
    end

    -- columns counted from 1 here, the way searchpos and the buffer lines
    -- above read
    local function at(row, column)
        vim.api.nvim_win_set_cursor(0, { row, column - 1 })
    end

    local function working()
        return cash.state.currentIndex
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
        vim.api.nvim_win_close(window, true)
        return lines
    end

    -- runs the given function with the notifications it makes collected
    -- rather than printed
    local function notifications(action)
        local said = {}
        local realNotify = vim.notify
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.notify = function(message)
            table.insert(said, message)
        end
        local ok, err = pcall(action)
        vim.notify = realNotify
        assert(ok, err)
        return table.concat(said, '\n')
    end

    ----------------------------------------------------------------------

    h.group('switching to the cash register under the cursor')

    do
        fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        at(1, 5)

        cash.setCashRegisterUnderCursor()

        h.check(
            'the working cash register becomes the one matching there',
            working() == 2,
            'working in ' .. working()
        )
        h.check(
            'and the search register follows it',
            vim.fn.getreg('/') == 'bar',
            'got [' .. vim.fn.getreg('/') .. ']'
        )
        h.check(
            'the cursor stays on the match it was already on',
            vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 4 }),
            vim.inspect(vim.api.nvim_win_get_cursor(0))
        )
    end

    do
        fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        at(1, 4)

        local said = notifications(cash.setCashRegisterUnderCursor)

        h.check(
            'text no cash register matches leaves the working one alone',
            working() == 1,
            'working in ' .. working()
        )
        h.check(
            'and says that nothing matches there',
            said:find('no cash register', 1, true) ~= nil,
            'said [' .. said .. ']'
        )
    end

    do
        fresh()
        cash.setSearch('foo')
        at(1, 2)

        local said = notifications(cash.setCashRegisterUnderCursor)

        h.check(
            'the working cash register matching there is left as it is',
            working() == 1,
            'working in ' .. working()
        )
        h.check(
            'and is told apart from nothing matching at all',
            said:find('already working', 1, true) ~= nil,
            'said [' .. said .. ']'
        )
    end

    do
        fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        at(1, 5)
        vim.v.hlsearch = 0

        cash.setCashRegisterUnderCursor()

        h.check(
            'the switch brings the highlighting back, since nothing else '
                .. 'would',
            vim.v.hlsearch == 1
        )
    end

    ----------------------------------------------------------------------

    h.group('more than one cash register matching the same text')

    do
        fresh()
        cash.setSearch('zzz')
        store(2, 'foobar')
        store(3, 'bar')
        at(4, 4)

        cash.setCashRegisterUnderCursor()
        local first = working()
        cash.setCashRegisterUnderCursor()
        local second = working()
        cash.setCashRegisterUnderCursor()
        local third = working()

        h.check(
            'the first one after the working cash register wins',
            first == 2,
            'working in ' .. first
        )
        h.check(
            'asking again moves on to the next one matching there',
            second == 3,
            'working in ' .. second
        )
        h.check(
            'and the walk wraps round rather than stopping',
            third == 2,
            'working in ' .. third
        )
    end

    ----------------------------------------------------------------------

    h.group('cash registers that are not painting anything there')

    do
        fresh()
        store(2, '\\(')
        store(3, 'foo')
        at(1, 1)

        h.check(
            'a pattern vim cannot compile does not throw',
            pcall(cash.setCashRegisterUnderCursor)
        )
        h.check(
            'it is passed over for one that can be matched',
            working() == 3,
            'working in ' .. working()
        )
    end

    do
        fresh()
        store(2, 'foo')
        store(3, '\\Cfoo')
        at(3, 1)

        cash.setCashRegisterUnderCursor()
        h.check(
            'with ignorecase off, FOO is not a match for foo',
            working() == 1,
            'working in ' .. working()
        )

        vim.opt.ignorecase = true
        cash.setCashRegisterUnderCursor()
        h.check(
            'with ignorecase on, it is',
            working() == 2,
            'working in ' .. working()
        )

        cash.setCashRegisterUnderCursor()
        h.check(
            'and a \\C in the pattern keeps that cash register out of it',
            working() == 2,
            'working in ' .. working()
        )
        vim.opt.ignorecase = false
    end

    do
        fresh()
        store(2, '^\\s*')
        at(1, 3)

        cash.setCashRegisterUnderCursor()
        h.check(
            'a pattern that matches without covering anything is not under '
                .. 'the cursor',
            working() == 1,
            'working in ' .. working()
        )

        at(5, 2)
        cash.setCashRegisterUnderCursor()
        h.check(
            'the same pattern counts where it does cover the cursor',
            working() == 2,
            'working in ' .. working()
        )
    end

    do
        fresh()
        store(2, 'baz\\nbar')
        at(2, 2)

        cash.setCashRegisterUnderCursor()
        h.check(
            'a multi-line match counts on the lines it carries on to',
            working() == 2,
            'working in ' .. working()
        )
    end

    ----------------------------------------------------------------------

    h.group('the chooser marking the cash register under the cursor')

    do
        fresh()
        cash.setSearch('foo')
        store(2, 'bar')

        at(1, 4)
        local unmarked = chooserLines('grid')
        at(1, 5)
        local marked = chooserLines('grid')

        h.check(
            'the cash register under the cursor gets a ? after its number',
            marked[1]:find('2?', 1, true) ~= nil,
            vim.inspect(marked)
        )
        h.check(
            'and no other cash register does',
            marked[1]:find('1?', 1, true) == nil,
            vim.inspect(marked)
        )
        h.check(
            'nothing is marked where nothing matches',
            unmarked[1]:find('?', 1, true) == nil,
            vim.inspect(unmarked)
        )
        h.check(
            'the mark takes the space the number already had after it',
            vim.fn.strdisplaywidth(marked[1])
                == vim.fn.strdisplaywidth(unmarked[1]),
            vim.fn.strdisplaywidth(marked[1])
                .. ' against '
                .. vim.fn.strdisplaywidth(unmarked[1])
        )

        at(1, 5)
        h.check(
            'the strip marks it too',
            chooserLines('strip')[1]:find('2?', 1, true) ~= nil,
            vim.inspect(chooserLines('strip'))
        )

        at(1, 2)
        h.check(
            'the working cash register is marked when it is the only one '
                .. 'matching there',
            chooserLines('grid')[1]:find('1?', 1, true) ~= nil,
            vim.inspect(chooserLines('grid'))
        )
    end

    ----------------------------------------------------------------------

    h.group('the ways of asking for it')

    do
        fresh()
        cash.setSearch('foo')
        store(2, 'bar')
        at(1, 5)

        -- queued rather than pressed, because getchar reads the typeahead and
        -- blocks the event loop until there is something in it
        vim.api.nvim_feedkeys('?', 'n', false)
        local choice = ui.chooseRegister(cash)

        h.check(
            'a second ? is the chooser being asked for the one under the '
                .. 'cursor',
            choice == 'under-cursor',
            'got [' .. tostring(choice) .. ']'
        )

        vim.cmd('Cash here')
        h.check(
            ':Cash here switches to it',
            working() == 2,
            'working in ' .. working()
        )
    end
end
