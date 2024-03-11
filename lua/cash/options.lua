local constants = require('cash.constants')
local util = require('cash.util')

local options = {}

options.defaultOptions = {
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
    -- leave vim's hlsearch setting alone. This plugin overrides hlsearch by
    -- default
    respectHLSearch = false,
}

options.validateOptions = function(opts)
    for key1, value1 in pairs(opts) do
        local name1 = 'opts'
        if key1 == 'centerAfterSearch' then
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
        elseif key1 == 'respectHLSearch' then
            util.checkType(value1, name1 .. '.respectHLSearch', 'boolean')
        else
            error('"opts.' .. key1 .. '" ' .. constants.invalidOptionMessage)
        end
    end
end

return options
