local constants = require('cash.constants')
local util = require('cash.util')

local options = {}

-- a border in any form nvim_open_win accepts: one of its names, or a list of
-- the pieces to build one from
---@alias cash.Border string | table

-- one cash register's colors. Either may be left out, and what is left out
-- falls back to colors.defaultBG or colors.defaultFG
---@class cash.HighlightColor
---@field bg? string
---@field fg? string

-- The options as the user may write them: everything optional, because
-- anything left out gets its default. This is the type to reach for when
-- annotating a config, and it is what setup takes.
--
-- cash.ResolvedOptions below is the same set of options after resolve has
-- filled in the defaults, where nothing is optional any more. The two are
-- written out separately because that difference is the whole job resolve
-- does, and every read inside the plugin is a read of the resolved shape
---@class cash.Options
---@field autoNoHighlight? boolean
---@field centerAfterSearch? boolean
---@field chooser? cash.ChooserOptions
---@field colors? cash.ColorOptions
---@field disableStarPoundJump? boolean
---@field drawer? cash.DrawerOptions
---@field manageJumps? boolean
---@field persistCashRegisters? boolean
---@field respectHLSearch? boolean

---@class cash.ChooserOptions
---@field style? cash.ChooserStyle
---@field position? cash.Position
---@field border? cash.Border

---@class cash.ColorOptions
---@field defaultBG? string
---@field defaultFG? string
---@field highlightColors? cash.HighlightColor[]

---@class cash.DrawerOptions
---@field border? cash.Border
---@field position? cash.Position
---@field detailPane? boolean

-- the options once resolve has filled in every default. What cash.opts holds,
-- and what everything inside the plugin reads
---@class cash.ResolvedOptions : cash.Options
---@field autoNoHighlight boolean
---@field centerAfterSearch boolean
---@field chooser cash.ResolvedChooserOptions
---@field colors cash.ResolvedColorOptions
---@field disableStarPoundJump boolean
---@field drawer cash.ResolvedDrawerOptions
---@field manageJumps boolean
---@field persistCashRegisters boolean
---@field respectHLSearch boolean

---@class cash.ResolvedChooserOptions
---@field style cash.ChooserStyle
---@field position cash.Position
---@field border cash.Border

---@class cash.ResolvedColorOptions
---@field defaultBG string
---@field defaultFG string
---@field highlightColors cash.HighlightColor[] always nine of them, one per
--- cash register. The count is checked in validateOptions, since a list length
--- is not something a type can carry

---@class cash.ResolvedDrawerOptions
---@field border cash.Border
---@field position cash.Position
---@field detailPane boolean

---@type cash.ResolvedOptions
options.defaultOptions = {
    -- clear every cash register's highlighting as soon as the cursor moves
    -- again. The search that turned it on moves the cursor itself, so that
    -- first move does not count
    autoNoHighlight = false,
    -- center the window on the match after every search: / and ?, * and #, a
    -- switch to another cash register, and n and N
    centerAfterSearch = true,
    -- the popup that ? brings up to choose a cash register
    chooser = {
        -- 'grid' lays the nine out like a numpad and shows what each one
        -- holds, 'strip' is one line of numbers in their colors, and 'none'
        -- keeps the plain message and no popup at all
        style = 'grid',
        -- where on screen it appears
        position = 'center',
        -- the chooser's border, in any form nvim_open_win accepts
        border = 'rounded',
    },
    -- color settings
    colors = {
        -- default colors for foreground and background (used for highlight
        -- groups where fg/bg are not specified)
        defaultBG = constants.colors.roninYellow,
        defaultFG = constants.colors.sumiInk0,
        -- define colors for highlight groups 1-9
        highlightColors = {
            { bg = constants.colors.roninYellow },
            { bg = constants.colors.springBlue },
            { bg = constants.colors.sakuraPink },
            { bg = constants.colors.springGreen },
            { bg = constants.colors.autumnYellow },
            { bg = constants.colors.oniViolet },
            { bg = constants.colors.autumnGreen },
            { bg = constants.colors.autumnRed },
            {
                bg = constants.colors.waveBlue2,
                fg = constants.colors.fujiWhite,
            },
        },
    },
    -- control whether or not using * or # from normal mode will jump to the
    -- next occurrence. Vim will jump by default; this plugin disables the jump
    -- by default
    disableStarPoundJump = true,
    -- the cash drawer, which :Cash opens
    drawer = {
        -- the drawer's border, in any form nvim_open_win accepts
        border = 'rounded',
        -- where on screen it appears
        position = 'center',
        -- whether the detail pane is already open when the drawer appears. ?
        -- toggles it either way
        detailPane = false,
    },
    -- let this plugin own n and N, so that they can move between the matches
    -- of every cash register in the search set. With one cash register in the
    -- search set -- which is the case until include-in-search is switched on
    -- somewhere -- the mapping hands straight back to vim, so n and N behave
    -- exactly as they always did. Set this to false to leave them alone
    -- entirely, at the cost of include-in-search doing nothing
    manageJumps = true,
    -- carry the cash registers from one neovim to the next in the shada file,
    -- as vim already does with the search pattern and the search history. The
    -- nine patterns, their include-in-search switches and the working cash
    -- register are all restored. Needs the ! flag in 'shada', which is there by
    -- default; without it, this says so once and does nothing
    persistCashRegisters = true,
    -- leave vim's hlsearch setting alone. This plugin overrides hlsearch by
    -- default
    respectHLSearch = false,
}

