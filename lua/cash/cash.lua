local highlights = require('cash.highlights')
local util = require('cash.util')

local CashModule = {}

-- factory for default module state
local generateDefaultState = function()
    return {
        currentIndex = 1,
        cashRegisters = { '', '', '', '', '', '', '', '', '' },
    }
end

-- brings the highlights in every window in line with the current state
CashModule.updateHighlights = function()
    highlights.update(
        CashModule.state.cashRegisters,
        CashModule.state.currentIndex
    )
end

-- sets the given string as the search pattern for the current index. This
-- function should be called whenever the user performs a search
CashModule.setSearch = function(searchString)
    -- the / register will be set when the user searches, but we also need a
    -- way to search for nothing to clear the search
    if searchString == '' then
        vim.fn.setreg('/', '')
    end
    -- set the contents of the working cash register. Note that there is no
    -- need to update the highlights here: the working cash register is shown
    -- using vim's Search highlight, so it has no match to keep in step
    CashModule.state.cashRegisters[CashModule.state.currentIndex] = searchString
end

-- initializes the state of the module
CashModule.initializeData = function()
    CashModule.state = generateDefaultState()
    CashModule.setSearch('')
end

-- sets the working cash register
CashModule.setCashRegister = function(newIndex)
    -- there are only 9 cash registers
    if
        type(newIndex) ~= 'number'
        or newIndex < 1
        or newIndex > 9
        or newIndex ~= math.floor(newIndex)
    then
        vim.notify(
            'Cash.nvim: cash register must be a whole number from 1 to 9',
            vim.log.levels.WARN
        )
        return
    end

    -- get the contents of the new cash register
    local newPattern = CashModule.state.cashRegisters[newIndex]

    -- switch first, so that the highlights are worked out against the new
    -- working cash register
    CashModule.state.currentIndex = newIndex
    CashModule.updateHighlights()

    -- if there is no search pattern, use an empty string
    if newPattern == nil or newPattern == '' then
        -- clear the search register
        vim.fn.setreg('/', {})
    else
        -- store the new pattern in the search register. This happens even for
        -- a pattern vim cannot compile, so that the search register and the
        -- cash register agree. It is also what vim itself does after a failed
        -- search
        vim.fn.setreg('/', newPattern)

        -- only jump if vim can actually use the pattern
        if util.isUsablePattern(newPattern) then
            -- search for the new pattern (w = wrap around end of document)
            vim.fn.search(newPattern, 'w')
        end
    end
end

-- clear all searches and start back at index 1
CashModule.resetCashRegisters = function()
    -- empty every cash register and go back to the first one
    CashModule.initializeData()

    -- remove the highlights for the cash registers that were just emptied.
    -- Note that the state is reset before this, never after: the ledger of
    -- match IDs lives in the highlights module precisely so that it cannot be
    -- thrown away while the matches it describes are still on screen
    CashModule.updateHighlights()
end

-- subscribes to the editor events that can invalidate the highlights. Called
-- from setup, so that nothing can fire before there is any state to update
CashModule.setUpAutocmds = function()
    local group = vim.api.nvim_create_augroup('CashNvim', { clear = true })

    -- a new window needs the highlights for the non-working cash registers.
    -- WinNew catches windows that are created without being entered; WinEnter
    -- is a cheap safety net, since an update that finds nothing out of place
    -- does not touch vim at all
    vim.api.nvim_create_autocmd({ 'WinNew', 'WinEnter' }, {
        group = group,
        callback = CashModule.updateHighlights,
    })

    -- changing ignorecase changes the case flag that every pattern without an
    -- explicit \c or \C resolves to, so the matches built from those patterns
    -- are no longer the ones that should be on screen
    vim.api.nvim_create_autocmd('OptionSet', {
        group = group,
        pattern = 'ignorecase',
        callback = CashModule.updateHighlights,
    })
end

-- print debug info
CashModule.printDebugInfo = function()
    local registers = {}
    for index = 1, 9 do
        table.insert(registers, CashModule.state.cashRegisters[index] or 'nil')
    end

    vim.notify(
        'index: '
            .. CashModule.state.currentIndex
            .. '\ncash registers: '
            .. table.concat(registers, ', ')
            .. '\nwindowMatchIDs: \n'
            .. highlights.debugInfo()
    )
end

return CashModule
