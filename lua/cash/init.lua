local cashModule = require('cash.cash')
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
    for i = 1, 9 do
        local bg = opts.colors.highlightColors[i].bg or opts.colors.defaultBG
        local fg = opts.colors.highlightColors[i].fg or opts.colors.defaultFG
        vim.cmd.highlight(
            'CashRegister' .. i,
            'guibg=' .. bg .. ' guifg=' .. fg
        )
    end

    -- set initial plugin state
    cashModule.initializeData()

    -- set up keymaps
    keymaps.setUpKeymaps(cashModule)

    -- enable hlsearch
    if not opts.respectHLSearch then
        vim.opt.hlsearch = true
    end
end

-- export module
return cashModule
