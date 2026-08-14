local highlights = require('cash.highlights')
local jump = require('cash.jump')
local util = require('cash.util')

local CashModule = {}

-- factory for default module state. A cash register is a record rather than a
-- bare pattern, because includeInSearch belongs to the register and has to
-- survive everything that rewrites the pattern
local generateDefaultState = function()
    local cashRegisters = {}
    for index = 1, 9 do
        cashRegisters[index] = { pattern = '', includeInSearch = false }
    end

    return {
        currentIndex = 1,
        cashRegisters = cashRegisters,
    }
end

-- complains about an index that does not name a cash register, and returns
-- false so that callers can give up on one line
local rejectIndex = function(index)
    if util.isCashRegisterIndex(index) then
        return false
    end

    vim.notify(
        'Cash.nvim: cash register must be a whole number from 1 to 9',
        vim.log.levels.WARN
    )
    return true
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
    CashModule.state.cashRegisters[CashModule.state.currentIndex].pattern =
        searchString
end

-- initializes the state of the module
CashModule.initializeData = function()
    CashModule.state = generateDefaultState()
    CashModule.setSearch('')
end

-- sets the working cash register
CashModule.setCashRegister = function(newIndex)
    -- there are only 9 cash registers
    if rejectIndex(newIndex) then
        return
    end

    -- get the contents of the new cash register
    local newPattern = CashModule.state.cashRegisters[newIndex].pattern

    -- switch first, so that the highlights are worked out against the new
    -- working cash register
    CashModule.state.currentIndex = newIndex
    CashModule.updateHighlights()

    -- if there is no search pattern, use an empty string
    if newPattern == '' then
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

-- switches whether n and N visit this cash register's matches. Note that the
-- working cash register is in the search set whatever its own switch says, so
-- turning this off for it changes nothing until it stops being the working
-- one. Highlighting is not affected either way: including a cash register
-- changes where n goes, never what is lit
CashModule.setIncludeInSearch = function(index, include)
    if rejectIndex(index) then
        return
    end

    CashModule.state.cashRegisters[index].includeInSearch = include and true
        or false
end

CashModule.toggleIncludeInSearch = function(index)
    if rejectIndex(index) then
        return
    end

    CashModule.setIncludeInSearch(
        index,
        not CashModule.state.cashRegisters[index].includeInSearch
    )
end

-- turns search highlighting back on, undoing a :nohlsearch, and brings every
-- cash register back with it.
--
-- v:hlsearch is saved and restored around autocmd execution and around
-- function calls, so assigning it from inside a callback holds for the rest of
-- that callback and is then thrown away. The matches added meanwhile stay on
-- screen, which makes it look as though it worked, until the next update finds
-- v:hlsearch back at 0 and takes them all away again. Scheduling the
-- assignment runs it outside that context, where it sticks. Both are done: the
-- first so that the caller sees the effect immediately, the second so that it
-- lasts
CashModule.showHighlighting = function()
    pcall(function()
        vim.v.hlsearch = 1
    end)
    CashModule.updateHighlights()

    vim.schedule(function()
        pcall(function()
            vim.v.hlsearch = 1
        end)
        CashModule.updateHighlights()
    end)
end

-- empties one cash register, or the selected one if no index is given
CashModule.clearCashRegister = function(index)
    index = index or CashModule.state.currentIndex
    if rejectIndex(index) then
        return
    end

    CashModule.state.cashRegisters[index].pattern = ''

    -- the search register only mirrors the selected cash register, so it is
    -- only wrong when that is the one being emptied
    if index == CashModule.state.currentIndex then
        vim.fn.setreg('/', '')
    end

    CashModule.updateHighlights()
end

-- what n and N do. Exported so that anyone who wants their own n -- to center
-- the screen after it, say -- can wrap these rather than replace them, which
-- would take the search set out of the picture without saying so
CashModule.nextMatch = function()
    jump.go(CashModule, true)
end

CashModule.previousMatch = function()
    jump.go(CashModule, false)
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

    -- cash register highlighting follows v:hlsearch, so :nohlsearch clears all
    -- nine at once instead of only the working one, and the next search brings
    -- them all back. Nothing announces a change to v:hlsearch, so it is
    -- compared against the last value that was acted on. SafeState fires
    -- whenever vim is about to wait for input, which makes this a number
    -- comparison per keystroke; the update itself only runs when the answer
    -- has actually changed
    local lastHighlightState = vim.v.hlsearch
    vim.api.nvim_create_autocmd('SafeState', {
        group = group,
        callback = function()
            if vim.v.hlsearch == lastHighlightState then
                return
            end
            lastHighlightState = vim.v.hlsearch
            CashModule.updateHighlights()
        end,
    })
end

-- print debug info
CashModule.printDebugInfo = function()
    local registers = {}
    for index = 1, 9 do
        local register = CashModule.state.cashRegisters[index]
        table.insert(
            registers,
            register.pattern .. (register.includeInSearch and ' (in n/N)' or '')
        )
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
