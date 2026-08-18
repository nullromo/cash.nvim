-- Tests for what setup accepts.
--
-- Most of what options.resolve does is covered by cash_spec, which asks what
-- the resolved options make the plugin do. What is here is the part with no
-- visible effect when it works: an option written under a name this plugin
-- used to have still reaching the option it turned into, so that upgrading
-- does not break Neovim on startup for anyone who has not read the release
-- notes yet.
--
-- See CONTEXT.md for the vocabulary used here.

return function(h)
    local cash = require('cash')
    local options = require('cash.options')

    -- vim.deprecate warns once per message for the life of the Neovim it runs
    -- in, so a test that asserts on the warning has to be the first thing to
    -- ask for it. It is not asserted on here at all: what these tests are
    -- about is the value arriving, and the warning is neovim's to format
    local function resolve(opts)
        return options.resolve(opts)
    end

    h.group('renamed options')

    local resolved = resolve({ prompt = { style = 'strip' } })

    h.check(
        'a value written under an old name reaches the new one',
        resolved.chooser.style == 'strip',
        'resolved to ' .. tostring(resolved.chooser.style)
    )

    local leftOver = {}
    for oldName in pairs(options.renamedOptions) do
        if resolved[oldName] ~= nil then
            table.insert(leftOver, oldName)
        end
    end

    h.check(
        'and no old name is left in the result',
        #leftOver == 0,
        'still there: ' .. table.concat(leftOver, ', ')
    )

    h.check(
        'everything else still gets its default',
        resolved.chooser.position == 'center'
            and resolved.drawer.border == 'rounded'
    )

    local both = resolve({
        ui = { detailPane = true },
        drawer = { detailPane = false },
    })

    h.check(
        'the new name wins when a config has both',
        both.drawer.detailPane == false,
        'resolved to ' .. tostring(both.drawer.detailPane)
    )

    local caller = { prompt = { style = 'none' } }
    resolve(caller)

    h.check(
        "the caller's own options table is not rewritten",
        vim.deep_equal(caller, { prompt = { style = 'none' } }),
        'became ' .. vim.inspect(caller)
    )

    h.check(
        'a value written under an old name is still checked',
        not pcall(resolve, { prompt = { style = 'asdf' } })
    )

    h.check(
        'and a name this plugin never had is still rejected',
        not pcall(resolve, { chooserr = {} })
    )

    for oldName, renamed in pairs(options.renamedOptions) do
        h.check(
            'opts.' .. oldName .. ' names an option that exists',
            options.defaultOptions[renamed.newName] ~= nil,
            'points at opts.' .. renamed.newName
        )

        h.check(
            'and is promised to last until ' .. renamed.removedIn,
            vim.version.lt(cash.version, renamed.removedIn),
            'this is Cash.nvim ' .. cash.version .. ', so it is already due'
        )
    end

    h.group('the version')

    h.check(
        'is a semantic version',
        vim.version.parse(cash.version) ~= nil,
        'is ' .. vim.inspect(cash.version)
    )

    -- put the plugin back the way the next spec expects to find it
    cash.setup({})
    cash.resetCashRegisters()
end
