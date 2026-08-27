-- Tests for carrying the cash registers from one neovim to the next.
--
-- The shada file itself is not exercised here: this suite runs under nvim -l,
-- which switches shada off entirely, and one neovim cannot outlive itself in
-- any case. What is testable in one process is everything either side of the
-- file -- the shape that goes into g:CASH_NVIM, the checking that shape gets on
-- the way back, and what a restore does to the cash registers and the search
-- register -- and that is what is here. Shada's own part is the ! flag, which
-- neovim ships on by default.
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')
    local persist = require('cash.persist')

    -- a module state shaped like the real one. entries is a map of cash
    -- register index to { pattern, includeInSearch }; the rest come out empty
    local function stateWith(entries, index)
        local cashRegisters = {}
        for i = 1, 9 do
            cashRegisters[i] = { pattern = '', includeInSearch = false }
        end
        for i, entry in pairs(entries) do
            cashRegisters[i] =
                { pattern = entry[1], includeInSearch = entry[2] }
        end

        return { currentIndex = index or 1, cashRegisters = cashRegisters }
    end

    -- every cash register as "index:pattern:include", so a whole set can be
    -- compared as one string
    local function describe(cashRegisters)
        local out = {}
        for i = 1, 9 do
            table.insert(
                out,
                i
                    .. ':'
                    .. cashRegisters[i].pattern
                    .. ':'
                    .. tostring(cashRegisters[i].includeInSearch)
            )
        end
        return table.concat(out, ' ')
    end

    local function matchesIn(windowID)
        return h.litSummary(windowID)
    end

    -- a single empty window with the plugin freshly set up. Deliberately does
    -- not reset the cash registers afterwards, since a restore is the thing
    -- under test
    local function fresh(opts)
        vim.cmd('silent! tabonly')
        vim.cmd('silent! only')
        vim.opt.ignorecase = false
        cash.setup(opts or {})
        return vim.fn.win_getid()
    end

    -- collects what the plugin would have told the user
    local function notifications(body)
        local real = vim.notify
        local said = {}
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.notify = function(message)
            table.insert(said, message)
        end
        local ok, err = pcall(body)
        vim.notify = real
        if not ok then
            error(err)
        end
        return said
    end

    local savedShada = vim.o.shada

    ----------------------------------------------------------------------

    h.group('the shada variable')

    do
        -- shada only carries a global variable whose name is written in
        -- capitals with no lowercase letter in it. Getting this wrong makes
        -- every other test here pass and the feature do nothing
        h.check(
            'the variable name is one shada will carry',
            persist.variableName:match('^%u[%u%d_]*$') ~= nil,
            'got [' .. persist.variableName .. ']'
        )

        vim.g[persist.variableName] = nil
        persist.save(stateWith({ [2] = { 'foo', true } }, 2))
        h.check(
            'save writes the variable shada is going to look at',
            vim.g[persist.variableName] ~= nil
        )

        -- the value is read back out of vim.g rather than compared against the
        -- table that went in, because that trip through vimscript is the same
        -- conversion shada makes. Anything that does not survive it is stored
        -- wrongly, however good it looked on the way in
        local restored = persist.load()
        h.check(
            'a cash register survives the trip through vim.g',
            restored ~= nil
                and describe(restored.cashRegisters)
                    == describe(
                        stateWith({ [2] = { 'foo', true } }).cashRegisters
                    ),
            restored and describe(restored.cashRegisters) or 'nothing restored'
        )

        h.check(
            'the working cash register survives the trip through vim.g',
            restored ~= nil and restored.currentIndex == 2
        )

        persist.save(stateWith({ [1] = { [[\v(foo|bar)\ze\s+]], false } }))
        h.check(
            'a pattern full of backslashes survives the trip through vim.g',
            persist.load().cashRegisters[1].pattern == [[\v(foo|bar)\ze\s+]],
            'got [' .. persist.load().cashRegisters[1].pattern .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('reading a stored value back')

    do
        h.check(
            'nothing stored restores nothing',
            persist.deserialize(nil) == nil
        )

        h.check(
            'a value that is not a table restores nothing',
            persist.deserialize('CASH_NVIM') == nil
        )

        h.check(
            'a version this plugin does not know restores nothing',
            persist.deserialize({
                version = persist.formatVersion + 1,
                index = 1,
                registers = {},
            }) == nil
        )

        h.check(
            'a stored value with no cash registers in it restores nothing',
            persist.deserialize({ version = persist.formatVersion, index = 1 })
                == nil
        )

        -- one bad entry is worth eight good ones, so it becomes an empty cash
        -- register rather than throwing the set away
        local patched = persist.deserialize({
            version = persist.formatVersion,
            index = 1,
            registers = {
                { pattern = 'one', includeInSearch = false },
                { pattern = 42, includeInSearch = false },
                'not a cash register at all',
            },
        })
        h.check(
            'a malformed cash register is emptied, not fatal',
            patched ~= nil
                and patched.cashRegisters[1].pattern == 'one'
                and patched.cashRegisters[2].pattern == ''
                and patched.cashRegisters[3].pattern == '',
            patched and describe(patched.cashRegisters) or 'nothing restored'
        )

        h.check(
            'the cash registers a short stored list never reached are empty',
            patched ~= nil and patched.cashRegisters[9].pattern == ''
        )

        local badIndex = persist.deserialize({
            version = persist.formatVersion,
            index = 27,
            registers = {},
        })
        h.check(
            'a stored working cash register that names no cash register '
                .. 'falls back to 1',
            badIndex ~= nil and badIndex.currentIndex == 1
        )

        -- vim.g hands booleans back as booleans, so anything else here was put
        -- there by vimscript or by a person
        local switches = persist.deserialize({
            version = persist.formatVersion,
            index = 1,
            registers = {
                { pattern = 'a', includeInSearch = true },
                { pattern = 'b', includeInSearch = 1 },
                { pattern = 'c', includeInSearch = 0 },
                { pattern = 'd', includeInSearch = 'yes' },
                { pattern = 'e' },
            },
        })
        h.check(
            'include-in-search reads back as on only when it is plainly on',
            switches ~= nil
                and switches.cashRegisters[1].includeInSearch == true
                and switches.cashRegisters[2].includeInSearch == true
                and switches.cashRegisters[3].includeInSearch == false
                and switches.cashRegisters[4].includeInSearch == false
                and switches.cashRegisters[5].includeInSearch == false,
            switches ~= nil and describe(switches.cashRegisters)
                or 'nothing was deserialized'
        )
    end

    ----------------------------------------------------------------------

    h.group('restoring at startup')

    do
        -- what the last neovim left behind: three patterns, one of them
        -- included, and cash register 3 as the working one
        local previousSession = stateWith({
            [1] = { 'alpha', false },
            [3] = { 'gamma', false },
            [5] = { 'epsilon', true },
        }, 3)

        vim.fn.setreg('/', 'gamma')
        persist.save(previousSession)

        -- shada puts the search register back as it was, so this is what the
        -- next neovim starts with
        vim.fn.setreg('/', 'gamma')
        local window = fresh()

        h.check(
            'the nine cash registers come back as they were left',
            describe(cash.state.cashRegisters)
                == describe(previousSession.cashRegisters),
            'got [' .. describe(cash.state.cashRegisters) .. ']'
        )

        h.check(
            'the working cash register comes back too',
            cash.state.currentIndex == 3,
            'got ' .. cash.state.currentIndex
        )

        h.check(
            'include-in-search comes back with its cash register',
            cash.state.cashRegisters[5].includeInSearch == true
        )

        h.check(
            'the search register still mirrors the working cash register',
            vim.fn.getreg('/') == 'gamma',
            'got [' .. vim.fn.getreg('/') .. ']'
        )

        -- a restored cash register is a cash register like any other, so the
        -- two that are not the working one are drawn by matches
        h.check(
            'restored cash registers are highlighted',
            matchesIn(window)
                == 'CashRegister1=\\Calpha CashRegister5=\\Cepsilon',
            'got [' .. matchesIn(window) .. ']'
        )
    end

    do
        -- nvim +/pattern and nvim -c /pattern both run before VimEnter, so by
        -- the time the restore happens the cursor is already sitting on a
        -- match for a pattern that is in no cash register
        vim.fn.setreg('/', 'gamma')
        persist.save(stateWith({ [3] = { 'gamma', false } }, 3))

        vim.fn.setreg('/', 'typedAtStartup')
        fresh()

        h.check(
            'a search made during startup lands in the working cash register',
            cash.state.cashRegisters[3].pattern == 'typedAtStartup',
            'got [' .. cash.state.cashRegisters[3].pattern .. ']'
        )

        h.check(
            'a search made during startup keeps the search register it set',
            vim.fn.getreg('/') == 'typedAtStartup',
            'got [' .. vim.fn.getreg('/') .. ']'
        )
    end

    do
        -- shada does not record an empty search pattern: it leaves the last
        -- non-empty one sitting in the file. So a session that ended with
        -- nothing being searched for -- :Cash reset and :Cash clear both leave
        -- that -- comes back to a stale pattern from some earlier session, and
        -- a difference no longer means anyone searched during startup. Reading
        -- it as one would put that stale pattern straight back into the cash
        -- register the user had just emptied
        vim.fn.setreg('/', '')
        persist.save(stateWith({}, 1))

        vim.fn.setreg('/', 'staleFromAnEarlierSession')
        fresh()

        h.check(
            'a stale search pattern is not mistaken for a startup search',
            cash.state.cashRegisters[1].pattern == '',
            'got [' .. cash.state.cashRegisters[1].pattern .. ']'
        )

        h.check(
            'and it does not survive as the search register either',
            vim.fn.getreg('/') == '',
            'got [' .. vim.fn.getreg('/') .. ']'
        )
    end

    do
        -- the working cash register can perfectly well be empty, and then the
        -- search register is empty with it rather than holding the last thing
        -- anything happened to put there
        vim.fn.setreg('/', '')
        persist.save(stateWith({ [2] = { 'beta', false } }, 4))

        vim.fn.setreg('/', '')
        fresh()

        h.check(
            'an empty working cash register empties the search register',
            vim.fn.getreg('/') == '',
            'got [' .. vim.fn.getreg('/') .. ']'
        )

        h.check(
            'the other cash registers are restored around it',
            cash.state.cashRegisters[2].pattern == 'beta'
                and cash.state.currentIndex == 4
        )
    end

    do
        vim.g[persist.variableName] = nil
        vim.fn.setreg('/', '')
        fresh()

        h.check(
            'a first run with nothing stored starts empty',
            describe(cash.state.cashRegisters)
                    == describe(stateWith({}).cashRegisters)
                and cash.state.currentIndex == 1,
            'got [' .. describe(cash.state.cashRegisters) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('switching persistence off')

    do
        persist.save(stateWith({ [7] = { 'stored', true } }, 7))
        vim.fn.setreg('/', '')
        fresh({ persistCashRegisters = false })

        h.check(
            'nothing is restored when persistence is off',
            cash.state.cashRegisters[7].pattern == ''
                and cash.state.currentIndex == 1,
            'got [' .. describe(cash.state.cashRegisters) .. ']'
        )

        -- and the stored value is left exactly as it was, rather than being
        -- overwritten by a session that was told not to take part
        cash.setSearch('typedThisSession')
        cash.saveCashRegisters()
        h.check(
            'nothing is saved when persistence is off',
            persist.load().cashRegisters[7].pattern == 'stored',
            'got [' .. describe(persist.load().cashRegisters) .. ']'
        )
    end

    ----------------------------------------------------------------------

    h.group('quitting before the cash registers were put back')

    do
        -- a neovim that exits during startup never reaches VimEnter, so the
        -- restore never runs and the cash registers are still the empty set
        -- setup made. nvim --headless "+Lazy! sync" +qa is exactly that shape,
        -- and so is every other scripted nvim that loads the user's config and
        -- quits, so this is not a rare case -- and a session that never read
        -- the drawer must not write one.
        --
        -- The state is put back by hand because this suite runs with
        -- v:vim_did_enter already 1, where setup restores there and then, so
        -- there is no way to reach an unrestored session honestly
        persist.save(stateWith({ [4] = { 'stored', true } }, 4))
        fresh()
        cash.initializeData()
        cash.restoreHasRun = false

        cash.saveCashRegisters()
        h.check(
            'nothing is saved when the restore never ran',
            persist.load().cashRegisters[4].pattern == 'stored'
                and persist.load().currentIndex == 4,
            'got ['
                .. describe(persist.load().cashRegisters)
                .. '] at '
                .. persist.load().currentIndex
        )

        -- and the same session saves normally once the restore has happened,
        -- so the check above is holding back only what it means to
        cash.restoreHasRun = true
        cash.setSearch('typedThisSession')
        cash.saveCashRegisters()
        h.check(
            'saving resumes once the restore has run',
            persist.load().cashRegisters[1].pattern == 'typedThisSession',
            'got [' .. describe(persist.load().cashRegisters) .. ']'
        )
    end

    do
        -- :Cash reset empties the cash registers through initializeData, which
        -- must not read as "this session never restored". The empty drawer is
        -- what the user asked for, and it is what should be waiting next time
        persist.save(stateWith({ [2] = { 'stored', false } }, 2))
        fresh()
        cash.resetCashRegisters()
        cash.saveCashRegisters()

        h.check(
            'a drawer emptied on purpose is still saved',
            persist.load().cashRegisters[2].pattern == '',
            'got [' .. describe(persist.load().cashRegisters) .. ']'
        )
    end

    do
        -- a first run has nothing stored, and the restore finding nothing is
        -- still a restore: what this session does is its own and goes out on
        -- the way down
        vim.g[persist.variableName] = nil
        vim.fn.setreg('/', '')
        fresh()
        cash.setSearch('firstEverSearch')
        cash.saveCashRegisters()

        local stored = persist.load()
        h.check(
            'a first run with nothing stored still saves what it did',
            stored ~= nil
                and stored.cashRegisters[1].pattern == 'firstEverSearch',
            stored ~= nil and 'got [' .. describe(stored.cashRegisters) .. ']'
                or 'nothing was stored'
        )
    end

    ----------------------------------------------------------------------

    h.group('shada that cannot carry the cash registers')

    do
        h.check(
            'shada switched off is noticed',
            persist.shadaIsOff(),
            'this suite runs under nvim -l, which sets shadafile=NONE'
        )

        vim.o.shada = "!,'100,<50,s10,h"
        h.check('the ! flag is found', persist.carriesGlobals())

        vim.o.shada = "'100,<50,s10,h"
        h.check(
            'a shada with no ! flag is noticed',
            not persist.carriesGlobals()
        )

        -- a ! inside a path is not the flag, which is why the items are
        -- compared rather than the whole string searched
        vim.o.shada = "'100,r/tmp!/"
        h.check(
            'a ! inside an r item does not pass for the flag',
            not persist.carriesGlobals()
        )

        vim.o.shada = savedShada
    end

    do
        -- shada switched off altogether is a deliberate act by whoever started
        -- this neovim, and is not something to complain about
        local said = notifications(function()
            persist.warnIfUnavailable()
        end)
        h.check(
            'shada switched off says nothing',
            #said == 0,
            'said [' .. table.concat(said, ' / ') .. ']'
        )

        -- shada kept, but with the one flag this needs taken out of it, is a
        -- configuration that has given up global variables without noticing
        local savedShadaFile = vim.o.shadafile
        vim.o.shadafile = ''
        vim.o.shada = "'100,<50,s10,h"
        said = notifications(function()
            persist.warnIfUnavailable()
        end)
        vim.o.shadafile = savedShadaFile
        vim.o.shada = savedShada

        h.check(
            'a shada with no ! flag is complained about once',
            #said == 1 and said[1]:find('!', 1, true) ~= nil,
            'said [' .. table.concat(said, ' / ') .. ']'
        )
    end

    ----------------------------------------------------------------------

    -- the suite shares one neovim, so the stored value goes away rather than
    -- being restored into whatever runs next
    vim.g[persist.variableName] = nil
    vim.fn.setreg('/', '')
    cash.setup({})
    cash.resetCashRegisters()
end
