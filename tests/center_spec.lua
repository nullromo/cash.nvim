-- Tests for centerAfterSearch.
--
-- The rule these are about:
--
--     with centerAfterSearch on, every path that performs a search leaves the
--     match centered in the window; with it off, none of them scroll at all
--
-- The option used to be honoured by * and # alone, so each path gets its own
-- check rather than one check standing in for the rest.
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')

    -- the only match is three lines below the cursor, and the cursor starts on
    -- the bottom line of the window. Vim on its own scrolls just far enough to
    -- bring the match into view, which leaves the cursor on the bottom line
    -- again, so a centered window and an unscrolled one are half a screen
    -- apart and cannot be confused
    local target = 'unmistakable'
    local matchLine = 203
    local startLine = 200

    local function fresh(opts)
        vim.cmd('silent! tabonly')
        vim.cmd('silent! only')
        vim.opt.ignorecase = false
        vim.opt.scrolloff = 0
        vim.opt.wrapscan = true
        cash.setup(opts or {})
        cash.resetCashRegisters()

        local lines = {}
        for index = 1, 400 do
            lines[index] = 'line ' .. index
        end
        lines[matchLine] = target
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

        vim.v.hlsearch = 1
        vim.v.searchforward = 1
        vim.api.nvim_win_set_cursor(0, { startLine, 0 })
        vim.cmd('normal! zb')
    end

    -- where the cursor sits when the window is centered on it
    local function centeredWinline()
        return math.floor((vim.api.nvim_win_get_height(0) + 1) / 2)
    end

    local function isCentered()
        return vim.fn.winline() == centeredWinline()
    end

    -- where the cursor sits when nothing has scrolled the window: still on the
    -- bottom line, where zb and then vim's own minimal scroll left it
    local function isUnscrolled()
        return vim.fn.winline() == vim.api.nvim_win_get_height(0)
    end

    local function detail()
        return 'winline '
            .. vim.fn.winline()
            .. '; centered is '
            .. centeredWinline()
            .. ', unscrolled is '
            .. vim.api.nvim_win_get_height(0)
    end

    -- 'm' so that the cmdline <CR> mapping and n are actually reached, and a
    -- wait afterwards because the / mapping can only center from a schedule:
    -- the search has not run yet at the point the mapping hands back its <CR>
    local function press(keys)
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes(keys, true, false, true),
            'mx',
            false
        )
        vim.wait(50)
    end

    -- puts the cursor on the match itself, for the paths that work from the
    -- word under it rather than from a pattern
    local function startOnTheMatch()
        vim.api.nvim_win_set_cursor(0, { matchLine, 0 })
        vim.cmd('normal! zb')
    end

    -- makes target the working cash register's pattern without searching for
    -- it, so that a following n has somewhere to go
    local function arm(pattern)
        cash.setSearch(pattern)
        vim.fn.setreg('/', pattern)
    end

    ----------------------------------------------------------------------

    h.group('centerAfterSearch on')

    do
        fresh({ centerAfterSearch = true })
        press('/' .. target .. '<CR>')
        h.check('a / search centers the window', isCentered(), detail())
    end

    do
        fresh({ centerAfterSearch = true })
        startOnTheMatch()
        press('*')
        h.check('* centers the window', isCentered(), detail())
    end

    do
        fresh({ centerAfterSearch = true })
        startOnTheMatch()
        press('#')
        h.check('# centers the window', isCentered(), detail())
    end

    do
        fresh({ centerAfterSearch = true })
        cash.state.cashRegisters[3].pattern = target
        cash.setCashRegister(3)
        h.check(
            'switching to another cash register centers the window',
            isCentered(),
            detail()
        )
    end

    do
        fresh({ centerAfterSearch = true })
        arm(target)
        press('n')
        h.check('n centers the window', isCentered(), detail())
    end

    -- with a second register in the search set, n is jump.go's own loop rather
    -- than a hand back to vim, so it centers by a different route
    do
        fresh({ centerAfterSearch = true })
        arm(target)
        cash.state.cashRegisters[5].pattern = 'line 399'
        cash.setIncludeInSearch(5, true)
        press('n')
        h.check(
            'n centers with more than one register in the search set',
            isCentered(),
            detail()
        )
    end

    do
        fresh({ centerAfterSearch = true })
        vim.api.nvim_win_set_cursor(0, { matchLine + 3, 0 })
        vim.cmd('normal! zb')
        arm(target)
        press('N')
        h.check('N centers the window', isCentered(), detail())
    end

    ----------------------------------------------------------------------

    h.group('centerAfterSearch off')

    do
        fresh({ centerAfterSearch = false })
        press('/' .. target .. '<CR>')
        h.check('a / search does not scroll', isUnscrolled(), detail())
    end

    do
        fresh({ centerAfterSearch = false })
        startOnTheMatch()
        press('*')
        h.check('* does not scroll', isUnscrolled(), detail())
    end

    do
        fresh({ centerAfterSearch = false })
        cash.state.cashRegisters[3].pattern = target
        cash.setCashRegister(3)
        h.check(
            'switching to another cash register does not scroll',
            isUnscrolled(),
            detail()
        )
    end

    do
        fresh({ centerAfterSearch = false })
        arm(target)
        press('n')
        h.check('n does not scroll', isUnscrolled(), detail())
    end

    do
        fresh({ centerAfterSearch = false })
        arm(target)
        cash.state.cashRegisters[5].pattern = 'line 399'
        cash.setIncludeInSearch(5, true)
        press('n')
        h.check(
            'n with more than one register in the search set does not scroll',
            isUnscrolled(),
            detail()
        )
    end

    ----------------------------------------------------------------------

    -- a search that finds nothing has not moved the cursor, and vim does not
    -- scroll the window for one either, so centering it would be movement the
    -- user did not ask for and vim would not have made
    h.group('a search that finds nothing')

    local missing = 'definitelynotinthisbuffer'

    do
        fresh({ centerAfterSearch = true })
        press('/' .. missing .. '<CR>')
        h.check(
            'a / search that finds nothing does not scroll',
            isUnscrolled(),
            detail()
        )
    end

    do
        fresh({ centerAfterSearch = true })
        cash.state.cashRegisters[4].pattern = missing
        cash.setCashRegister(4)
        h.check(
            'switching to a cash register whose pattern matches nothing does '
                .. 'not scroll',
            isUnscrolled(),
            detail()
        )
    end

    do
        fresh({ centerAfterSearch = true })
        arm(missing)
        press('n')
        h.check(
            'n with nothing to find does not scroll',
            isUnscrolled(),
            detail()
        )
    end

    do
        fresh({ centerAfterSearch = true })
        arm('\\(unclosed')
        press('n')
        h.check(
            'n on a pattern vim cannot compile does not scroll',
            isUnscrolled(),
            detail()
        )
    end

    fresh()
end
