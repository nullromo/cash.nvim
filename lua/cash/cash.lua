local util = require('cash.util')

local CashModule = {}

-- factory for default module state
local generateDefaultState = function()
    return {
        currentIndex = 1,
        cashRegisters = { '', '', '', '', '', '', '', '', '' },
        windowMatchIDs = {},
    }
end

-- removes a match from vim based on a cash register index
local deleteMatch = function(index)
    for windowID, matchIDs in pairs(CashModule.state.windowMatchIDs) do
        local matchID = matchIDs[index]
        if matchID ~= nil and matchID ~= -1 then
            util.wrappers.matchdelete(matchID, windowID)
            matchIDs[index] = nil
        end
    end
end

-- adds a match to vim based on a cash register index
local addMatch = function(index)
    for windowID, matchIDs in pairs(CashModule.state.windowMatchIDs) do
        matchIDs[index] = vim.fn.matchadd(
            'CashRegister' .. index,
            CashModule.state.cashRegisters[index],
            10, -- use default priority
            -1, -- automatically choose ID
            { window = windowID }
        )
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

-- initializes the state of the module
CashModule.initializeData = function()
    CashModule.state = generateDefaultState()
    CashModule.setSearch('')
end

-- sets the active cash register
CashModule.setCashRegister = function(newIndex)
    -- get the contents of the active cash register and the new cash register
    local newPattern = CashModule.state.cashRegisters[newIndex]

    -- delete the match that was highlighting the newIndex-th pattern
    deleteMatch(newIndex)

    -- add a new match highlighting the currentIndex-th pattern
    addMatch(CashModule.state.currentIndex)

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
    local z = '\n'
    for windowID, matchIDs in pairs(CashModule.state.windowMatchIDs) do
        z = z .. '\twindow ' .. windowID .. ': '
        for i = 1, 9 do
            local x = matchIDs[i]
            if x == nil then
                z = z .. 'nil' .. ', '
            else
                z = z .. x .. ', '
            end
        end
        z = z .. '\n'
    end
    vim.notify('index: ' .. CashModule.state.currentIndex .. '\ncash registers: ' .. s .. '\nwindowMatchIDs: ' .. z)
end

-- whenever a new window is opened, give that window a blank set of match IDs
vim.api.nvim_create_autocmd({'VimEnter', 'WinEnter'}, {
    callback = function()
        -- get the window ID for the window that was just entered
        local windowID = tonumber(vim.fn.win_getid())

        -- create empty match ID table
        if windowID ~= nil then
            CashModule.state.windowMatchIDs[windowID] = {
                nil, nil, nil, nil, nil, nil, nil, nil, nil
            }
        else
            vim.notify(
                'Could not get window ID from VimEnter/WinEnter event.',
                vim.log.levels.WARN
            )
        end
    end
})

-- whenever a window is closed, stop tracking match IDs for it
vim.api.nvim_create_autocmd({'WinClosed'}, {
    callback = function(event)
        -- event.match holds the value of <amatch>, which in this case gets set
        -- to the window ID of the window that was just closed
        local windowID = tonumber(event.match)

        -- remove the matchID list for the window that was closed
        if windowID ~= nil then
            CashModule.state.windowMatchIDs[windowID] = nil
        else
            vim.notify(
                'Could not get window ID from WinClosed event.',
                vim.log.levels.WARN
            )
        end
    end
})

return CashModule
