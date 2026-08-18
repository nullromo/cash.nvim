-- Tests for what :checkhealth cash reports.
--
-- The health check exists because this plugin's failures are quiet ones, so
-- what is worth testing is that each quiet failure gets a loud line. Every
-- test here breaks something on purpose and then asks the health check whether
-- it noticed.
--
-- vim.health is swapped for a collector rather than driving :checkhealth and
-- reading the buffer back. The buffer is neovim's rendering of the report, and
-- what the report says is this plugin's business while how it is drawn is not.
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')
    local health = require('cash.health')
    local persist = require('cash.persist')

    -- one line of the report
    ---@class cash.HealthEntry
    ---@field level string start, ok, info, warn or error
    ---@field message string
    ---@field advice any whatever was passed alongside it

    -- runs the health check with vim.health standing in for the real one, and
    -- hands back everything it reported. The real one is put back even when
    -- the check throws, since a broken check must not take the rest of the
    -- suite with it
    ---@return cash.HealthEntry[]
    local function report()
        local entries = {}

        local record = function(level)
            return function(message, advice)
                table.insert(entries, {
                    level = level,
                    message = tostring(message),
                    advice = advice,
                })
            end
        end

        local real = vim.health
        vim.health = {
            start = record('start'),
            ok = record('ok'),
            info = record('info'),
            warn = record('warn'),
            error = record('error'),
        } --[[@as any]]

        local ok, err = pcall(health.check)

        vim.health = real

        if not ok then
            error(err)
        end

        return entries
    end

    -- the first entry at the given level whose message contains the given
    -- text, or nil. Plain find, because the things being looked for are full
    -- of pattern characters: *, #, g* and ? are four of the keys
    ---@param entries cash.HealthEntry[]
    ---@param level string
    ---@param text string
    ---@return cash.HealthEntry|nil
    local function find(entries, level, text)
        for _, entry in ipairs(entries) do
            if entry.level == level and entry.message:find(text, 1, true) then
                return entry
            end
        end

        return nil
    end

    -- the advice that came with an entry, as one string, so that a test can
    -- ask what the user was told to do about it
    ---@param entry cash.HealthEntry|nil
    ---@return string
    local function advice(entry)
        if entry == nil or entry.advice == nil then
            return ''
        end

        if type(entry.advice) == 'table' then
            return table.concat(entry.advice, ' ')
        end

        return tostring(entry.advice)
    end

    -- a plugin freshly set up, with nothing left over from another spec on the
    -- keys this one takes away
    local function fresh(opts)
        for _, key in ipairs({ '*', '#', 'g*', 'g#', 'n', 'N', '?' }) do
            pcall(vim.keymap.del, 'n', key)
        end
        vim.g[persist.variableName] = nil
        vim.opt.termguicolors = true
        cash.setup(opts or {})
        cash.resetCashRegisters()
    end

    h.group('a healthy setup')

    fresh()
    local healthy = report()

    h.check(
        'reports which Cash.nvim this is',
        find(healthy, 'info', 'Cash.nvim ' .. cash.version) ~= nil
    )

    h.check(
        'reports the neovim version',
        find(healthy, 'ok', 'Neovim ' .. vim.version().major) ~= nil
    )

    h.check(
        'reports termguicolors',
        find(healthy, 'ok', "'termguicolors' is on") ~= nil
    )

    h.check('reports that setup has run', find(healthy, 'ok', 'setup') ~= nil)

    h.check(
        'says so when every option is at its default',
        find(healthy, 'ok', 'default') ~= nil
    )

    for _, key in ipairs({ '?', '*', '#', 'g*', 'g#', 'n', 'N' }) do
        h.check(
            key .. " is reported as this plugin's",
            find(healthy, 'ok', key .. " is Cash.nvim's") ~= nil
        )
    end

    h.check(
        "the command line <CR> mapping is reported as this plugin's",
        find(healthy, 'ok', '<CR> in the command line') ~= nil
    )

    h.check(
        'the nine highlight groups are all there',
        find(healthy, 'ok', 'CashRegister1 to CashRegister9') ~= nil
    )

    h.check(
        'nothing is reported as wrong',
        find(healthy, 'warn', '') == nil and find(healthy, 'error', '') == nil,
        'a healthy setup reported: '
            .. vim.inspect(vim.tbl_map(
                function(entry)
                    return entry.level .. ' ' .. entry.message
                end,
                vim.tbl_filter(function(entry)
                    return entry.level == 'warn' or entry.level == 'error'
                end, healthy)
            ))
    )

    h.group('a key something else has taken')

    fresh()
    vim.keymap.set('n', 'n', 'nzz', { desc = 'nvim-hlslens: next match' })
    local taken = report()
    local takenEntry = find(taken, 'info', 'n is mapped by something else')

    h.check('is reported', takenEntry ~= nil)

    h.check(
        'and the report names what took it',
        takenEntry ~= nil
            and takenEntry.message:find('nvim-hlslens', 1, true) ~= nil,
        'got: ' .. (takenEntry and takenEntry.message or 'nothing')
    )

    h.check(
        'and says which call keeps it working',
        takenEntry ~= nil
            and takenEntry.message:find('cash.nextMatch()', 1, true) ~= nil
    )

    h.check(
        'and says what is lost if it does not make that call',
        takenEntry ~= nil
            and takenEntry.message:find('include-in-search', 1, true) ~= nil
    )

    h.check(
        'and points at the command that names the culprit',
        takenEntry ~= nil
            and takenEntry.message:find(':verbose nmap n', 1, true) ~= nil
    )

    h.check(
        'while the keys nobody took are still reported as ours',
        find(taken, 'ok', "N is Cash.nvim's") ~= nil
    )

    -- The check knows which mapping is on a key. It cannot know what that
    -- mapping does, and the two configurations below are both ones where the
    -- key is not Cash.nvim's and everything works anyway. Calling either of
    -- them broken is worse than saying nothing, because the second is what
    -- |cash-tip-after-jump| tells people to write
    h.group('a key that has been taken but still calls this plugin')

    fresh()
    vim.keymap.set('n', 'n', function()
        cash.nextMatch()
        vim.cmd('normal! zt')
    end)
    local viaApi = report()

    h.check(
        'is not called broken',
        find(viaApi, 'warn', 'n ') == nil and find(viaApi, 'error', 'n ') == nil,
        'the documented tip in cash-tip-after-jump reported: '
            .. vim.inspect(vim.tbl_map(
                function(entry)
                    return entry.level .. ' ' .. entry.message
                end,
                vim.tbl_filter(function(entry)
                    return (entry.level == 'warn' or entry.level == 'error')
                        and entry.message:find('n ', 1, true) ~= nil
                end, viaApi)
            ))
    )

    h.group('a key another plugin has wrapped')

    fresh()
    local wrapped = vim.fn.maparg('*', 'n', false, true) --[[@as table]]
    vim.keymap.set('n', '*', function()
        wrapped.callback()
    end, { desc = 'some-other-plugin: star' })
    local viaWrapper = report()

    h.check(
        'is not called broken either',
        find(viaWrapper, 'warn', '*') == nil
            and find(viaWrapper, 'error', '*') == nil
    )

    h.check(
        'and is still reported, so that the conflict is visible',
        find(viaWrapper, 'info', '* is mapped by something else') ~= nil
    )

    -- every :help tag the mapping report offers has to be a tag that exists.
    -- They are only ever printed, so a renamed section would go unnoticed
    -- until somebody followed one
    h.group('the help tags the mapping report points at')

    fresh()
    for _, key in ipairs({ '?', '*', '#', 'g*', 'g#', 'n', 'N' }) do
        vim.keymap.set('n', key, '<Nop>', { desc = 'a stand-in' })
    end
    vim.keymap.set('c', '<CR>', '<CR>', { desc = 'a stand-in' })
    local everyKeyTaken = report()

    -- doc/tags is generated by :helptags rather than kept in the repository,
    -- so it has to be built before it can be read. It is usually already
    -- sitting there on a machine this plugin has been used on, and never on a
    -- fresh checkout, which is the whole difference between this passing
    -- locally and failing in CI
    vim.cmd.helptags(h.pluginRoot .. '/doc')

    local tags = {}
    for _, line in
        ipairs(vim.fn.readfile(h.pluginRoot .. '/doc/tags') --[[@as string[] ]])
    do
        tags[vim.split(line, '\t')[1]] = true
    end

    local referenced, missing = 0, {}
    for _, entry in ipairs(everyKeyTaken) do
        for tag in entry.message:gmatch(':help ([^%s]+)') do
            referenced = referenced + 1
            if not tags[tag] then
                table.insert(missing, tag)
            end
        end
    end

    h.check(
        'the report points at one for every key',
        referenced == 8,
        'found ' .. referenced .. ' of 8'
    )

    h.check(
        'and every one of them is a real tag',
        #missing == 0,
        'not in doc/tags: ' .. table.concat(missing, ', ')
    )

    -- the stand-ins would otherwise still be sitting on the keys
    fresh()
    pcall(vim.keymap.del, 'c', '<CR>')
    cash.setup({})

    h.group('a key nobody has')

    fresh()
    vim.keymap.del('n', '*')
    local unmapped = report()

    h.check(
        'is reported as a warning',
        find(unmapped, 'warn', '* is not mapped') ~= nil
    )

    h.group('manageJumps switched off')

    fresh({ manageJumps = false })
    local unmanaged = report()

    h.check(
        'n and N are not asked about',
        find(unmanaged, 'warn', 'n is not mapped') == nil
            and find(unmanaged, 'ok', "n is Cash.nvim's") == nil
    )

    h.check(
        'and the report says why',
        find(unmanaged, 'info', 'manageJumps is off') ~= nil
    )

    h.check(
        'while the option shows up as a non-default',
        find(unmanaged, 'info', 'manageJumps = false') ~= nil
    )

    h.group('highlight groups a colorscheme has cleared')

    fresh()
    vim.cmd('highlight clear CashRegister4')
    vim.cmd('highlight clear CashRegister7')
    local cleared = report()
    local clearedEntry = find(cleared, 'warn', 'empty')

    h.check('are reported as a warning', clearedEntry ~= nil)

    h.check(
        'and every empty one is named',
        clearedEntry ~= nil
            and clearedEntry.message:find('CashRegister4', 1, true) ~= nil
            and clearedEntry.message:find('CashRegister7', 1, true) ~= nil,
        'got: ' .. (clearedEntry and clearedEntry.message or 'nothing')
    )

    h.check(
        'and the advice says how they got that way',
        advice(clearedEntry):find('colorscheme', 1, true) ~= nil
    )

    h.group('termguicolors switched off')

    fresh()
    vim.opt.termguicolors = false
    local noTrueColor = report()
    vim.opt.termguicolors = true

    h.check(
        'is reported as a warning',
        find(noTrueColor, 'warn', "'termguicolors' is off") ~= nil
    )

    h.group('setup that never ran')

    fresh()
    local realOpts = cash.opts
    ---@diagnostic disable-next-line: assign-type-mismatch
    cash.opts = nil
    local unconfigured = report()
    cash.opts = realOpts

    h.check(
        'is reported as an error',
        find(unconfigured, 'error', 'setup() has not been called') ~= nil
    )

    h.check(
        'and nothing after it is asked about, since it would read the options',
        find(unconfigured, 'start', 'Mappings') == nil
    )

    h.group('what the last session left behind')

    fresh()
    cash.setCashRegister(3)
    cash.setSearch('foo')
    cash.setCashRegister(1)
    vim.g[persist.variableName] = persist.serialize(cash.state)
    local stored = report()
    local storedEntry = find(stored, 'ok', 'holds a readable set')

    h.check('is reported when it can be read', storedEntry ~= nil)

    h.check(
        'and the report counts the cash registers that hold something',
        storedEntry ~= nil
            and storedEntry.message:find('1 of 9', 1, true) ~= nil,
        'got: ' .. (storedEntry and storedEntry.message or 'nothing')
    )

    fresh()
    vim.g[persist.variableName] = { version = persist.formatVersion + 99 }
    local unreadable = report()

    h.check(
        'a stored set this version cannot read is reported as a warning',
        find(unreadable, 'warn', 'cannot read') ~= nil
    )

    fresh()
    local nothingStored = report()

    h.check(
        'and nothing stored at all is reported without complaint',
        find(nothingStored, 'info', 'is empty') ~= nil
            and find(nothingStored, 'warn', 'CASH_NVIM') == nil
    )

    -- put the plugin back the way the next spec expects to find it
    fresh()
end
