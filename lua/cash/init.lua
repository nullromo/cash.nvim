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
    -- center the screen after each search
    centerAfterSearch = true,
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
    -- setting to control whether or not using * or # from normal mode will
    -- jump to the next occurrence. Vim will jump by default
    disableStarPoundJump = true,
}

local throw = function(valueName, requiredType)
    error(valueName .. ' must be a ' .. requiredType .. 'for Cash.nvim')
end

local checkType = function(value, valueName, typeName)
    if type(value) ~= typeName then
        throw(valueName, typeName)
    end
end

local invalidOptionMessage = 'is not a valid option for Cash.nvim'


local generateDefaultState = function()
    return {
        currentIndex = 1,
        cashRegisters = { '', '', '', '', '', '', '', '', '' },
        matchIDs = { nil, nil, nil, nil, nil, nil, nil, nil, nil },
    }
end

-- sets the given string as the search pattern for the current index. This
-- function should be called whenever the user performs a search
CashModule.setSearch = function(searchString)
    -- the / register will be set when the user searches, but we also need a
    -- way to search for nothing to clear the search
    if searchString == '' then
        vim.fn.setreg('/', '')
    end
    -- set the contents of the active cash register
    CashModule.state.cashRegisters[CashModule.state.currentIndex] = searchString
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

    -- validate options
    for key1, value1 in pairs(options) do
        local name1 = 'options'
        if key1 == 'centerAfterSearch' then
            checkType(value1, name1 .. '.centerAfterSearch', 'boolean')
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
                                error('"' .. name3 .. '.' .. key4 .. '" ' .. invalidOptionMessage)
                            end
                        end
                    end
                else
                    error('"options.colors.' .. key2 .. '" ' .. invalidOptionMessage)
                end
            end
        elseif key1 == 'disableStarPoundJump' then
            checkType(value1, name1 .. '.disableStarPoundJump', 'boolean')
        else
            error('"options.' .. key1 .. '" ' .. invalidOptionMessage)
        end
    end

    -- set options
    CashModule.options = options

    -- set up highlight groups
    for i = 1, 9 do
        local bg = options.colors.highlightColors[i].bg or options.colors.defaultBG
        local fg = options.colors.highlightColors[i].fg or options.colors.defaultFG
        vim.cmd.highlight('CashRegister' .. i, 'guibg=' .. bg  .. ' guifg=' .. fg)
    end

    -- set initial plugin state
    CashModule.initializeData()
end

-- initializes the state of the module
CashModule.initializeData = function()
    CashModule.state = generateDefaultState()
    CashModule.setSearch('')
end

local deleteMatch = function(index)
    local matchID = CashModule.state.matchIDs[index]
    if matchID ~= nil and matchID ~= -1 then
        vim.fn.matchdelete(matchID)
        CashModule.state.matchIDs[index] = nil
    end
end

-- sets the active cash register
CashModule.setCashRegister = function(newIndex)
    -- get the contents of the active cash register and the new cash register
    local currentPattern = CashModule.state.cashRegisters[CashModule.state.currentIndex]
    local newPattern = CashModule.state.cashRegisters[newIndex]

    -- delete the match that was highlighting the newIndex-th pattern
    deleteMatch(newIndex)

    -- add a match for the old search highlight
    CashModule.state.matchIDs[CashModule.state.currentIndex] = vim.fn.matchadd(
        'CashRegister' .. CashModule.state.currentIndex,
        currentPattern
    )

    -- change the active search highlight color
    vim.api.nvim_set_hl(0, 'Search', {
        fg = CashModule.options.colors.highlightColors[newIndex].fg or CashModule.options.colors.defaultFG,
        bg = CashModule.options.colors.highlightColors[newIndex].bg or CashModule.options.colors.defaultBG,
    })

    -- if there is no search pattern, use an empty string
    if newPattern == nil or newPattern == '' then
        -- clear the search register
        vim.fn.setreg('/', {})
    else
        -- store the new pattern in the search register
        vim.fn.setreg('/', newPattern)
        -- search for the new pattern (w = wrap around end of document)
        vim.fn.search(newPattern, 'w')
    end

    -- update the active cash register index
    CashModule.state.currentIndex = newIndex
end

