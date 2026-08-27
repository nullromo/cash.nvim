-- Tests for mapKeys: which of the keys that switch cash registers get mapped.
--
-- The rules these are about:
--
--     both groups are on by default, so ? brings up the chooser and <F1> to
--     <F10> switch cash registers without one
--
--     either group can be switched off on its own, and a group that is off is
--     not mapped at all -- ? goes back to being a backward search, and the
--     function keys go back to whatever they were
--
--     switching a group off and setting up again takes its keys back, and
--     takes back nothing that is not this plugin's
--
-- The keypresses are made by calling the mapping's own callback rather than by
-- feeding keys, because what these are about is which key carries which
-- action.
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')
    local constants = require('cash.constants')
    local keymaps = require('cash.keymaps')

    local functionKeys = constants.functionKeys

    -- every key mapKeys can put something on
    local everyKey = { '?' }
    vim.list_extend(everyKey, functionKeys.registers)
    table.insert(everyKey, functionKeys.underCursor)

    ---@param mapKeys? table what to hand setup, or nil for the defaults
    local function fresh(mapKeys)
        vim.cmd('silent! tabonly')
        vim.cmd('silent! only')
        vim.opt.ignorecase = false

        -- a mapping left by an earlier case would survive setup, and these
        -- tests are about what setup itself put on a key
        for _, key in ipairs(everyKey) do
            pcall(vim.keymap.del, 'n', key)
        end

        cash.setup(mapKeys and { mapKeys = mapKeys } or {})
        cash.resetCashRegisters()
        vim.api.nvim_buf_set_lines(
            0,
            0,
            -1,
            false,
            { 'foo bar baz', 'bar and foo again' }
        )
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.v.hlsearch = 1
    end

    -- fills a cash register without leaving the working one behind
    local function store(index, pattern)
        local previous = cash.state.currentIndex
        cash.setCashRegister(index)
        cash.setSearch(pattern)
        cash.setCashRegister(previous)
    end

    local function working()
        return cash.state.currentIndex
    end

    ---@return table whatever maparg handed back
    local function mapping(key)
        return vim.fn.maparg(key, 'n', false, true) --[[@as table]]
    end

    -- runs whatever is mapped to a key. Every mapping these tests look at is a
    -- lua callback, so there is one to call
    local function press(key)
        local keymap = mapping(key)
        assert(keymap.callback ~= nil, key .. ' has no callback')
        keymap.callback()
    end

    -- how many of the ten function keys are this plugin's
    local function ours()
        local count = 0
        for _, key in ipairs(everyKey) do
            if key ~= '?' and keymaps.isOurs(mapping(key)) then
                count = count + 1
            end
        end
        return count
    end

    -- names every function key that is mapped at all
    local function stillMapped()
        local found = {}
        for _, key in ipairs(everyKey) do
            if key ~= '?' and next(mapping(key)) ~= nil then
                table.insert(found, key)
            end
        end
        return found
    end

    ----------------------------------------------------------------------

    h.group('both groups on, which is the default')

    fresh()

    h.check(
        '? brings up the chooser',
        keymaps.isOurs(mapping('?')),
        vim.inspect(mapping('?').desc)
    )

    h.check(
        'and all ten function keys are mapped alongside it',
        ours() == 10,
        ours() .. " of 10 are this plugin's"
    )

    local described = 0
    for index, key in ipairs(functionKeys.registers) do
        local desc = mapping(key).desc
        -- the number is in the description, so that which-key and :nmap say
        -- which cash register the key is for
        if
            type(desc) == 'string'
            and desc:find(tostring(index), 1, true) ~= nil
        then
            described = described + 1
        end
    end

    h.check(
        'each of the nine names its cash register',
        described == 9,
        described .. ' of 9 say their number'
    )

    h.group('what the function keys do')

    fresh()
    press(functionKeys.registers[4])

    h.check(
        '<F4> works in cash register 4',
        working() == 4,
        'working in ' .. working()
    )

    press(functionKeys.registers[9])

    h.check(
        'and <F9> works in cash register 9',
        working() == 9,
        'working in ' .. working()
    )

    fresh()
    cash.setSearch('foo')
    store(2, 'bar')
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    press(functionKeys.underCursor)

    h.check(
        '<F10> works in the cash register under the cursor',
        working() == 2,
        'working in ' .. working()
    )

    -- no chooser for these: a key that names a cash register has nothing to
    -- ask about, so nothing should be waiting for a keypress
    fresh()
    local windowsBefore = #vim.api.nvim_list_wins()
    press(functionKeys.registers[3])

    h.check(
        'and none of them opens the chooser',
        #vim.api.nvim_list_wins() == windowsBefore and working() == 3,
        #vim.api.nvim_list_wins() .. ' windows, working in ' .. working()
    )

    h.group('questionMark switched off')

    fresh({ questionMark = false })

    h.check(
        '? is left alone, so it is a backward search again',
        next(mapping('?')) == nil,
        vim.inspect(mapping('?'))
    )

    h.check(
        'while the function keys are untouched by it',
        ours() == 10,
        ours() .. " of 10 are this plugin's"
    )

    h.group('functionKeys switched off')

    fresh({ functionKeys = false })

    h.check(
        'none of the ten is mapped',
        #stillMapped() == 0,
        'still mapped: ' .. table.concat(stillMapped(), ', ')
    )

    h.check(
        'while ? still brings up the chooser',
        keymaps.isOurs(mapping('?')),
        vim.inspect(mapping('?').desc)
    )

    h.group('both switched off')

    fresh({ functionKeys = false, questionMark = false })

    h.check(
        'nothing this option covers is mapped',
        next(mapping('?')) == nil and #stillMapped() == 0,
        'still mapped: '
            .. table.concat(stillMapped(), ', ')
            .. ' '
            .. vim.inspect(mapping('?'))
    )

    h.check(
        'and :Cash use still switches cash registers',
        (function()
            cash.setCashRegister(1)
            vim.cmd('Cash use 5')
            return working() == 5
        end)(),
        'working in ' .. working()
    )

    h.group('switching a group off after it was on')

    -- setup is what applies the option, and a plugin manager hands it the same
    -- table on every reload, so a group that has been switched off has to give
    -- its keys back rather than leaving them behind switching cash registers
    fresh()
    cash.setup({ mapKeys = { functionKeys = false } })

    h.check(
        'the function keys are given back',
        #stillMapped() == 0,
        'still mapped: ' .. table.concat(stillMapped(), ', ')
    )

    cash.setup({})

    h.check(
        'and switching the group back on maps them again',
        ours() == 10,
        ours() .. " of 10 are this plugin's"
    )

    fresh()
    cash.setup({ mapKeys = { questionMark = false } })

    h.check(
        '? is given back the same way',
        next(mapping('?')) == nil,
        vim.inspect(mapping('?'))
    )

    -- a key something else has taken since is that something else's, whatever
    -- this plugin used to have on it
    fresh()
    vim.keymap.del('n', '<F5>')
    vim.keymap.set('n', '<F5>', '<Nop>', { desc = 'somebody else' })
    cash.setup({ mapKeys = { functionKeys = false } })

    h.check(
        'a foreign mapping on a released key is left where it is',
        mapping('<F5>').desc == 'somebody else',
        vim.inspect(mapping('<F5>').desc)
    )

    h.group('what setup refuses')

    h.check(
        'a key mapKeys does not have',
        not pcall(cash.setup, { mapKeys = { fKeys = true } })
    )

    h.check(
        'and a value of the wrong type',
        ---@diagnostic disable-next-line: assign-type-mismatch
        not pcall(cash.setup, { mapKeys = { functionKeys = 'yes' } })
    )

    h.check(
        'while mapKeys itself has to be a table',
        ---@diagnostic disable-next-line: assign-type-mismatch
        not pcall(cash.setup, { mapKeys = true })
    )

    -- put the plugin back the way the next spec expects to find it
    fresh()
end
