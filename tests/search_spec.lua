-- Tests for what a / search puts in the working cash register.
--
-- The rule these are about:
--
--     the cash register holds the pattern vim searched for, which is not
--     always the text that was typed to start the search
--
-- A search offset (/foo/e) is typed but is no part of the pattern, and an
-- empty command line is not a search for nothing but a repeat of the last
-- search. Taking the command line literally got both wrong, and the second one
-- destructively: emptying the search register in front of the search that was
-- about to reuse it left vim with nothing to repeat (E35) and the cash
-- register empty.
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')

    -- value appears four times: twice as a whole word and twice inside a
    -- longer word
    local lines = {
        'value here',
        'values plural',
        'myvalue prefixed',
        'value again',
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
    end

    -- 'm' so that the cmdline <CR> mapping is reached, and a wait afterwards
    -- because the pattern is only recorded once the search has run
    local function press(keys)
        pcall(
            vim.api.nvim_feedkeys,
            vim.api.nvim_replace_termcodes(keys, true, false, true),
            'mx',
            false
        )
        vim.wait(60, function()
            return false
        end)
    end

    local function working()
        return cash.state.cashRegisters[cash.state.currentIndex].pattern
    end

    local function line()
        return vim.api.nvim_win_get_cursor(0)[1]
    end

    -- how many of the buffer's lines the search register matches, which is
    -- what says whether a search still works without depending on how its
    -- pattern is spelled
    local function linesMatchingSearchRegister()
        local pattern = vim.fn.getreg('/')
        if pattern == '' or not pcall(vim.fn.match, '', pattern) then
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

    h.group('an ordinary / search')

    do
        fresh()
        press('/value<CR>')
        h.check(
            'goes into the working cash register',
            working() == 'value',
            'register holds [' .. working() .. ']'
        )
        h.check(
            'and the search register agrees with it',
            vim.fn.getreg('/') == working(),
            'search register [' .. vim.fn.getreg('/') .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('a / search with a search offset')

    do
        fresh()
        press('/value/e<CR>')
        h.check(
            'stores the pattern without the offset',
            working() == 'value',
            'register holds [' .. working() .. ']'
        )

        local before = linesMatchingSearchRegister()
        cash.setCashRegister(2)
        cash.setCashRegister(1)
        h.check(
            'so it still matches after a round trip through the register',
            linesMatchingSearchRegister() == before and before > 0,
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

    h.group('an empty / repeats the last search')

    do
        fresh()
        press('/value<CR>')
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        press('/<CR>')
        h.check(
            'the cash register still holds the pattern',
            working() == 'value',
            'register holds [' .. working() .. ']'
        )
        h.check(
            'and the search register still holds it too',
            vim.fn.getreg('/') == 'value',
            'search register [' .. vim.fn.getreg('/') .. ']'
        )
        h.check(
            'and the repeat actually moved the cursor',
            line() == 2,
            'cursor ended on line ' .. line()
        )
    end

    ----------------------------------------------------------------------

    h.group('searches vim refuses or cannot find')

    do
        fresh()
        press('/nosuchword<CR>')
        h.check(
            'a pattern that matches nothing is still recorded',
            working() == 'nosuchword',
            'register holds [' .. working() .. ']'
        )
    end

    do
        -- a cash register holds whatever the user typed, including patterns
        -- vim cannot compile. Vim sets the search register for one of those
        -- too, which is what makes reading it back safe here
        fresh()
        press('/\\(<CR>')
        h.check(
            'and so is one vim cannot compile',
            working() == '\\(',
            'register holds [' .. working() .. ']'
        )
    end
end
