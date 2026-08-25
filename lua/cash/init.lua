local cashModule = require('cash.cash')
local highlights = require('cash.highlights')
local keymaps = require('cash.keymaps')
local options = require('cash.options')

-- main setup function for Cash.nvim
---@param opts? cash.Options anything left out keeps its default
cashModule.setup = function(opts)
    -- check the user's options and fill in the defaults
    opts = options.resolve(opts)

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

    -- and draw the indicator, or take away the one a previous setup drew
    cashModule.updateIndicator()

    -- enable hlsearch
    if not opts.respectHLSearch then
        vim.opt.hlsearch = true
    end
end

-- export module
return cashModule
