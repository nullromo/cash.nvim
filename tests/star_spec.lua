-- Tests for *, #, g* and g#.
--
-- The rules these are about:
--
--     with disableStarPoundJump on, none of the four move the cursor; with it
--     off, all four move it exactly where vim would
--
--     the working cash register ends up holding what vim searched for -- the
--     whole-word pattern for * and #, the bare word for g* and g# -- so that
--     leaving the register and coming back searches for the same thing again
--
-- The second one is why the g-versions are mapped at all. Left alone they set
-- the search register behind this plugin's back, and the cash register goes
-- stale; and with autoNoHighlight on, the highlighting they turn on is taken
-- away again the moment the cursor lands.
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')

    -- value appears three times as a whole word (lines 1, 4 and 5) and twice
    -- more inside a longer word (lines 2 and 3), which is the whole difference
    -- between * and g*. Line 6 is blank, for the case where there is no word
    -- under the cursor at all
    local lines = {
        'value here',
        'values plural',
        'myvalue prefixed',
        'value again',
        'value once more',
        '',
    }

    local function fresh(opts)
        vim.cmd('silent! tabonly')
        vim.cmd('silent! only')
        vim.opt.ignorecase = false
        vim.opt.wrapscan = true

        -- whatever a previous spec left on these keys. setUpKeymaps replaces
        -- its own mappings, but not another spec's stand-in for a foreign one
        for _, key in ipairs({ '*', '#', 'g*', 'g#' }) do
            pcall(vim.keymap.del, 'n', key)
        end

        cash.setup(opts or {})
        cash.resetCashRegisters()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.v.hlsearch = 1
    end

    -- 'm' so that the mapping is actually reached rather than vim's own key
    local function press(keys)
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes(keys, true, false, true),
            'mx',
            false
        )
        vim.wait(50)
    end

    local function line()
        return vim.api.nvim_win_get_cursor(0)[1]
    end

    local function working()
        return cash.state.cashRegisters[cash.state.currentIndex].pattern
    end

    -- how many of the buffer's lines the search register actually matches,
    -- which is what tells a whole-word search from one that matches inside
    -- other words without depending on how the pattern is spelled
    local function linesMatchingSearchRegister()
        local pattern = vim.fn.getreg('/')
        if pattern == '' then
            return 0
        end

        local count = 0
        for index = 1, vim.api.nvim_buf_line_count(0) do
            local text = vim.api.nvim_buf_get_lines(0, index - 1, index, false)
            if vim.fn.match(text[1], pattern) >= 0 then
                count = count + 1
            end
        end
        return count
    end

    ----------------------------------------------------------------------

    h.group('disableStarPoundJump keeps the cursor where it is')

    for _, key in ipairs({ '*', '#', 'g*', 'g#' }) do
        fresh({ disableStarPoundJump = true })
        press(key)
        h.check(
            key .. ' does not move the cursor',
            line() == 1,
            'cursor ended on line ' .. line()
        )
    end

    ----------------------------------------------------------------------

    h.group('and with it off they move the cursor as vim does')

    do
        fresh({ disableStarPoundJump = false })
        press('*')
        h.check(
            '* goes to the next whole word',
            line() == 4,
            'cursor ended on line ' .. line()
        )
    end

    do
        fresh({ disableStarPoundJump = false })
        press('g*')
        h.check(
            'g* goes to the next match, whole word or not',
            line() == 2,
            'cursor ended on line ' .. line()
        )
    end

    do
        fresh({ disableStarPoundJump = false })
        press('#')
        h.check(
            '# goes backwards, round the end of the buffer',
            line() == 5,
            'cursor ended on line ' .. line()
        )
    end

    do
        -- lines 4, 5 and then round to 1
        fresh({ disableStarPoundJump = false })
        press('3*')
        h.check(
            'a count is honoured',
            line() == 1,
            'cursor ended on line ' .. line()
        )
    end

    do
        -- a count names the occurrence to go to, which is an instruction to
        -- move even where * on its own would have stayed put
        fresh({ disableStarPoundJump = true })
        press('2*')
        h.check(
            'a count jumps even with disableStarPoundJump on',
            line() == 5,
            'cursor ended on line ' .. line()
        )
    end

    ----------------------------------------------------------------------

    h.group('the cash register holds what vim searched for')

    do
        fresh()
        press('*')
        h.check(
            '* stores a whole-word pattern',
            linesMatchingSearchRegister() == 3,
            'the search register ['
                .. vim.fn.getreg('/')
                .. '] matches '
                .. linesMatchingSearchRegister()
                .. ' lines'
        )
        h.check(
            'and the working cash register agrees with it',
            working() == vim.fn.getreg('/'),
            'register ['
                .. working()
                .. '], search register ['
                .. vim.fn.getreg('/')
                .. ']'
        )
    end

    do
        fresh()
        press('g*')
        h.check(
            'g* stores a pattern that matches inside other words',
            linesMatchingSearchRegister() == 5,
            'the search register ['
                .. vim.fn.getreg('/')
                .. '] matches '
                .. linesMatchingSearchRegister()
                .. ' lines'
        )
        h.check(
            'and the working cash register agrees with it',
            working() == vim.fn.getreg('/'),
            'register ['
                .. working()
                .. '], search register ['
                .. vim.fn.getreg('/')
                .. ']'
        )
    end

    do
        -- the two keys have to be told apart by what they leave behind, or a
        -- * search comes back out of its register as a g* search
        fresh()
        press('*')
        local starPattern = working()
        fresh()
        press('g*')
        h.check(
            '* and g* do not store the same pattern',
            starPattern ~= working(),
            'both stored [' .. starPattern .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('a * search survives a round trip through its cash register')

    do
        fresh()
        press('*')
        local before = linesMatchingSearchRegister()

        -- away to another cash register and back again
        cash.setCashRegister(2)
        cash.setCashRegister(1)

        h.check(
            'the search register still matches the same lines',
            linesMatchingSearchRegister() == before,
            'matched '
                .. before
                .. ' lines, now '
                .. linesMatchingSearchRegister()
                .. ' ['
                .. vim.fn.getreg('/')
                .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('a * with no word under the cursor')

    do
        fresh()
        press('/plural<CR>')
        local armed = working()

        -- the last line is empty, so there is no word to search for
        vim.api.nvim_win_set_cursor(0, { 6, 0 })
        press('*')

        h.check(
            'leaves the cash register holding what it held',
            working() == armed,
            'register was [' .. armed .. '], is now [' .. working() .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('mappings that were already there')

    do
        -- something else got to * first, the way another plugin would have
        local foreignRan = false
        vim.keymap.set('n', '*', function()
            foreignRan = true
        end, { desc = 'not cash' })

        cash.setup({})
        cash.resetCashRegisters()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        press('*')
        h.check('the mapping that was there still runs', foreignRan)
        h.check(
            'and this plugin still took the search',
            working() ~= '',
            'the working cash register is empty'
        )

        pcall(vim.keymap.del, 'n', '*')
    end

    do
        -- setup twice over must not leave two of this plugin's mappings on the
        -- key: both would search, and with the jump enabled both would move
        fresh({ disableStarPoundJump = false })
        cash.setup({ disableStarPoundJump = false })
        press('*')
        h.check(
            'setting up twice searches once, not twice',
            line() == 4,
            'cursor ended on line ' .. line()
        )
    end
end
