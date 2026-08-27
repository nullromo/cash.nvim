-- Tests for what the cash registers paint, and where.
--
-- The rule these are about:
--
--     window W shows cash register i's color on every match of i's pattern in
--     the lines W is drawing, exactly when v:hlsearch is on, i is not the
--     working cash register, and i's pattern is not empty
--
-- A cash register is painted with an extmark added while vim is drawing, from a
-- decoration provider, rather than with a match. Issue #13 is why: two matches
-- covering the same text never blend, so a semantic token asking only for bold
-- took a cash register's color away entirely. An extmark is combined with
-- whatever else has something to say about the same text, which is what the
-- screen check at the end of this file is about.
--
-- Nothing is left behind to read afterwards, since an ephemeral extmark lives
-- for one redraw, so the painting decision is asked for rather than looked up.
-- That is what highlights.paintsFor is for.
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')
    local highlights = require('cash.highlights')

    -- two matches on one line, a match with a multibyte character in front of
    -- it, a line with nothing to find, and two patterns that overlap
    local lines = {
        'foo and foo again',
        'wörd foo wörd',
        'nothing here',
        'foobar foo',
    }

    local function fresh()
        vim.cmd('silent! tabonly')
        vim.cmd('silent! only')
        vim.opt.ignorecase = false
        cash.setup({ indicator = { show = false } })
        cash.resetCashRegisters()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, { 3, 0 })
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

    -- what one line is painted, as "index:start-end" per highlight, in the
    -- order the paints come back. The order matters: extmarks of equal
    -- priority are settled by the order they were added
    local function paintedOn(row)
        local out = {}
        for _, paint in
            ipairs(highlights.paintsFor(vim.api.nvim_get_current_buf(), row))
        do
            table.insert(
                out,
                paint.index
                    .. ':'
                    .. paint.startColumn
                    .. '-'
                    .. paint.endColumn
            )
        end
        return table.concat(out, ' ')
    end

    ----------------------------------------------------------------------

    h.group('where a cash register is painted')

    do
        local window = fresh()
        store(2, 'foo')

        -- f-o-o at columns 0 and 8 of 'foo and foo again'. Byte columns
        -- counted from 0, and the end is the column the paint stops before
        h.check(
            'every match on the line is painted, not just the first',
            paintedOn(0) == '2:0-3 2:8-11',
            'got [' .. paintedOn(0) .. ']'
        )

        -- 'wörd foo wörd' -- the ö is two bytes, so foo starts at byte 6 and
        -- character 5. An extmark takes bytes, and getting this wrong paints
        -- one column to the left of the match
        h.check(
            'a multibyte character in front of a match is counted in bytes',
            paintedOn(1) == '2:6-9',
            'got [' .. paintedOn(1) .. ']'
        )

        h.check(
            'a line with no match is painted nothing',
            paintedOn(2) == '',
            'got [' .. paintedOn(2) .. ']'
        )

        h.check(
            'and a window is painted without waiting for a redraw to ask',
            h.litPattern(window, 2) == '\\Cfoo',
            'got [' .. tostring(h.litPattern(window, 2)) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('two cash registers over the same text')

    do
        fresh()
        store(2, 'foo')
        store(5, 'foobar')

        -- 'foobar foo': cash register 2 matches foo twice, cash register 5
        -- matches foobar once, and the two overlap at the start of the line.
        -- Lowest cash register first, so the higher-numbered one is painted
        -- over it. Whichever cash register was written to most recently must
        -- not come into it
        h.check(
            'the lower-numbered one is painted first, whatever order they were stored in',
            paintedOn(3) == '2:0-3 2:7-10 5:0-6',
            'got [' .. paintedOn(3) .. ']'
        )

        store(2, 'foo')
        h.check(
            'and storing the lower one again does not move it',
            paintedOn(3) == '2:0-3 2:7-10 5:0-6',
            'got [' .. paintedOn(3) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('cash registers that paint nothing')

    do
        local window = fresh()
        cash.setSearch('foo')

        h.check(
            'the working cash register is left to vim',
            paintedOn(0) == '',
            'got [' .. paintedOn(0) .. ']'
        )

        store(3, '')
        h.check(
            'an empty cash register paints nothing',
            paintedOn(0) == '',
            'got [' .. paintedOn(0) .. ']'
        )

        -- a cash register holds whatever the user typed, and vim has already
        -- complained about the search itself
        store(3, 'foo\\(')
        h.check(
            'and neither does a pattern vim will not compile',
            paintedOn(0) == '',
            'got [' .. paintedOn(0) .. ']'
        )

        -- a pattern matching without covering anything has nothing to paint
        -- and nothing to move past either. Vim paints nothing for these, and
        -- asking one for its matches has to end rather than stand still
        store(3, '\\<')
        h.check(
            'a pattern with no extent paints nothing, and the line ends',
            paintedOn(0) == '',
            'got [' .. paintedOn(0) .. ']'
        )

        store(3, 'foo')
        h.check(
            'and a usable pattern in the same cash register paints again',
            paintedOn(0) == '3:0-3 3:8-11',
            'got [' .. paintedOn(0) .. ']'
        )

        vim.cmd('nohlsearch')
        h.check(
            'nohlsearch takes the painting away without an update',
            paintedOn(0) == '' and h.litCount(window) == 0,
            'got [' .. paintedOn(0) .. '], ' .. h.litCount(window) .. ' lit'
        )

        vim.v.hlsearch = 1
        h.check(
            'and turning it back on paints again, also without an update',
            paintedOn(0) == '3:0-3 3:8-11',
            'got [' .. paintedOn(0) .. ']'
        )
    end

    ----------------------------------------------------------------------

    -- what matching a line at a time gives up. Both of these were painted when
    -- a cash register was a matchadd, because vim did the matching itself and
    -- did it against the buffer rather than against a line taken out of it.
    -- Known rather than checked, so that a neovim which starts answering these
    -- fails here and gets the limitation taken out of the documentation
    h.group('patterns a line at a time cannot see')

    do
        fresh()

        -- 'foo and foo again' then 'wörd foo wörd', so this one starts on the
        -- first line and ends on the second
        store(3, 'again\\nwörd')
        h.knownBroken(
            'a pattern reaching across a line break is painted',
            paintedOn(0) ~= '',
            'got [' .. paintedOn(0) .. ']'
        )

        -- \%2l is the second line, which is row 1. A line number means nothing
        -- to a pattern matched against one line on its own
        store(3, '\\%2lfoo')
        h.knownBroken(
            'a pattern anchored to a line number is painted',
            paintedOn(1) ~= '',
            'got [' .. paintedOn(1) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('buffers this plugin leaves alone')

    do
        fresh()
        store(2, 'foo')
        local buffer = vim.api.nvim_get_current_buf()

        h.check(
            'an ordinary buffer is painted',
            #highlights.paintsFor(buffer, 0) == 2,
            #highlights.paintsFor(buffer, 0) .. ' paints'
        )

        -- the drawer, the chooser and the telescope picker all hold the
        -- patterns as literal text, so painting them there would paint the
        -- list in the very colors it is explaining
        vim.b[buffer].cashDrawer = true
        h.check(
            'a marked one is not',
            #highlights.paintsFor(buffer, 0) == 0,
            #highlights.paintsFor(buffer, 0) .. ' paints'
        )
        h.check(
            'and reports nothing lit either',
            h.litCount(vim.fn.win_getid()) == 0,
            h.litCount(vim.fn.win_getid()) .. ' lit'
        )

        vim.b[buffer].cashDrawer = nil
    end

    ----------------------------------------------------------------------

    h.group('on screen')

    do
        -- what vim actually drew, for each cell of the match on the first
        -- line. The point of the whole mechanism is a question about the
        -- screen rather than about either highlight: whether the two combined,
        -- or one of them was dropped whole
        local function drawn(row, fromColumn, toColumn)
            -- twice, because the first draw after the message this test's own
            -- output has just written is the one that repaints the window
            vim.cmd('redraw!')
            vim.cmd('redraw!')

            local cells = {}
            for column = fromColumn, toColumn do
                local ok, cell =
                    pcall(vim.api.nvim__inspect_cell, 1, row, column)
                table.insert(cells, (ok and cell and cell[2]) or {})
            end
            return cells
        end

        -- true when every cell of the match came out with the given
        -- background, and bold when bold is asked for
        local function everyCell(cells, background, bold)
            for _, attributes in ipairs(cells) do
                if attributes.background ~= background then
                    return false
                end
                if bold and not attributes.bold then
                    return false
                end
            end
            return #cells > 0
        end

        local window = fresh()
        vim.o.termguicolors = true
        store(2, 'foo')

        local registerBackground =
            vim.api.nvim_get_hl(0, { name = 'CashRegister2' }).bg

        -- the first answer is thrown away. The suite has been printing as it
        -- goes, so the screen is showing messages rather than the window until
        -- vim has drawn over them, and the read that comes back mid-repaint is
        -- of neither one
        drawn(0, 0, 2)

        local painted = drawn(0, 0, 2)
        h.check(
            'a cash register paints its own color',
            everyCell(painted, registerBackground, false),
            vim.inspect(painted)
        )

        -- the shape coc.nvim's document highlight arrives in: matchaddpos, at
        -- priority -1, in a group that asks for bold and says nothing about
        -- color. Painted as a match, a cash register lost to this outright and
        -- the color vanished. That is issue #13
        vim.api.nvim_set_hl(0, 'CashTestBold', { bold = true })
        local boldID = vim.fn.matchaddpos(
            'CashTestBold',
            { { 1, 1, 3 } },
            -1,
            -1,
            { window = window }
        )

        local merged = drawn(0, 0, 2)
        h.check(
            "and keeps it under another plugin's bold instead of losing it",
            everyCell(merged, registerBackground, true),
            vim.inspect(merged)
        )

        pcall(vim.fn.matchdelete, boldID, window)

        -- and the one cash register that cannot do this. The working one is
        -- painted by vim's own hlsearch, which is a match, so another plugin's
        -- highlighting of the same text is dropped rather than combined.
        -- Making vim paint nothing for Search does not hand the text back
        -- either: only v:hlsearch being off does that, and that is this
        -- plugin's way of spelling "no highlighting at all".
        --
        -- Known rather than checked, because it is worth being told if a
        -- neovim ever makes search highlighting combine. The documentation in
        -- doc/cash.txt says it does not
        cash.setCashRegister(2)
        cash.setSearch('foo')
        -- @/ is set by the user actually searching, which setSearch does not do
        vim.fn.setreg('/', 'foo')
        vim.o.hlsearch = true
        vim.cmd('let v:hlsearch = 1')
        cash.updateHighlights()

        local searchBackground = vim.api.nvim_get_hl(0, { name = 'Search' }).bg
        local workingBoldID = vim.fn.matchaddpos(
            'CashTestBold',
            { { 1, 1, 3 } },
            -1,
            -1,
            { window = window }
        )

        drawn(0, 0, 2)
        local working = drawn(0, 0, 2)
        h.check(
            'the working cash register is painted by vim, in its own color',
            everyCell(working, searchBackground, false),
            vim.inspect(working)
        )
        h.knownBroken(
            "and takes another plugin's bold on top of it",
            everyCell(working, searchBackground, true),
            vim.inspect(working)
        )

        pcall(vim.fn.matchdelete, workingBoldID, window)
    end
end
