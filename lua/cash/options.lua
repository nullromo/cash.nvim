local constants = require('cash.constants')
local util = require('cash.util')

local options = {}

options.defaultOptions = {
    -- clear every cash register's highlighting as soon as the cursor moves
    -- again. The search that turned it on moves the cursor itself, so that
    -- first move does not count
    autoNoHighlight = false,
    -- center the screen after each search
    centerAfterSearch = true,
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
    -- let this plugin own n and N, so that they can move between the matches
    -- of every cash register in the search set. With one cash register in the
    -- search set -- which is the case until include-in-search is switched on
    -- somewhere -- the mapping hands straight back to vim, so n and N behave
    -- exactly as they always did. Set this to false to leave them alone
    -- entirely, at the cost of include-in-search doing nothing
    manageJumps = true,
    -- the popup that ? brings up to choose a cash register
    prompt = {
        -- 'grid' lays the nine out like a numpad and shows what each one
        -- holds, 'strip' is one line of numbers in their colors, and 'none'
        -- keeps the plain message and no popup at all
        style = 'grid',
        -- where on screen it appears
        position = 'center',
        -- the chooser's border, in any form nvim_open_win accepts
        border = 'rounded',
    },
    -- leave vim's hlsearch setting alone. This plugin overrides hlsearch by
    -- default
    respectHLSearch = false,
    -- the cash drawer, which :Cash opens
    ui = {
        -- the drawer's border, in any form nvim_open_win accepts
        border = 'rounded',
        -- where on screen it appears
        position = 'center',
        -- whether the detail pane is already open when the drawer appears. ?
        -- toggles it either way
        detailPane = false,
    },
}

-- checks the user's options and fills in a default for everything they did
-- not specify. Returns a new table; the caller's own table is left alone
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

options.validateOptions = function(opts)
    for key1, value1 in pairs(opts) do
        local name1 = 'opts'
        if key1 == 'autoNoHighlight' then
            util.checkType(value1, name1 .. '.autoNoHighlight', 'boolean')
        elseif key1 == 'centerAfterSearch' then
            util.checkType(value1, name1 .. '.centerAfterSearch', 'boolean')
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
        elseif key1 == 'manageJumps' then
            util.checkType(value1, name1 .. '.manageJumps', 'boolean')
        elseif key1 == 'prompt' then
            util.checkType(value1, name1 .. '.prompt', 'table')
            for key2, value2 in pairs(value1) do
                local name2 = name1 .. '.prompt.' .. key2
                if key2 == 'style' then
                    util.checkOneOf(value2, name2, constants.promptStyles)
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
        elseif key1 == 'respectHLSearch' then
            util.checkType(value1, name1 .. '.respectHLSearch', 'boolean')
        elseif key1 == 'ui' then
            util.checkType(value1, name1 .. '.ui', 'table')
            for key2, value2 in pairs(value1) do
                local name2 = name1 .. '.ui'
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
                        '"opts.ui.'
                            .. key2
                            .. '" '
                            .. constants.invalidOptionMessage
                    )
                end
            end
        else
            error('"opts.' .. key1 .. '" ' .. constants.invalidOptionMessage)
        end
    end
end

return options
