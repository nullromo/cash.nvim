local options = require('cash.options')
local keymaps = require('cash.keymaps')
local util = require('cash.util')

-- create module object for export
local CashModule = {}

-- factory for default module state
local generateDefaultState = function()
    return {
        currentIndex = 1,
        cashRegisters = { '', '', '', '', '', '', '', '', '' },
        matchIDs = { nil, nil, nil, nil, nil, nil, nil, nil, nil },
    }
end

-- removes a match from vim based on a cash register index
local deleteMatch = function(index)
    local matchID = CashModule.state.matchIDs[index]
    if matchID ~= nil and matchID ~= -1 then
        util.wrappers.matchdelete(matchID)
        CashModule.state.matchIDs[index] = nil
    end
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
CashModule.setup = function(opts)
    -- make sure options is not nil
    opts = opts or {}

    -- set default options if not already set
    opts.centerAfterSearch = opts.centerAfterSearch or options.defaultOptions.centerAfterSearch
    opts.colors = opts.colors or options.defaultOptions.colors
    opts.colors.defaultFG = opts.colors.defaultFG or options.defaultOptions.colors.defaultFG
    opts.colors.defaultBG = opts.colors.defaultBG or options.defaultOptions.colors.defaultBG
    opts.colors.highlightColors = opts.colors.highlightColors or options.defaultOptions.colors.highlightColors
    opts.disableStarPoundJump = opts.disableStarPoundJump or options.defaultOptions.disableStarPoundJump
    opts.respectHLSearch = opts.respectHLSearch or options.defaultOptions.respectHLSearch

    -- validate options
    options.validateOptions(opts)

    -- set options
    CashModule.opts = opts

    -- set up highlight groups
    for i = 1, 9 do
        local bg = opts.colors.highlightColors[i].bg or opts.colors.defaultBG
        local fg = opts.colors.highlightColors[i].fg or opts.colors.defaultFG
        vim.cmd.highlight('CashRegister' .. i, 'guibg=' .. bg  .. ' guifg=' .. fg)
    end

    -- set initial plugin state
    CashModule.initializeData()

    -- set up keymaps
    keymaps.setUpKeymaps(CashModule)

    -- enable hlsearch
    if not opts.respectHLSearch then
        vim.opt.hlsearch = true
    end
end

-- initializes the state of the module
CashModule.initializeData = function()
    CashModule.state = generateDefaultState()
    CashModule.setSearch('')
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
        fg = CashModule.opts.colors.highlightColors[newIndex].fg or CashModule.opts.colors.defaultFG,
        bg = CashModule.opts.colors.highlightColors[newIndex].bg or CashModule.opts.colors.defaultBG,
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

-- clear all searches and start back at index 1
CashModule.resetCashRegisters = function()
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