-- set the cash register switching keymap. Use ?<number> to swap to the
-- <number>-th search pattern
vim.keymap.set('n', '?', function()
    -- get a character from the user
    vim.notify('Enter a digit to choose a cash registers')
    local userNumber = tonumber(vim.fn.nr2char(vim.fn.getchar()))

    -- if the user didn't enter a number, do nothing
    if userNumber == nil then
        vim.notify('Error: you must enter a digit to select a cash register')
        return
    end

    -- set the active cash register to the user's desired number
    CashModule.setCashRegister(userNumber)
end)

-- run custom functions after searching. Whenever the user performs a normal
-- search, we need to make sure to update some things
vim.keymap.set('c', '<CR>',
    function()
        -- check if the current command is a search command
        local commandType = vim.fn.getcmdtype()
        if commandType == '/' or commandType == '?' then
            -- update Cash.nvim for the new search
            CashModule.setSearch(vim.fn.getcmdline())
        end

        -- execute the command as normal
        return '<CR>'
    end,
    { expr = true }
)

-- action to run when the user presses * or # from normal mode
local starPoundAction = function(usingStar)
    return function()
        -- choose the key pressed based on the argument
        local keyPressed = usingStar and '*' or '#'

        -- set the search pattern as */# normally would
        CashModule.setSearch(vim.fn.expand('<cword>'))

        -- if a count was supplied, execute */# normally and exit
        if vim.v.count > 0 then
            vim.cmd('normal! ' .. vim.v.count .. keyPressed .. '<CR>')
        else
            -- save current window view
            local windowView = vim.fn.winsaveview()

            -- execute */# normally
            vim.cmd('silent keepjumps normal! ' .. keyPressed .. '<CR>')

            -- restore the window view
            if windowView ~= nil and CashModule.options.disableStarPoundJump then
                vim.fn.winrestview(windowView)
            end
        end

        -- center the screen
        if CashModule.options.centerAfterSearch then
            vim.cmd('normal! zz<CR>')
        end
    end
end

-- set keymaps for * and # to update module state
vim.keymap.set('n', '*', starPoundAction(true))
vim.keymap.set('n', '#', starPoundAction(false))

-- Use clc in command mode to clear the search
vim.keymap.set(
    'c',
    'clc<CR>',
    function()
        -- check which command line the command was entered in
        local commandType = vim.fn.getcmdtype()

        -- if it was entered in ex mode
        if commandType == ':' then
            -- clear the current search
            CashModule.setSearch('')

            -- exit ex mode normally
            return '<CR>'
        end

        -- if it was entered in a search command
        if commandType == '/' or commandType == '?' then
            -- search for the literal string
            CashModule.setSearch('clc')
        end

        -- exit the search normally
        return 'clc<CR>'
    end,
    { expr = true }
)

-- clear all searches and start back at index 1
CashModule.clearAllSearches = function()
    -- clear current search
    CashModule.setSearch('')

    -- reset search index to 1
    CashModule.setCashRegister(1)

    -- remove all leftover match highlights
    for i = 1, 9 do
        deleteMatch(i)
    end

    -- re-initialize module state
    CashModule.initializeData()
end

-- print debug info
CashModule.printDebugInfo = function()
    local s = ''
    for i = 1, 9 do
        local x = CashModule.state.cashRegisters[i]
        if x == nil then
            s = s .. 'nil' .. ', '
        else
            s = s .. x .. ', '
        end
    end
    local z = ''
    for i = 1, 9 do
        local x = CashModule.state.matchIDs[i]
        if x == nil then
            z = z .. 'nil' .. ', '
        else
            z = z .. x .. ', '
        end
    end
    vim.notify('index: ' .. CashModule.state.currentIndex .. ' table: ' .. s .. ' : ' .. z)
end

-- export module
return CashModule

-- TODO: make a debug function that shows all the colors in a temporary buffer
-- debug
--vim.fn.matchadd('SearchPattern1', 'SearchPattern1', -1)
--vim.fn.matchadd('SearchPattern2', 'SearchPattern2', -1)
--vim.fn.matchadd('SearchPattern3', 'SearchPattern3', -1)
--vim.fn.matchadd('SearchPattern4', 'SearchPattern4', -1)
--vim.fn.matchadd('SearchPattern5', 'SearchPattern5', -1)
--vim.fn.matchadd('SearchPattern6', 'SearchPattern6', -1)
--vim.fn.matchadd('SearchPattern7', 'SearchPattern7', -1)
--vim.fn.matchadd('SearchPattern8', 'SearchPattern8', -1)
--vim.fn.matchadd('SearchPattern9', 'SearchPattern9', -1)
