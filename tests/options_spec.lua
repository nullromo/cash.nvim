-- Tests for what setup accepts.
--
-- Most of what options.resolve does is covered by cash_spec, which asks what
-- the resolved options make the plugin do. What is here is the part with no
-- visible effect when it works: a name this plugin used to have being read for
-- exactly as long as it was promised, so that upgrading neither breaks Neovim
-- on startup for anyone who has not read the release notes yet nor drags every
-- name this plugin has ever had along behind it forever.
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

    h.group('names this plugin used to have')

    -- opts.prompt and opts.ui were read until 1.0.0, and 1.0.0 has shipped.
    -- What they turned into is what a config has to write now, and the old
    -- names are back to being ones validateOptions cannot tell from a typo
    h.check(
        'opts.prompt is rejected, as its deprecation warning promised',
        not pcall(resolve, { prompt = { style = 'strip' } })
    )

    h.check(
        'and opts.ui with it',
        not pcall(resolve, { ui = { detailPane = true } })
    )

    h.check(
        'a name this plugin never had is rejected too',
        not pcall(resolve, { chooserr = {} })
    )

    h.group('renaming an option')

    -- Nothing is renamed at the moment, so migrate has no live entry to carry
    -- a value across and these checks make one up. Testing the machinery
    -- against a rename of its own is what stops the next real rename being
    -- the release that finds out whether any of this still works.
    --
    -- The real table goes back whatever the call does, since a made-up rename
    -- left behind is one every spec after this one would resolve against
    local function withRename(run)
        local real = options.renamedOptions
        options.renamedOptions = {
            oldChooser = { newName = 'chooser', removedIn = '9.0.0' },
        }
        local ok, result = pcall(run)
        options.renamedOptions = real
        return ok, result
    end

    local migrated, resolved = withRename(function()
        return resolve({ oldChooser = { style = 'strip' } })
    end)

    h.check(
        'a value written under an old name reaches the new one',
        migrated and resolved.chooser.style == 'strip',
        vim.inspect(migrated and resolved.chooser or resolved)
    )

    h.check(
        'and no old name is left in the result',
        migrated and resolved.oldChooser == nil
    )

    h.check(
        'everything else still gets its default',
        migrated
            and resolved.chooser.position == 'center'
            and resolved.drawer.border == 'rounded'
    )

    local wroteBoth, both = withRename(function()
        return resolve({
            oldChooser = { style = 'strip' },
            chooser = { style = 'none' },
        })
    end)

    h.check(
        'the new name wins when a config has both',
        wroteBoth and both.chooser.style == 'none',
        vim.inspect(wroteBoth and both.chooser or both)
    )

    local caller = { oldChooser = { style = 'none' } }
    withRename(function()
        return resolve(caller)
    end)

    h.check(
        "the caller's own options table is not rewritten",
        vim.deep_equal(caller, { oldChooser = { style = 'none' } }),
        'became ' .. vim.inspect(caller)
    )

    local checked = withRename(function()
        return resolve({ oldChooser = { style = 'asdf' } })
    end)

    h.check('a value written under an old name is still checked', not checked)

    -- and whatever is in the table for real, the next time anything is
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
