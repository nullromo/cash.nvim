-- Tests for the indicator: the always-on answer to which cash register is the
-- working one.
--
-- Three things are being tested, and they are three different kinds of thing.
-- The label is data and is checked as data. The statusline is a string vim
-- parses, so it is handed to vim and the drawn result is what is checked --
-- the %# items in it mean nothing unless vim re-parses them, which is the
-- whole reason the %{% %} form is what the docs tell people to write. The
-- float is a window, and what matters about it is that there is exactly one,
-- that it says what the label says, and that it stays out of everything else.
--
-- See CONTEXT.md for the vocabulary.

return function(h)
    local cash = require('cash')
    local constants = require('cash.constants')
    local highlights = require('cash.highlights')
    local indicator = require('cash.indicator')
    local options = require('cash.options')
    local ui = require('cash.ui')

    local function fresh(indicatorOpts)
        vim.cmd('silent! tabonly')
        vim.cmd('silent! only')
        vim.opt.ignorecase = false
        cash.setup({ indicator = indicatorOpts })
        cash.resetCashRegisters()
        vim.api.nvim_buf_set_lines(
            0,
            0,
            -1,
            false,
            { 'foo bar baz', 'foo again' }
        )
        vim.v.hlsearch = 1
    end

    local function store(index, pattern)
        local previous = cash.state.currentIndex
        cash.setCashRegister(index)
        cash.setSearch(pattern)
        cash.setCashRegister(previous)
    end

    -- the highlight group covering a given character of the label
    local function groupAt(label, character)
        local column = 0
        for _, chunk in ipairs(label.chunks) do
            if chunk[1] == character then
                return chunk[2]
            end
            column = column + #chunk[1]
        end
        return nil
    end

    ----------------------------------------------------------------------

    h.group('the label')

    do
        fresh()

        local label = cash.label()
        h.check(
            'is the working cash register in brackets',
            label.text == '❰1❱',
            label.text
        )
        h.check(
            'with nothing between the bracket and the number',
            label.text:sub(1, #'❰1') == '❰1',
            label.text
        )
        h.check(
            'and names the working cash register as data as well',
            label.index == 1 and label.group == 'CashRegister1',
            vim.inspect({ label.index, label.group })
        )

        cash.setCashRegister(3)
        h.check(
            'following the working cash register',
            cash.label().text == '❰3❱',
            cash.label().text
        )
    end

    do
        fresh({ display = 'number-and-pattern' })
        cash.setSearch('foo')

        h.check(
            'showing the pattern as well when asked for both',
            cash.label().text == '❰1 foo❱',
            cash.label().text
        )

        cash.clearCashRegister(1)
        h.check(
            'and nothing but the number for an empty cash register',
            cash.label().text == '❰1❱',
            cash.label().text
        )
    end

    do
        fresh({ display = 'pattern' })
        cash.setSearch('foo')

        h.check(
            'the pattern on its own leaves the number out',
            cash.label().text == '❰foo❱',
            cash.label().text
        )

        -- the style shapes the number, and there is no number in here
        h.check(
            'and the strip has nothing to shape',
            cash.label({ style = 'strip' }).text == '❰foo❱',
            cash.label({ style = 'strip' }).text
        )

        cash.clearCashRegister(1)
        h.check(
            'an empty cash register is the dot, not an empty pair of brackets',
            cash.label().text == '❰·❱',
            cash.label().text
        )
    end

    do
        fresh({ display = 'number-and-pattern', maxWidth = 10 })
        cash.setSearch('abcdefghij')

        -- maxWidth is the whole label, brackets included, so this is the two
        -- brackets, the number, the space, and six cells of pattern
        h.check(
            'a label too wide for maxWidth is cut short to fit',
            cash.label().text == '❰1 abcde~❱',
            cash.label().text
        )
        h.check(
            'which is maxWidth exactly',
            vim.fn.strdisplaywidth(cash.label().text) == 10,
            vim.fn.strdisplaywidth(cash.label().text) .. ' cells'
        )

        -- the brackets are whatever was asked for, and two of the named pairs
        -- are two cells wide under ambiwidth=double. What they cost has to be
        -- measured rather than counted
        fresh({
            display = 'number-and-pattern',
            maxWidth = 10,
            brackets = { left = '【', right = '】' },
        })
        cash.setSearch('abcdefghij')
        h.check(
            'and the brackets are measured, not counted',
            vim.fn.strdisplaywidth(cash.label().text) == 10,
            cash.label().text
                .. ' is '
                .. vim.fn.strdisplaywidth(cash.label().text)
                .. ' cells'
        )

        -- room for the ~ and nothing else says that there is a pattern and
        -- not one thing about what it is
        fresh({ display = 'number-and-pattern', maxWidth = 5 })
        cash.setSearch('abcdefghij')
        h.check(
            'a maxWidth with no room for any of the pattern leaves it out',
            cash.label().text == '❰1❱',
            cash.label().text
        )

        -- the number is the answer the indicator exists to give, so a label
        -- too narrow comes out too wide rather than unable to answer
        fresh({ display = 'number-and-pattern', style = 'strip', maxWidth = 10 })
        cash.setSearch('abcdefghij')
        h.check(
            'and the number is never the part that gives way',
            cash.label().text == '❰▸1 2 3 4 5 6 7 8 9❱',
            cash.label().text
        )

        -- the search set is part of the number in the narrow style, so it is
        -- not what gives way either
        fresh({ display = 'number-and-pattern', maxWidth = 10 })
        cash.setSearch('abcdefghij')
        cash.setIncludeInSearch(3, true)
        cash.setIncludeInSearch(5, true)
        h.check(
            'nor is the rest of the search set',
            cash.label().text == '❰▸1 3 5❱',
            cash.label().text
        )

        fresh({ display = 'pattern', maxWidth = 3 })
        cash.setSearch('abcdefghij')
        h.check(
            'a pattern with no room for it is the dot, not empty brackets',
            cash.label().text == '❰·❱',
            cash.label().text
        )
    end

    do
        fresh()
        h.check(
            'overrides answer a question other than the configured one',
            cash.label({ display = 'number-and-pattern', style = 'strip' }).text
                    ~= cash.label().text
                and cash.opts.indicator.display == 'number',
            'the overrides leaked into the options'
        )
    end

    do
        -- every name resolves to a pair. Asked of the list rather than of the
        -- table, because nothing checks that the two agree: a key type is one
        -- of the few things lua-language-server does not compare against an
        -- alias, so a name offered by autocomplete could otherwise be one
        -- setup refuses
        local missing = {}
        for _, style in ipairs(constants.bracketStyles) do
            local pair = constants.brackets[style]
            if
                type(pair) ~= 'table'
                or type(pair.left) ~= 'string'
                or type(pair.right) ~= 'string'
            then
                table.insert(missing, style)
            end
        end

        h.check(
            'every named bracket style has a pair behind it',
            #missing == 0,
            'without one: ' .. table.concat(missing, ', ')
        )
    end

    do
        fresh({ brackets = 'ascii' })
        h.check(
            'a named bracket style is the pair it names',
            cash.label().text == '[1]',
            cash.label().text
        )

        fresh({ brackets = { left = '(', right = ')' } })
        h.check(
            'and a pair written out is used as it stands',
            cash.label().text == '(1)',
            cash.label().text
        )

        h.check(
            'either way, the resolved options hold the pair',
            cash.opts.indicator.brackets.left == '('
                and cash.opts.indicator.brackets.right == ')',
            vim.inspect(cash.opts.indicator.brackets)
        )

        h.check(
            'and an override can name one too',
            cash.label({ brackets = 'double-square' }).text == '⟬1⟭',
            cash.label({ brackets = 'double-square' }).text
        )

        -- an override is read as it comes rather than validated, so a name
        -- that is not one of them has to draw something rather than throw
        -- from inside a redraw.
        --
        -- The cast is the annotations working: lua-language-server refuses
        -- this name in an editor, which is the point of naming the pairs in
        -- the alias, and the test still has to hand over what a config that
        -- ignores the warning would hand over
        ---@type any
        local madeUp = 'nonsense'
        h.check(
            'a name an override made up falls back to the default pair',
            cash.label({ brackets = madeUp }).text == '❰1❱',
            cash.label({ brackets = madeUp }).text
        )
    end

    do
        local refused = {
            ['a name that is not one of them'] = 'fancy',
            ['half a pair'] = { left = '(' },
            ['a stray key'] = { left = '(', right = ')', middle = '|' },
            ['neither a name nor a pair'] = 7,
        }

        local accepted = {}
        for what, brackets in pairs(refused) do
            local written = { indicator = { brackets = brackets } }
            if pcall(options.resolve, written) then
                table.insert(accepted, what)
            end
        end

        h.check(
            'setup refuses brackets it cannot draw',
            #accepted == 0,
            'accepted: ' .. table.concat(accepted, ', ')
        )
    end

    do
        fresh()
        local label = cash.label()

        local covered = 0
        local unpainted = 0
        for _, chunk in ipairs(label.chunks) do
            covered = covered + #chunk[1]
            if chunk[2] == nil then
                unpainted = unpainted + 1
            end
        end

        h.check(
            'the chunks are the whole text and nothing else',
            covered == #label.text,
            covered .. ' bytes of ' .. #label.text
        )
        h.check(
            'and every one of them names a group',
            unpainted == 0,
            unpainted .. ' chunks without one'
        )
    end

    ----------------------------------------------------------------------

    h.group('the strip')

    do
        fresh({ style = 'strip' })
        store(4, 'bar')
        store(5, 'baz')
        cash.setIncludeInSearch(4, true)
        cash.setIncludeInSearch(8, true)
        cash.setCashRegister(2)

        local label = cash.label()
        h.check(
            'is all nine numbers, with nothing between them and the brackets',
            label.text == '❰1▸2 3 4 5 6 7 8 9❱',
            label.text
        )
        h.check(
            'a cash register in the search set wears its color as a swatch',
            groupAt(label, '2') == 'CashRegister2'
                and groupAt(label, '4') == 'CashRegister4',
            vim.inspect({ groupAt(label, '2'), groupAt(label, '4') })
        )
        h.check(
            'one holding a pattern that n and N skip wears it as text',
            groupAt(label, '5') == 'CashRegisterFg5',
            tostring(groupAt(label, '5'))
        )
        h.check(
            'one that is neither is in Comment',
            groupAt(label, '7') == 'Comment',
            tostring(groupAt(label, '7'))
        )
        h.check(
            'and an included cash register with nothing in it is swatched all'
                .. ' the same',
            groupAt(label, '8') == 'CashRegister8',
            tostring(groupAt(label, '8'))
        )

        -- the marker takes the place of the space in front of the working
        -- number, so the one it is in front of can change without any of the
        -- numbers moving
        local before = cash.label().text
        cash.setCashRegister(9)
        local after = cash.label().text
        h.check(
            'the marker says which one is working',
            after == '❰1 2 3 4 5 6 7 8▸9❱',
            after
        )
        h.check(
            'and moving it moves nothing else',
            vim.fn.strdisplaywidth(before) == vim.fn.strdisplaywidth(after)
                and before:gsub('▸', ' ') == after:gsub('▸', ' '),
            before .. ' then ' .. after
        )

        -- cash register 1 has no space in front of it for the marker to take,
        -- so it is the one label that comes out a cell wider. The alternative
        -- is a blank cell after the left bracket in the other eight
        cash.setCashRegister(1)
        h.check(
            'and cash register 1 takes the marker without a space for it',
            cash.label().text == '❰▸1 2 3 4 5 6 7 8 9❱'
                and vim.fn.strdisplaywidth(cash.label().text)
                    == vim.fn.strdisplaywidth(after) + 1,
            cash.label().text
        )
    end

    ----------------------------------------------------------------------

    h.group('the search set in the narrow style')

    do
        fresh()

        h.check(
            'a search set of one is that number on its own, with no marker',
            cash.label().text == '❰1❱',
            cash.label().text
        )

        cash.setIncludeInSearch(1, true)
        cash.setIncludeInSearch(3, true)
        cash.setIncludeInSearch(5, true)
        h.check(
            'and the whole set once there is more of it',
            cash.label().text == '❰▸1 3 5❱',
            cash.label().text
        )

        cash.setCashRegister(3)
        h.check(
            'with the marker on the working one wherever it sits in the set',
            cash.label().text == '❰1 ▸3 5❱',
            cash.label().text
        )

        local label = cash.label()
        h.check(
            'every number in the set wearing its own color as a swatch',
            groupAt(label, '1') == 'CashRegister1'
                and groupAt(label, '5') == 'CashRegister5',
            vim.inspect({ groupAt(label, '1'), groupAt(label, '5') })
        )

        cash.setIncludeInSearch(5, false)
        h.check(
            'a cash register taken out of the set leaves the label',
            cash.label().text == '❰1 ▸3❱',
            cash.label().text
        )

        -- the working cash register is in the search set whatever its own
        -- switch says, which is jump.searchSet's rule and has to be the
        -- indicator's too
        cash.setCashRegister(7)
        h.check(
            'and the working one is in it with its own switch off',
            cash.label().text == '❰1 3 ▸7❱'
                and cash.state.cashRegisters[7].includeInSearch == false,
            cash.label().text
        )
    end

    ----------------------------------------------------------------------

    h.group('the statusline')

    do
        fresh({ display = 'number-and-pattern' })
        cash.setCashRegister(3)
        cash.setSearch('50%')

        local text = cash.statusline()
        h.check(
            "names the cash register's highlight groups",
            text:find('%%#CashRegister3#') ~= nil,
            text
        )
        h.check('ends by handing the colors back', text:sub(-2) == '%*', text)
        h.check(
            'and doubles every % in the pattern',
            text:find('50%%%%', 1) ~= nil and text:find('50%%[^%%]') == nil,
            text
        )

        -- what vim actually draws, which is the only thing that settles
        -- whether the %{% %} form carries the highlights
        local statusline = "x %{%v:lua.require'cash'.statusline()%} y"
        local drawn = vim.api.nvim_eval_statusline(statusline, {
            highlights = true,
        })

        h.check(
            'drawn by vim, it is the label and the % is one %',
            drawn.str == 'x ❰3 50%❱ y',
            drawn.str
        )

        local painted = false
        for _, highlight in ipairs(drawn.highlights) do
            if highlight.group == 'CashRegister3' then
                painted = true
            end
        end
        h.check(
            "in the working cash register's colors",
            painted,
            vim.inspect(drawn.highlights)
        )
    end

    ----------------------------------------------------------------------

    h.group('the indicator window')

    do
        fresh()
        h.check(
            'is not there until it is asked for',
            #indicator.windows() == 0,
            #indicator.windows() .. ' windows'
        )

        fresh({ show = true })
        h.check(
            'and is there once it is',
            #indicator.windows() == 1,
            #indicator.windows() .. ' windows'
        )

        cash.updateIndicator()
        cash.updateIndicator()
        h.check(
            'however many times the state is brought in line',
            #indicator.windows() == 1,
            #indicator.windows() .. ' windows'
        )

        local window = indicator.windows()[1]
        local config = vim.api.nvim_win_get_config(window)
        h.check(
            'one row tall, and never the window you land in',
            config.height == 1 and config.focusable == false,
            vim.inspect({ config.height, config.focusable })
        )
        h.check(
            'sitting under everything else that is floating',
            config.zindex < 50,
            tostring(config.zindex)
        )
        h.check(
            'as wide as what it says',
            config.width
                == vim.fn.strdisplaywidth(
                    vim.api.nvim_buf_get_lines(
                        vim.api.nvim_win_get_buf(window),
                        0,
                        -1,
                        false
                    )[1]
                ),
            tostring(config.width)
        )

        -- the indicator holds a pattern as literal text, so a match in here
        -- would paint it in the color it is reporting
        cash.setSearch('foo')
        cash.updateIndicator()
        cash.updateHighlights()
        h.check(
            'and out of the highlighting, like the drawer and the picker',
            not vim.tbl_contains(highlights.trackedWindows(), window),
            vim.inspect(highlights.trackedWindows())
        )
    end

    do
        -- row 0 of the editor is the tabline's row when there is a tabline, so
        -- a corner the tabline is in has to start one row lower
        fresh({ show = true, position = 'top-left' })

        vim.o.showtabline = 0
        cash.updateIndicator()
        local function row()
            return vim.api.nvim_win_get_config(indicator.windows()[1]).row
        end
        h.check(
            'sits in the top corner with no tabline to worry about',
            row() == 0,
            tostring(row())
        )

        vim.o.showtabline = 2
        cash.updateIndicator()
        h.check(
            'and one row lower when a tabline is there',
            row() == 1,
            tostring(row())
        )
        vim.o.showtabline = 1
    end

    do
        fresh({ show = true })
        local function said()
            return vim.api.nvim_buf_get_lines(
                vim.api.nvim_win_get_buf(indicator.windows()[1]),
                0,
                -1,
                false
            )[1]
        end

        h.check(
            'says which cash register is working',
            said() == '❰1❱',
            said()
        )

        cash.setCashRegister(6)
        cash.updateIndicator()
        h.check('and follows a switch', said() == '❰6❱', said())
    end

    do
        fresh({ show = true })

        ui.open(cash)
        cash.updateIndicator()
        h.check(
            'gets out of the way of the cash drawer',
            #indicator.windows() == 0,
            #indicator.windows() .. ' windows'
        )

        ui.close()
        cash.updateIndicator()
        h.check(
            'and comes back when the drawer closes',
            #indicator.windows() == 1,
            #indicator.windows() .. ' windows'
        )
    end

    do
        -- on the strip, a cash register filling up changes the color of its
        -- number and not one character of the text. A redraw that compares
        -- only what the label says would leave the old color on screen
        fresh({ show = true, style = 'strip' })
        cash.updateIndicator()

        -- the highlight groups actually on the extmarks, in column order
        local function painted()
            local marks = vim.api.nvim_buf_get_extmarks(
                vim.api.nvim_win_get_buf(indicator.windows()[1]),
                -1,
                0,
                -1,
                { details = true }
            )
            table.sort(marks, function(one, other)
                return one[3] < other[3]
            end)

            local groups = {}
            for _, mark in ipairs(marks) do
                table.insert(groups, mark[4].hl_group)
            end
            return groups
        end

        -- and the ones the label says should be there
        local function wanted()
            local groups = {}
            for _, chunk in ipairs(cash.label().chunks) do
                table.insert(groups, chunk[2])
            end
            return groups
        end

        local before = painted()
        h.check(
            'the float is painted the way the label says',
            vim.deep_equal(before, wanted()),
            vim.inspect({ painted = before, wanted = wanted() })
        )

        store(5, 'bar')
        cash.updateIndicator()

        h.check(
            'and follows a change that alters a color and no text',
            vim.deep_equal(painted(), wanted()),
            vim.inspect({ painted = painted(), wanted = wanted() })
        )
        h.check(
            'which is a change the text alone would not have shown',
            not vim.deep_equal(before, painted()),
            'nothing changed, so this proves nothing'
        )
    end

    do
        fresh({ show = true })
        vim.cmd('tabnew')
        cash.updateIndicator()
        h.check(
            'a float belongs to a tab page, so each one gets its own',
            #indicator.windows() == 2,
            #indicator.windows() .. ' windows'
        )

        vim.cmd('tabclose')
        cash.updateIndicator()
        h.check(
            'and a closed tab page takes its own with it',
            #indicator.windows() == 1,
            #indicator.windows() .. ' windows'
        )
    end

    do
        fresh({ show = true })

        vim.cmd('Cash indicator off')
        h.check(
            ':Cash indicator off takes it off the screen',
            #indicator.windows() == 0 and cash.opts.indicator.show == false,
            #indicator.windows() .. ' windows'
        )

        vim.cmd('Cash indicator toggle')
        h.check(
            'and toggle puts it back',
            #indicator.windows() == 1 and cash.opts.indicator.show == true,
            #indicator.windows() .. ' windows'
        )

        vim.cmd('Cash indicator on')
        h.check(
            'while on with it already on changes nothing',
            #indicator.windows() == 1,
            #indicator.windows() .. ' windows'
        )
    end

    do
        fresh({ display = 'number' })
        cash.setSearch('foo')

        -- :Cash where asks for the whole answer whatever the indicator is
        -- configured to show, so this is the pattern being asked for rather
        -- than the option being read
        local echoed = vim.fn.execute('Cash where')
        h.check(
            ':Cash where says the pattern whatever the option says',
            echoed:find('❰1 foo❱', 1, true) ~= nil,
            vim.inspect(echoed)
        )
    end

    -- the rest of the suite runs in this Neovim, and a float left in the
    -- corner is a window the specs after this one would have to know about
    fresh()
end
