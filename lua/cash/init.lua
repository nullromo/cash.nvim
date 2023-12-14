-- create module object for export
local CashModule = {}

-- color constants taken from kanagawa.nvim
local sumiInk0 = '#16161D'
local fujiWhite = '#DCD7BA'
local roninYellow = '#FF9E3B'
local springBlue = '#7FB4CA'
local sakuraPink = '#D27E99'
local springGreen = '#98BB6C'
local autumnYellow = '#DCA561'
local oniViolet = '#957FB8'
local autumnGreen = '#76946A'
local autumnRed = '#C34043'
local waveBlue2 = '#2D4F67'

local defaultOptions = {
    -- color settings
    colors = {
        -- default colors for foreground and background (used for highlight
        -- groups where fg/bg are not specified)
        defaultBG = roninYellow,
        defaultFG = sumiInk0,
        -- define colors for highlight groups 1-9
        highlightColors = {
            { bg = roninYellow },
            { bg = springBlue },
            { bg = sakuraPink },
            { bg = springGreen },
            { bg = autumnYellow },
            { bg = oniViolet },
            { bg = autumnGreen },
            { bg = autumnRed },
            { bg = waveBlue2, fg = fujiWhite },
        },
    },
}

local throw = function(valueName, requiredType)
    error(valueName .. ' must be a ' .. requiredType .. 'for Cash.nvim')
end

local checkType = function(value, valueName, typeName)
    if type(value) ~= typeName then
        throw(valueName, typeName)
    end
end

local generateDefaultState = function()
    return {
        currentIndex = 1,
        searchHighlightPatterns = { '', '', '', '', '', '', '', '', '' },
        matchIDs = { nil, nil, nil, nil, nil, nil, nil, nil, nil },
    }
end

-- main setup function for Cash.nvim
CashModule.setup = function(options)
    -- make sure options is not nil
    options = options or {}

    -- set default options if not already set
    options.colors = options.colors or defaultOptions.colors
    options.colors.defaultFG = options.colors.defaultFG or defaultOptions.colors.defaultFG
    options.colors.defaultBG = options.colors.defaultBG or defaultOptions.colors.defaultBG
    options.colors.highlightColors = options.colors.highlightColors or defaultOptions.colors.highlightColors
    options.message = options.message or 'hello'

    -- validate options
    for key1, value1 in pairs(options) do
        local name1 = 'options'
        if key1 == 'message' then
            checkType(value1, name1 .. '.message', 'string')
        elseif key1 == 'colors' then
            checkType(value1, name1 .. '.colors', 'table')
            for key2, value2 in pairs(value1) do
                local name2 = name1 .. '.colors'
                if key2 == 'defaultBG' then
                    checkType(value2, name2 .. '.defaultBG', 'string')
                elseif key2 == 'defaultFG' then
                    checkType(value2, name2 .. '.defaultFG', 'string')
                elseif key2 == 'highlightColors' then
                    checkType(value2, 'options.colors.highlightColors', 'table')
                    for key3, value3 in ipairs(value2) do
                        local name3 = name2 .. '.highlightColors[' .. key3 .. ']'
                        checkType(value3, name3, 'table')
                        for key4, value4 in pairs(value3) do
                            if key4 == 'bg' then
                                checkType(value4, name3 .. '.bg', 'string')
                            elseif key4 == 'fg' then
                                checkType(value4, name3 .. '.fg', 'string')
                            else
                                error('"' .. name3 .. '.' .. key4 .. '" is not a valid option for Cash.nvim')
                            end
                        end
                    end
                else
                    error('"options.colors.' .. key2 .. '" is not a valid option for Cash.nvim')
                end
            end
        else
            error('"options.' .. key1 .. '" is not a valid option for Cash.nvim')
        end
    end

    vim.api.nvim_create_user_command(
        'TimeToTest',
        function()
            vim.notify(options.message)
        end,
        { bang = true }
    )

    -- set up highlight groups
    for i = 1, 9 do
        local bg = options.colors.highlightColors[i].bg or options.colors.defaultBG
        local fg = options.colors.highlightColors[i].fg or options.colors.defaultFG
        vim.cmd.highlight('CashRegister' .. i, 'guibg=' .. bg  .. ' guifg=' .. fg)
    end

    -- set initial plugin state
    CashModule.state = generateDefaultState()
end

CashModule.exampleVariable = function()
    return 4
end

-- export module
return CashModule