-- checks the user's options and fills in a default for everything they did
-- not specify. Returns a new table; the caller's own table is left alone
---@param opts? cash.Options
---@return cash.ResolvedOptions
options.resolve = function(opts)
    opts = opts or {}

    -- validate what the user actually wrote, so that a complaint names one of
    -- their options rather than one of ours
    options.validateOptions(opts)

    -- the defaults are deep copied first because tbl_deep_extend hands back
    -- the tables it did not have to merge, and those would be this module's
    -- own defaults, shared with whatever the caller does to the result later
    return vim.tbl_deep_extend(
        'force',
        vim.deepcopy(options.defaultOptions),
        opts
    )
end

-- throws unless every key in the given table is an option this plugin has,
-- holding a value of the right shape.
--
-- Takes a plain table rather than cash.Options, because the keys it is looking
-- for include the ones that are not options at all: that is the whole point of
-- the catch-all at the bottom, and of the two renamed options above it
---@param opts table exactly as the user wrote it
options.validateOptions = function(opts)
    for key1, value1 in pairs(opts) do
        local name1 = 'opts'
        if key1 == 'autoNoHighlight' then
            util.checkType(value1, name1 .. '.autoNoHighlight', 'boolean')
        elseif key1 == 'centerAfterSearch' then
            util.checkType(value1, name1 .. '.centerAfterSearch', 'boolean')
        elseif key1 == 'chooser' then
            util.checkType(value1, name1 .. '.chooser', 'table')
            for key2, value2 in pairs(value1) do
                local name2 = name1 .. '.chooser.' .. key2
                if key2 == 'style' then
                    util.checkOneOf(value2, name2, constants.chooserStyles)
                elseif key2 == 'position' then
                    util.checkOneOf(value2, name2, constants.positions)
                elseif key2 == 'border' then
                    util.checkBorder(value2, name2)
                else
                    error(
                        '"' .. name2 .. '" ' .. constants.invalidOptionMessage
                    )
                end
            end
        elseif key1 == 'colors' then
            util.checkType(value1, name1 .. '.colors', 'table')
            for key2, value2 in pairs(value1) do
                local name2 = name1 .. '.colors'
                if key2 == 'defaultBG' then
                    util.checkType(value2, name2 .. '.defaultBG', 'string')
                elseif key2 == 'defaultFG' then
                    util.checkType(value2, name2 .. '.defaultFG', 'string')
                elseif key2 == 'highlightColors' then
                    util.checkType(
                        value2,
                        'opts.colors.highlightColors',
                        'table'
                    )
                    -- there are 9 cash registers, so there have to be 9
                    -- colors. A shorter list would otherwise only fail later,
                    -- when something looked up a cash register that had none
                    if #value2 ~= 9 then
                        error(
                            '"opts.colors.highlightColors" must have exactly '
                                .. '9 entries for Cash.nvim'
                        )
                    end
                    for key3, value3 in ipairs(value2) do
                        local name3 = name2
                            .. '.highlightColors['
                            .. key3
                            .. ']'
                        util.checkType(value3, name3, 'table')
                        for key4, value4 in pairs(value3) do
                            if key4 == 'bg' then
                                util.checkType(value4, name3 .. '.bg', 'string')
                            elseif key4 == 'fg' then
                                util.checkType(value4, name3 .. '.fg', 'string')
                            else
                                error(
                                    '"'
                                        .. name3
                                        .. '.'
                                        .. key4
                                        .. '" '
                                        .. constants.invalidOptionMessage
                                )
                            end
                        end
                    end
                else
                    error(
                        '"opts.colors.'
                            .. key2
                            .. '" '
                            .. constants.invalidOptionMessage
                    )
                end
            end
        elseif key1 == 'disableStarPoundJump' then
            util.checkType(value1, name1 .. '.disableStarPoundJump', 'boolean')
        elseif key1 == 'drawer' then
            util.checkType(value1, name1 .. '.drawer', 'table')
            for key2, value2 in pairs(value1) do
                local name2 = name1 .. '.drawer'
                if key2 == 'border' then
                    util.checkBorder(value2, name2 .. '.border')
                elseif key2 == 'position' then
                    util.checkOneOf(
                        value2,
                        name2 .. '.position',
                        constants.positions
                    )
                elseif key2 == 'detailPane' then
                    util.checkType(value2, name2 .. '.detailPane', 'boolean')
                else
                    error(
                        '"opts.drawer.'
                            .. key2
                            .. '" '
                            .. constants.invalidOptionMessage
                    )
                end
            end
        elseif key1 == 'manageJumps' then
            util.checkType(value1, name1 .. '.manageJumps', 'boolean')
        elseif key1 == 'persistCashRegisters' then
            util.checkType(value1, name1 .. '.persistCashRegisters', 'boolean')
        elseif key1 == 'respectHLSearch' then
            util.checkType(value1, name1 .. '.respectHLSearch', 'boolean')
        -- the old names for chooser and drawer, caught here rather than left
        -- to the catch-all below so that an upgrade is told what to write
        -- instead of only that the option is not one this plugin has
        elseif key1 == 'prompt' then
            error('"opts.prompt" is now "opts.chooser" for Cash.nvim')
        elseif key1 == 'ui' then
            error('"opts.ui" is now "opts.drawer" for Cash.nvim')
        else
            error('"opts.' .. key1 .. '" ' .. constants.invalidOptionMessage)
        end
    end
end

return options
