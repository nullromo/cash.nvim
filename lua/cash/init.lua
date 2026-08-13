local cashModule = require('cash.cash')
local highlights = require('cash.highlights')
local keymaps = require('cash.keymaps')
local options = require('cash.options')

-- main setup function for Cash.nvim
cashModule.setup = function(opts)
    -- make sure options is not nil
    opts = opts or {}

    -- set default options if not already set
    opts.centerAfterSearch = opts.centerAfterSearch
        or options.defaultOptions.centerAfterSearch
    opts.colors = opts.colors or options.defaultOptions.colors
    opts.colors.defaultFG = opts.colors.defaultFG
        or options.defaultOptions.colors.defaultFG
    opts.colors.defaultBG = opts.colors.defaultBG
        or options.defaultOptions.colors.defaultBG
    opts.colors.highlightColors = opts.colors.highlightColors
        or options.defaultOptions.colors.highlightColors
    opts.disableStarPoundJump = opts.disableStarPoundJump
        or options.defaultOptions.disableStarPoundJump
    opts.respectHLSearch = opts.respectHLSearch
        or options.defaultOptions.respectHLSearch

    -- validate options
    options.validateOptions(opts)

    -- set options
    cashModule.opts = opts

    -- set up highlight groups
    highlights.setup(opts.colors)

    -- set initial plugin state
    cashModule.initializeData()

    -- subscribe to editor events now that there is state for them to update
    cashModule.setUpAutocmds()

    -- set up keymaps
    keymaps.setUpKeymaps(cashModule)

    -- bring any windows that are already open in line with the state
    cashModule.updateHighlights()

    -- enable hlsearch
    if not opts.respectHLSearch then
        vim.opt.hlsearch = true
    end
end

-- export module
return cashModule
