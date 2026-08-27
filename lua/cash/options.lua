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
---@field indicator? cash.IndicatorOptions
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

-- the brackets, written either way: the name of one of the pairs Cash.nvim
-- has, or the two strings to use
---@alias cash.BracketOption cash.BracketStyle | cash.Brackets

---@class cash.IndicatorOptions
---@field show? boolean
---@field style? cash.IndicatorStyle
---@field position? cash.Position
---@field display? cash.IndicatorDisplay
---@field maxWidth? integer
---@field brackets? cash.BracketOption

-- the options once resolve has filled in every default. What cash.opts holds,
-- and what everything inside the plugin reads
---@class cash.ResolvedOptions : cash.Options
---@field autoNoHighlight boolean
---@field centerAfterSearch boolean
---@field chooser cash.ResolvedChooserOptions
---@field colors cash.ResolvedColorOptions
---@field disableStarPoundJump boolean
---@field drawer cash.ResolvedDrawerOptions
---@field indicator cash.ResolvedIndicatorOptions
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

---@class cash.ResolvedIndicatorOptions
---@field show boolean
---@field style cash.IndicatorStyle
---@field position cash.Position
---@field display cash.IndicatorDisplay
---@field maxWidth integer
---@field brackets cash.Brackets always the pair, never the name of one. A name
--- is the other way of writing the same thing, and resolve turns it into the
--- pair so that nothing downstream has to know which way it was written

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
    -- the indicator: a small window of this plugin's own saying which cash
    -- register is the working one
    indicator = {
        -- off, because this is a persistent overlay on the user's own text and
        -- that is asked for rather than arrived at. What it draws is available
        -- as require('cash').label() and require('cash').statusline() either
        -- way, for anyone putting it in a statusline of their own
        show = false,
        -- 'current' is the search set, 'strip' is all nine of them. Either
        -- way the cash registers in the search set wear their color as a
        -- swatch and the working one is marked
        style = 'current',
        -- where on screen it sits, out of the same nine places the popups use
        position = 'bottom-right',
        -- what goes inside the brackets: 'number' for the cash register's
        -- number, 'pattern' for what it holds, or 'number-and-pattern' for
        -- both. indicator.style shapes the number, so it has nothing to do
        -- with 'pattern'
        display = 'number',
        -- how wide the whole label may be, in screen cells and brackets
        -- included. The pattern is what gives way to fit; the number never
        -- does. Wide enough by default for the strip and a pattern together,
        -- since a cap that quietly leaves the pattern out of the combination
        -- the user just asked for is a cap that looks like a bug
        maxWidth = 30,
        -- what goes round it. These are the indicator's border, which is
        -- why it is drawn without one. Either the name of one of the pairs in
        -- constants.brackets, or { left = ..., right = ... } to use anything
        -- else
        brackets = vim.deepcopy(
            constants.brackets[constants.defaultBracketStyle]
        ),
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

-- one option that used to be called something else
---@class cash.RenamedOption
---@field newName string what to write instead
---@field removedIn string the version the old name stops being read at all

-- Every option this plugin has renamed, and what it is called now.
--
-- A config written against an older Cash.nvim keeps working: the value moves
-- to the new name and the user is told once, rather than setup throwing on a
-- name that was right when they wrote it. Throwing is what this used to do,
-- and it makes every rename an upgrade that breaks Neovim on startup for
-- anyone who has not read the release notes yet.
--
-- removedIn is a promise, so it goes in front of the user rather than only in
-- a comment: the old name is read until that version and not after it. An
-- entry whose removedIn has shipped comes out of this table, and the name
-- goes back to being one the catch-all in validateOptions does not know
---@type table<string, cash.RenamedOption>
options.renamedOptions = {
    prompt = { newName = 'chooser', removedIn = '1.0.0' },
    ui = { newName = 'drawer', removedIn = '1.0.0' },
}

-- Moves anything written under an old option name over to the name it has
-- now, warning once per name. Returns a new table; the caller's own table is
-- left alone, since a plugin manager tends to hand setup the same opts table
-- on every reload and rewriting it under them would be a surprise.
--
-- Only the top level is copied, which is as deep as a rename goes. What is
-- underneath is shared with the caller's table, exactly as it was before this
-- ran, and resolve is what stops that sharing reaching the defaults
---@param opts table exactly as the user wrote it
---@return table
options.migrate = function(opts)
    local migrated = vim.tbl_extend('force', {}, opts)

    for oldName, renamed in pairs(options.renamedOptions) do
        if migrated[oldName] ~= nil then
            -- the backtrace is turned off because it points at this file,
            -- which is not where the option the user has to go and change is
            vim.deprecate(
                'opts.' .. oldName,
                'opts.' .. renamed.newName,
                renamed.removedIn,
                'Cash.nvim',
                false
            )

            -- what is already written under the new name wins. Both names at
            -- once is a config half way through the rename, and the new name
            -- is the half that has been updated on purpose
            if migrated[renamed.newName] == nil then
                migrated[renamed.newName] = migrated[oldName]
            end

            migrated[oldName] = nil
        end
    end

    return migrated
end

-- throws unless the given value is one of the named bracket pairs or a pair
-- written out in full.
--
-- Both halves are required of a pair, rather than the missing one falling back
-- to the default. Half a pair is a chip that opens with one thing and closes
-- with another, which nobody asks for on purpose, and the deep merge behind
-- resolve would hand it over without a word
---@param value any straight from the user's options table
---@param valueName string as the user wrote it
options.validateBrackets = function(value, valueName)
    if type(value) == 'string' then
        util.checkOneOf(value, valueName, constants.bracketStyles)
        return
    end

    if type(value) ~= 'table' then
        error(
            '"'
                .. valueName
                .. '" must be one of '
                .. table.concat(constants.bracketStyles, ', ')
                .. ', or a table of left and right, for Cash.nvim'
        )
    end

    for key, side in pairs(value) do
        if key ~= 'left' and key ~= 'right' then
            error(
                '"'
                    .. valueName
                    .. '.'
                    .. tostring(key)
                    .. '" '
                    .. constants.invalidOptionMessage
            )
        end
        util.checkType(side, valueName .. '.' .. key, 'string')
    end

    if value.left == nil or value.right == nil then
        error(
            '"'
                .. valueName
                .. '" must have both a left and a right for '
                .. 'Cash.nvim'
        )
    end
end

-- turns whatever the brackets option holds into the pair to draw with. A name
-- becomes the pair it names, and a pair is already one.
--
-- Exported because two callers need it. resolve calls it so that the resolved
-- options hold a pair whichever way the user wrote it, and indicator.label
-- calls it because its overrides can name a style that the configured options
-- do not, and those are read as they come rather than validated
---@param brackets cash.BracketOption
---@return cash.Brackets
options.resolveBrackets = function(brackets)
    if type(brackets) ~= 'string' then
        return brackets
    end

    -- a name that is not one of them cannot come from setup, which has already
    -- refused it, so it came from an override. The default pair is a better
    -- answer there than an error thrown from inside a redraw
    return vim.deepcopy(
        constants.brackets[brackets]
            or constants.brackets[constants.defaultBracketStyle]
    )
end

-- checks the user's options and fills in a default for everything they did
-- not specify. Returns a new table; the caller's own table is left alone
---@param opts? cash.Options
---@return cash.ResolvedOptions
options.resolve = function(opts)
    opts = opts or {}

    -- an option written under a name this plugin used to have moves to the
    -- name it has now, before anything below is handed a name it would only
    -- be able to call invalid
    opts = options.migrate(opts)

    -- validate what the user actually wrote, so that a complaint names one of
    -- their options rather than one of ours. A renamed option is the one
    -- exception: a complaint about it names the new name, which is the name
    -- the deprecation warning has just told the user to write
    options.validateOptions(opts)

    -- the defaults are deep copied first because tbl_deep_extend hands back
    -- the tables it did not have to merge, and those would be this module's
    -- own defaults, shared with whatever the caller does to the result later
    local resolved =
        vim.tbl_deep_extend('force', vim.deepcopy(options.defaultOptions), opts)

    -- the brackets are the one option that can be written two ways, so this is
    -- where the two become one. A name replaced the default pair outright
    -- during the merge, since a string and a table do not merge, and it is
    -- turned into the pair it names here
    resolved.indicator.brackets =
        options.resolveBrackets(resolved.indicator.brackets)

    return resolved
end

-- throws unless every key in the given table is an option this plugin has,
-- holding a value of the right shape.
--
-- Takes a plain table rather than cash.Options, because the keys it is looking
-- for include the ones that are not options at all: that is the whole point of
-- the catch-all at the bottom. Names this plugin used to have never reach it,
-- because migrate has already turned them into names it has now
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
        elseif key1 == 'indicator' then
            util.checkType(value1, name1 .. '.indicator', 'table')
            for key2, value2 in pairs(value1) do
                local name2 = name1 .. '.indicator.' .. key2
                if key2 == 'show' then
                    util.checkType(value2, name2, 'boolean')
                elseif key2 == 'style' then
                    util.checkOneOf(value2, name2, constants.indicatorStyles)
                elseif key2 == 'position' then
                    util.checkOneOf(value2, name2, constants.positions)
                elseif key2 == 'display' then
                    util.checkOneOf(value2, name2, constants.indicatorDisplays)
                elseif key2 == 'maxWidth' then
                    util.checkType(value2, name2, 'number')
                    -- a label cannot be no cells wide. Leaving the pattern
                    -- out altogether is what display is for, rather than a
                    -- width with no room in it
                    if value2 < 1 or value2 ~= math.floor(value2) then
                        error(
                            '"'
                                .. name2
                                .. '" must be a whole number of 1 or more '
                                .. 'for Cash.nvim'
                        )
                    end
                elseif key2 == 'brackets' then
                    options.validateBrackets(value2, name2)
                else
                    error(
                        '"' .. name2 .. '" ' .. constants.invalidOptionMessage
                    )
                end
            end
        elseif key1 == 'manageJumps' then
            util.checkType(value1, name1 .. '.manageJumps', 'boolean')
        elseif key1 == 'persistCashRegisters' then
            util.checkType(value1, name1 .. '.persistCashRegisters', 'boolean')
        elseif key1 == 'respectHLSearch' then
            util.checkType(value1, name1 .. '.respectHLSearch', 'boolean')
        else
            error('"opts.' .. key1 .. '" ' .. constants.invalidOptionMessage)
        end
    end
end

return options
