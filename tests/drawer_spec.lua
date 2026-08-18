-- Tests for the cash drawer.
--
-- The rule these are about:
--
--     the drawer's buffer holds nothing but the nine search patterns, one per
--     line, and everything else on screen is an extmark
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')
    local ui = require('cash.ui')

    local function fresh(opts)
        ui.close()
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
            { 'foo bar baz', 'foo again', 'bar again' }
        )
        vim.v.hlsearch = 1
        return vim.api.nvim_get_current_win()
    end

    local function press(keys)
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes(keys, true, false, true),
            'x',
            false
        )
    end

    -- an edit, followed by the preview that would normally follow it.
    --
    -- Two things about feedkeys make this necessary. TextChanged is checked on
    -- the main loop, which a headless run driving feedkeys with 'x' never
    -- comes round to, so the preview autocmd never fires by itself. And 'x'
    -- leaves insert mode when the typeahead runs out, so an <Esc> sent as a
    -- separate call arrives in normal mode -- where it is mapped to apply and
    -- close. Keys that end in insert mode therefore carry their own <Esc>.
    --
    -- The preview has been checked separately in a real terminal, where the
    -- autocmd fires on its own
    local function edit(keys)
        press(keys)
        vim.api.nvim_exec_autocmds('TextChanged', {
            buffer = vim.api.nvim_get_current_buf(),
        })
    end

    local function drawerLines()
        return vim.api.nvim_buf_get_lines(0, 0, -1, false)
    end

    local function patternsOf()
        local patterns = {}
        for index = 1, 9 do
            table.insert(patterns, cash.state.cashRegisters[index].pattern)
        end
        return patterns
    end

    ----------------------------------------------------------------------

    h.group('opening the drawer')

    do
        local origin = fresh()
        cash.setSearch('foo')
        cash.setCashRegister(2)
        cash.setSearch('bar')
        cash.setCashRegister(1)

        vim.cmd('Cash')
        h.check('the drawer opens', ui.isOpen())

        h.check(
            'its buffer holds nothing but the nine patterns',
            vim.deep_equal(drawerLines(), patternsOf()),
            vim.inspect(drawerLines())
        )
        h.check(
            'which is nine lines, however few are filled in',
            #drawerLines() == 9,
            #drawerLines() .. ' lines'
        )

        -- the header, legend and key hints are extmarks rather than text, so
        -- there is nothing below cash register 9 for the cursor to reach
        press('G')
        h.check(
            'G lands on cash register 9, not on a key hint',
            vim.api.nvim_win_get_cursor(0)[1] == 9,
            'landed on ' .. vim.api.nvim_win_get_cursor(0)[1]
        )

        -- the drawer buffer holds the patterns as literal text, so matching
        -- them here would paint the drawer in the colors it is explaining
        local drawerWindow = vim.api.nvim_get_current_win()
        cash.updateHighlights()
        h.check(
            'the drawer window gets no cash matches of its own',
            #vim.fn.getmatches(drawerWindow) == 0,
            #vim.fn.getmatches(drawerWindow) .. ' matches'
        )
        h.check(
            'while the window behind it keeps them',
            #vim.fn.getmatches(origin) == 1,
            #vim.fn.getmatches(origin) .. ' matches'
        )

        -- the drawer's buffer holds the patterns as literal text, so vim's own
        -- hlsearch matches them here. That is not the ledger, and leaving the
        -- window out of it does not help: it is vim highlighting @/ wherever
        -- it appears. Left alone, a pattern wore CurSearch as soon as the
        -- cursor reached its row, and a pattern occurring inside another one
        -- lit up part of it
        local winhighlight = vim.wo[drawerWindow].winhighlight
        h.check(
            'search highlighting is turned off inside the drawer',
            winhighlight:find('Search:CashDrawerNoSearch', 1, true) ~= nil
                and winhighlight:find('CurSearch:', 1, true) ~= nil,
            'winhighlight is [' .. winhighlight .. ']'
        )
        h.check(
            'and the group it redirects to has no attributes of its own',
            vim.tbl_isempty(
                vim.api.nvim_get_hl(0, { name = 'CashDrawerNoSearch' })
            ),
            vim.inspect(vim.api.nvim_get_hl(0, { name = 'CashDrawerNoSearch' }))
        )

        ui.close()
        h.check('and it closes', not ui.isOpen())
    end

    ----------------------------------------------------------------------

    h.group('keys inside the drawer')

    do
        fresh()
        cash.setSearch('foo')
        cash.setCashRegister(2)
        cash.setSearch('bar')
        cash.setCashRegister(1)
        vim.cmd('Cash')

        press('3G')
        press('<Space>')
        h.check(
            'space switches include-in-search on for the row under the cursor',
            cash.state.cashRegisters[3].includeInSearch
        )

        press('<Space>')
        h.check(
            'and off again',
            not cash.state.cashRegisters[3].includeInSearch
        )

        -- the selected cash register is in the search set whatever its switch
        -- says, so the drawer says so rather than appearing to ignore the key
        press('1G')
        press('<Space>')
        h.check(
            'space on the selected cash register leaves it alone',
            not cash.state.cashRegisters[1].includeInSearch
        )

        -- swapping moves the pattern and the switch but not the color, which
        -- is what makes it a way to recolor a search
        press('1G')
        press(']')
        h.check(
            '] swaps the cash register with the one below it',
            cash.state.cashRegisters[1].pattern == 'bar'
                and cash.state.cashRegisters[2].pattern == 'foo',
            vim.inspect(patternsOf())
        )
        h.check(
            'and the selection travels with its contents',
            cash.state.currentIndex == 2,
            'selected ' .. cash.state.currentIndex
        )

        press('[')
        h.check(
            '[ puts it back',
            cash.state.cashRegisters[1].pattern == 'foo'
                and cash.state.currentIndex == 1,
            vim.inspect(patternsOf())
        )

        press('5G')
        press('<CR>')
        h.check(
            'enter selects the cash register under the cursor',
            cash.state.currentIndex == 5,
            'selected ' .. cash.state.currentIndex
        )
        h.check('and closes the drawer', not ui.isOpen())

        vim.cmd('Cash')
        press('q')
        h.check('q closes it too', not ui.isOpen())
    end

    ----------------------------------------------------------------------

    h.group('editing patterns')

    do
        local origin = fresh()
        cash.setSearch('foo')
        vim.cmd('Cash')

        -- the line is nothing but the pattern, so ordinary vim editing does
        -- the right thing without a single mapping
        edit('1Gcwbar<Esc>')
        h.check(
            'editing a line edits the cash register',
            cash.state.cashRegisters[1].pattern == 'bar',
            'got [' .. cash.state.cashRegisters[1].pattern .. ']'
        )

        edit('2GAbaz<Esc>')
        h.check(
            'and typing into an empty row fills one in',
            cash.state.cashRegisters[2].pattern == 'baz',
            'got [' .. cash.state.cashRegisters[2].pattern .. ']'
        )

        -- the preview: the buffers behind the drawer follow along as the
        -- pattern is typed, which is the reason to edit here and not at a
        -- prompt
        h.check(
            'the highlights behind the drawer keep up',
            #vim.fn.getmatches(origin) == 1,
            #vim.fn.getmatches(origin) .. ' matches'
        )

        -- D on a line that holds only the pattern already clears the register,
        -- which is why it is not mapped
        -- 0 because nvim defaults to nostartofline, so 1G keeps whatever
        -- column the last edit left the cursor in
        edit('1G0D')
        h.check(
            'D clears a cash register with no mapping at all',
            cash.state.cashRegisters[1].pattern == '',
            'got [' .. cash.state.cashRegisters[1].pattern .. ']'
        )

        press('q')
        h.check('the drawer closes', not ui.isOpen())
        h.check(
            'and the search register agrees with the selected cash register',
            vim.fn.getreg('/') == '',
            'got [' .. vim.fn.getreg('/') .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('there are always nine rows')

    do
        fresh()
        cash.setSearch('one')
        cash.setCashRegister(2)
        cash.setSearch('two')
        cash.setCashRegister(1)
        vim.cmd('Cash')

        -- dd would leave eight rows, so it empties one instead
        edit('1Gdd')
        h.check(
            'dd empties a cash register rather than removing the row',
            #vim.api.nvim_buf_get_lines(0, 0, -1, false) == 9
                and cash.state.cashRegisters[1].pattern == ''
                and cash.state.cashRegisters[2].pattern == 'two',
            vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false))
        )

        edit('o')
        edit('O')
        h.check(
            'o and O cannot add one',
            #vim.api.nvim_buf_get_lines(0, 0, -1, false) == 9,
            #vim.api.nvim_buf_get_lines(0, 0, -1, false) .. ' lines'
        )

        -- the backstop, for everything that was not thought of
        edit('ggVGd')
        h.check(
            'and deleting the lot leaves nine empty rows behind',
            #vim.api.nvim_buf_get_lines(0, 0, -1, false) == 9,
            #vim.api.nvim_buf_get_lines(0, 0, -1, false) .. ' lines'
        )

        -- u must not be able to reach the empty buffer the drawer started as.
        -- The guard above would read that back as nine empty cash registers
        press('u')
        press('u')
        press('u')
        h.check(
            'undo cannot rewind past the drawer being opened',
            #vim.api.nvim_buf_get_lines(0, 0, -1, false) == 9,
            #vim.api.nvim_buf_get_lines(0, 0, -1, false) .. ' lines'
        )

        press('<C-c>')
        h.check('the drawer closes', not ui.isOpen())
    end

    ----------------------------------------------------------------------

    h.group('the selected cash register is not left behind')

    do
        local origin = fresh()
        cash.setSearch('foo')
        vim.fn.setreg('/', 'foo')
        cash.setCashRegister(2)
        cash.setSearch('bar')
        cash.setCashRegister(1)

        vim.cmd('Cash')
        edit('ggVGd')

        h.check(
            'clearing every row removes every match',
            #vim.fn.getmatches(origin) == 0,
            #vim.fn.getmatches(origin) .. ' matches'
        )

        -- the selected cash register is painted by vim's own hlsearch on @/
        -- rather than by a match, so it is the one register updateHighlights
        -- cannot reach. Left behind, it goes on painting what it said when the
        -- drawer opened, which looks like highlighting that will not go away
        h.check(
            'and empties the search register with them',
            vim.fn.getreg('/') == '',
            'got [' .. vim.fn.getreg('/') .. ']'
        )

        press('q')
    end

    ----------------------------------------------------------------------

    h.group('undo inside the drawer')

    do
        fresh()
        cash.setSearch('foo')
        cash.setCashRegister(2)
        cash.setSearch('bar')
        cash.setCashRegister(1)
        vim.cmd('Cash')

        -- dropping undolevels and putting it back throws the whole undo
        -- history away rather than skipping one change, so doing it on every
        -- write left nothing to undo at all
        edit('ggVGd')
        h.check(
            'a change made in the drawer can be undone',
            #vim.fn.undotree().entries > 0,
            #vim.fn.undotree().entries .. ' undo entries'
        )

        edit('u')
        h.check(
            'and u puts the patterns back',
            vim.api.nvim_buf_get_lines(0, 0, 2, false)[1] == 'foo',
            vim.inspect(vim.api.nvim_buf_get_lines(0, 0, 2, false))
        )
        h.check(
            'without the row count drifting',
            vim.api.nvim_buf_line_count(0) == 9,
            vim.api.nvim_buf_line_count(0) .. ' lines'
        )

        press('q')
    end

    ----------------------------------------------------------------------

    h.group('opening the drawer ends a nohlsearch')

    do
        local origin = fresh()
        cash.setSearch('foo')
        cash.setCashRegister(2)
        cash.setSearch('bar')
        cash.setCashRegister(1)

        vim.cmd('nohlsearch')
        cash.updateHighlights()
        h.check(
            'nothing is lit to begin with',
            #vim.fn.getmatches(origin) == 0,
            #vim.fn.getmatches(origin) .. ' matches'
        )

        -- there is no point showing every cash register's contents and colors
        -- in the drawer while the buffer behind it stays dark, and the preview
        -- would have nothing to preview
        vim.cmd('Cash')
        h.check(
            'opening the drawer brings the highlighting back',
            vim.v.hlsearch == 1 and #vim.fn.getmatches(origin) == 1,
            'v:hlsearch='
                .. vim.v.hlsearch
                .. ' '
                .. #vim.fn.getmatches(origin)
                .. ' matches'
        )

        press('q')
        h.check(
            'and it is still on once the drawer closes',
            vim.v.hlsearch == 1 and #vim.fn.getmatches(origin) == 1,
            'v:hlsearch='
                .. vim.v.hlsearch
                .. ' '
                .. #vim.fn.getmatches(origin)
                .. ' matches'
        )
    end

    ----------------------------------------------------------------------

    h.group('abandoning changes')

    do
        fresh()
        cash.setSearch('kept')
        cash.setCashRegister(3)
        cash.setSearch('also kept')
        cash.setCashRegister(1)
        cash.setIncludeInSearch(3, true)

        vim.cmd('Cash')
        edit('1Gcwwrecked<Esc>')
        press('4G')
        press('<Space>')
        h.check(
            'a change is live before the drawer closes',
            cash.state.cashRegisters[1].pattern == 'wrecked'
                and cash.state.cashRegisters[4].includeInSearch
        )

        press('<C-c>')
        h.check('ctrl-c closes the drawer', not ui.isOpen())
        h.check(
            'and puts every pattern back',
            cash.state.cashRegisters[1].pattern == 'kept'
                and cash.state.cashRegisters[3].pattern == 'also kept',
            vim.inspect(patternsOf())
        )
        h.check(
            'including the switches',
            cash.state.cashRegisters[3].includeInSearch
                and not cash.state.cashRegisters[4].includeInSearch
        )
        h.check(
            'and the search register',
            vim.fn.getreg('/') == 'kept',
            'got [' .. vim.fn.getreg('/') .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('selecting searches in the right window')

    do
        local origin = fresh()
        vim.api.nvim_buf_set_lines(
            0,
            0,
            -1,
            false,
            { 'aaa', 'bbb', 'ccc', 'target here', 'ddd' }
        )
        cash.setCashRegister(2)
        cash.setSearch('target')
        cash.setCashRegister(1)
        vim.api.nvim_win_set_cursor(origin, { 1, 0 })

        vim.cmd('Cash')
        press('2G')
        press('<Tab>')

        -- selecting a cash register searches for its pattern. Run with the
        -- drawer focused, that jump lands in the list of patterns instead of
        -- in the buffer the user came from
        h.check(
            'the jump happens in the window behind the drawer',
            vim.api.nvim_win_get_cursor(origin)[1] == 4,
            'origin cursor on line ' .. vim.api.nvim_win_get_cursor(origin)[1]
        )
        h.check('and the drawer is still open', ui.isOpen())

        press('q')
    end

    ----------------------------------------------------------------------

    h.group('the :Cash command')

    do
        local origin = fresh()

        vim.cmd('Cash include 4')
        h.check(
            ':Cash include switches a cash register on',
            cash.state.cashRegisters[4].includeInSearch
        )

        vim.cmd('Cash exclude 4')
        h.check(
            ':Cash exclude switches it off',
            not cash.state.cashRegisters[4].includeInSearch
        )

        vim.cmd('Cash toggle 4')
        h.check(
            ':Cash toggle flips it',
            cash.state.cashRegisters[4].includeInSearch
        )

        vim.cmd('Cash use 6')
        h.check(
            ':Cash use selects one',
            cash.state.currentIndex == 6,
            'selected ' .. cash.state.currentIndex
        )

        cash.setSearch('goes away')
        vim.cmd('Cash clear')
        h.check(
            ':Cash clear empties the selected cash register',
            cash.state.cashRegisters[6].pattern == ''
        )

        cash.setSearch('kept')
        cash.setCashRegister(7)
        vim.cmd('Cash clear 6')
        h.check(
            ':Cash clear with an index empties that one instead',
            cash.state.cashRegisters[6].pattern == ''
                and cash.state.currentIndex == 7
        )

        -- hide and show drive v:hlsearch, which every cash register follows
        cash.setCashRegister(1)
        cash.setSearch('foo')
        cash.setCashRegister(2)
        h.check(
            'a cash register is lit to begin with',
            #vim.fn.getmatches(origin) == 1,
            #vim.fn.getmatches(origin) .. ' matches'
        )

        vim.cmd('Cash hide')
        h.check(
            ':Cash hide takes every highlight away',
            #vim.fn.getmatches(origin) == 0,
            #vim.fn.getmatches(origin) .. ' matches'
        )

        vim.cmd('Cash show')
        h.check(
            ':Cash show brings them back',
            #vim.fn.getmatches(origin) == 1,
            #vim.fn.getmatches(origin) .. ' matches'
        )

        vim.cmd('Cash reset')
        h.check(
            ':Cash reset goes back to cash register 1',
            cash.state.currentIndex == 1
                and cash.state.cashRegisters[1].pattern == ''
        )

        h.check(
            'a verb that does not exist is refused rather than thrown',
            pcall(function()
                vim.cmd('Cash bogus')
            end)
        )
    end

    ----------------------------------------------------------------------

    h.group('the detail pane')

    do
        -- the drawer and the pane side by side need more room than a headless
        -- run gives by default, and openPane refuses rather than showing
        -- something clipped in half
        local columns = vim.o.columns
        vim.o.columns = 120

        fresh()
        cash.setSearch('foo')
        cash.setCashRegister(2)
        cash.setSearch('bar')
        cash.setCashRegister(1)

        vim.cmd('Cash')
        h.check('it starts closed', not ui.isOpenPane())

        press('?')
        h.check('? opens it', ui.isOpenPane())

        local function paneText()
            return table.concat(ui.paneContents(), '\n')
        end

        press('2G')
        vim.cmd('doautocmd CursorMoved')
        h.check(
            'it names the cash register under the cursor',
            paneText():find('cash register 2', 1, true) ~= nil,
            paneText()
        )

        -- the resolved form is the one vim is actually given, and is not
        -- shown anywhere else
        h.check(
            'the contents as typed, and the pattern vim is really given',
            paneText():find('contents', 1, true) ~= nil
                and paneText():find('match pattern', 1, true) ~= nil
                and paneText():find('\\Cbar', 1, true) ~= nil,
            paneText()
        )
        h.check(
            'whether it is in the search set',
            paneText():find('include in search', 1, true) ~= nil,
            paneText()
        )

        -- the ledger, which nothing else surfaces. This is issue #3's real ask
        h.check(
            'and the windows carrying a match for it',
            paneText():find('matching window IDs%s+%d+') ~= nil,
            paneText()
        )

        -- the selected cash register never has a ledger entry, because it is
        -- drawn by vim's hlsearch rather than by a match. The selected line is
        -- what accounts for that
        press('1G')
        vim.cmd('doautocmd CursorMoved')
        h.check(
            'it says which cash register is the selected one',
            paneText():find('selected', 1, true) ~= nil,
            paneText()
        )
        -- the selected cash register has no matchadd of its own -- it is
        -- drawn by hlsearch -- but its pattern is still visibly matching in
        -- the window behind, so it must be listed. Reporting the ledger here
        -- said "none" while the text was lit up on screen
        h.check(
            'the selected cash register still lists the window it matches in',
            paneText():find('matching window IDs%s+%d+') ~= nil,
            paneText()
        )

        -- the selected cash register is in the search set whatever its own
        -- switch says, so the pane answers "will n visit it" rather than
        -- reporting the flag. The dot in the drawer already works this way,
        -- and the two must not contradict each other
        h.check(
            'the selected cash register always reads as included',
            not cash.state.cashRegisters[1].includeInSearch
                and paneText():find('include in search%s+yes') ~= nil,
            paneText()
        )

        press('5G')
        vim.cmd('doautocmd CursorMoved')
        h.check(
            'an empty cash register says so rather than showing nothing',
            paneText():find('empty', 1, true) ~= nil,
            paneText()
        )

        -- a pattern gets a matchadd whether or not it matches anything, so
        -- the ledger claimed a window for one that occurs nowhere
        edit('5Gazzzzzzzz<Esc>')
        vim.cmd('doautocmd CursorMoved')
        h.check(
            'a pattern that matches nothing lists no windows',
            paneText():find('matching window IDs%s+none') ~= nil,
            paneText()
        )

        press('?')
        h.check('? closes it again', not ui.isOpenPane())

        press('?')
        press('q')
        h.check(
            'and closing the drawer takes the pane with it',
            not ui.isOpen() and not ui.isOpenPane()
        )

        -- narrower than the two side by side, so it says so instead of
        -- drawing something unreadable
        vim.o.columns = 80
        vim.cmd('Cash')
        press('?')
        h.check(
            'and it refuses to open where there is no room for it',
            not ui.isOpenPane()
        )
        press('q')

        vim.o.columns = columns
    end

    ----------------------------------------------------------------------

    h.group('drawer options')

    do
        h.check(
            'an unknown drawer option is rejected',
            not pcall(cash.setup, { drawer = { bogus = true } })
        )
        h.check(
            'a border of the wrong type is rejected',
            ---@diagnostic disable-next-line: assign-type-mismatch
            not pcall(cash.setup, { drawer = { border = 7 } })
        )
        h.check(
            'a named border is accepted',
            pcall(cash.setup, { drawer = { border = 'single' } })
        )
        h.check(
            'detailPane must be a boolean',
            ---@diagnostic disable-next-line: assign-type-mismatch
            not pcall(cash.setup, { drawer = { detailPane = 'yes' } })
        )

        -- drawer.detailPane decides only whether it is already open; ? still
        -- toggles it either way
        local columns = vim.o.columns
        vim.o.columns = 120
        fresh({ drawer = { detailPane = true } })
        vim.cmd('Cash')
        h.check('detailPane = true opens it with the drawer', ui.isOpenPane())
        press('q')
        vim.o.columns = columns
    end

    ui.close()
    fresh()
end
