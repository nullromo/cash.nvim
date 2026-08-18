local highlights = require('cash.highlights')
local jump = require('cash.jump')
local persist = require('cash.persist')
local util = require('cash.util')

-- One of the nine cash registers. A record rather than a bare pattern, because
-- includeInSearch belongs to the register and has to survive everything that
-- rewrites the pattern.
--
-- Its color is deliberately not in here. That belongs to the slot, and lives in
-- opts.colors.highlightColors, which is what makes moving a pattern from one
-- cash register to another a way to recolor a search
---@class cash.Register
---@field pattern string as the user typed it, before any case flag is applied
---@field includeInSearch boolean whether n and N visit its matches

-- what the plugin knows about the cash registers. There are always nine, and
-- one of them is always the working one
---@class cash.State
---@field currentIndex cash.RegisterIndex the working cash register
---@field cashRegisters cash.Register[] nine of them, indexed 1 to 9

-- The module require('cash') hands back.
--
-- Also the one argument the jump, ui and keymaps modules take: they are handed
-- the module rather than the state, so that everything they do goes through the
-- same operations a user's own mapping would call, and so that they can read
-- the options without being given those separately.
--
-- setup is the exception to fields being defined here. It is added by init.lua,
-- which is the file require('cash') actually resolves to
---@class cash.Module
---@field opts cash.ResolvedOptions set by setup, before anything can read it
---@field state cash.State
---@field setup fun(opts?: cash.Options)
local CashModule = {}

-- which Cash.nvim this is, as require('cash').version and as the first line of
-- :checkhealth cash. A bug report that names a version is one that can be read
-- against the code that produced it, which is the whole reason this is here
-- rather than left to whatever the user's plugin manager last checked out.
--
-- This is the same number as the git tag, without the v. The release workflow
-- checks that the two agree before it publishes anything, so a tag pushed
-- without this line being bumped fails there rather than reaching luarocks
CashModule.version = '0.3.0'

-- factory for default module state. A cash register is a record rather than a
-- bare pattern, because includeInSearch belongs to the register and has to
-- survive everything that rewrites the pattern
---@return cash.State
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
---@param index any wherever it came from -- a command argument, a keypress
---@return boolean rejected true when the index does not name a cash register
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
---@param searchString string
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

-- what the search register held just before initializeData last cleared it.
--
-- A fresh set of cash registers is empty, and the search register mirrors the
-- working one, so initializeData empties the search register too. That throws
-- away the one thing a restore needs to look at: whether anything had set the
-- search register before setup ran. It only matters when setup runs after
-- startup rather than during it -- which is what a plugin manager loading this
-- plugin on an event gives -- because there, shada has already put the search
-- register back and initializeData is about to write over it
---@type string
local searchRegisterBeforeSetup = ''

-- initializes the state of the module
CashModule.initializeData = function()
    searchRegisterBeforeSetup = vim.fn.getreg('/')
    CashModule.state = generateDefaultState()
    CashModule.setSearch('')
end

-- centers the window on the cursor, as zz does, when the user has asked for
-- that. Every path that performs a search calls this, so that an ordinary /,
-- a * or #, a switch to another cash register and n and N all leave the match
-- in the same place on the screen.
--
-- A search that found nothing does not call this at all: it has not moved the
-- cursor, and vim does not scroll the window for a failed search either. * and
-- # are the deliberate exception, and center even when disableStarPoundJump
-- has kept the cursor still, since the match is the word under it already
CashModule.centerWindow = function()
    if not CashModule.opts.centerAfterSearch then
        return
    end

    vim.cmd('normal! zz')
end

-- sets the working cash register
---@param newIndex number|nil anything else is refused with a notification
CashModule.setCashRegister = function(newIndex)
    -- there are only 9 cash registers
    if rejectIndex(newIndex) then
        return
    end

    -- rejectIndex has settled that this names one of the nine, which is not
    -- something the checker can work out for itself
    ---@cast newIndex integer

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
            CashModule.expectSearchMove()
            if vim.fn.search(newPattern, 'w') ~= 0 then
                CashModule.centerWindow()
            end
        end
    end
end

-- switches whether n and N visit this cash register's matches. Note that the
-- working cash register is in the search set whatever its own switch says, so
-- turning this off for it changes nothing until it stops being the working
-- one. Highlighting is not affected either way: including a cash register
-- changes where n goes, never what is lit
---@param index number|nil anything else is refused with a notification
---@param include boolean
CashModule.setIncludeInSearch = function(index, include)
    if rejectIndex(index) then
        return
    end

    CashModule.state.cashRegisters[index].includeInSearch = include and true
        or false
end

---@param index number|nil anything else is refused with a notification
CashModule.toggleIncludeInSearch = function(index)
    if rejectIndex(index) then
        return
    end

    CashModule.setIncludeInSearch(
        index,
        not CashModule.state.cashRegisters[index].includeInSearch
    )
end

-- true when the cursor is about to be moved by a search rather than by the
-- user. See CashModule.expectSearchMove
local searchIsMovingTheCursor = false

-- how many times the highlighting has been asked for: once for every search
-- about to move the cursor, and once every time it is turned back on by hand.
--
-- autoNoHighlight cannot clear the highlighting the moment it decides to,
-- because v:hlsearch does not survive being assigned from inside an autocmd,
-- so the clear waits for a schedule. More keys can be dealt with in the
-- meantime, and a search among them turns the highlighting back on -- so a
-- clear that was already on its way would land on top of it and take away the
-- colors of a jump the user has only just made. Every pending clear remembers
-- what this counter said when it was scheduled, and gives up if it has moved
-- on since
local highlightingRequests = 0

-- says that the next cursor movement belongs to a search.
--
-- autoNoHighlight clears the highlighting as soon as the cursor moves, and
-- every search moves the cursor itself. Without this the highlighting would be
-- gone in the same breath as it arrived, which is not what anyone means by
-- "clear it when I move"
CashModule.expectSearchMove = function()
    searchIsMovingTheCursor = true
    highlightingRequests = highlightingRequests + 1
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
-- lasts.
--
-- Both assignments count as asking for the highlighting, so that a clear
-- autoNoHighlight had already scheduled gives up rather than undoing this. The
-- second one is what covers the drawer: opening it moves the cursor into its
-- own window, and that movement is seen and scheduled against after this
-- function has run
CashModule.showHighlighting = function()
    highlightingRequests = highlightingRequests + 1
    pcall(function()
        vim.v.hlsearch = 1
    end)
    CashModule.updateHighlights()

    vim.schedule(function()
        highlightingRequests = highlightingRequests + 1
        pcall(function()
            vim.v.hlsearch = 1
        end)
        CashModule.updateHighlights()
    end)
end

-- empties one cash register, or the selected one if no index is given
---@param index? number the working cash register when left out
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

-- what n and N do. Exported so that anyone who wants their own n -- one that
-- puts the match at the top of the window after it, say -- can wrap these
-- rather than replace them, which would take the search set out of the
-- picture without saying so
CashModule.nextMatch = function()
    jump.go(CashModule, true)
end

CashModule.previousMatch = function()
    jump.go(CashModule, false)
end

-- whether the stored cash registers have been read this session.
--
-- Set once restoreCashRegisters has run, whether or not it found anything, and
-- never cleared again -- not even by initializeData, so that emptying the cash
-- registers with :Cash reset and leaving still saves the empty drawer the user
-- asked for
CashModule.restoreHasRun = false

-- hands the cash registers to shada, for the next neovim to pick up.
--
-- Called from VimLeavePre, which is the last moment that works. Shada collects
-- the global variables it is about to write before VimLeave runs, so a value
-- set from VimLeave is thrown away without a word -- which looks exactly like
-- persistence not being implemented at all
CashModule.saveCashRegisters = function()
    if not CashModule.opts.persistCashRegisters then
        return
    end

    -- a neovim that never got as far as restoring has nothing to say about the
    -- cash registers, and must not answer for them. Quitting before VimEnter is
    -- an ordinary thing to do -- nvim --headless "+Lazy! sync" +qa is the
    -- shape of it, and every scripted nvim that loads the user's config and
    -- exits during startup is the same -- and each one of those would otherwise
    -- write its own empty drawer over the one the user left behind
    if not CashModule.restoreHasRun then
        return
    end

    persist.save(CashModule.state)
end

-- puts back the cash registers the last neovim left behind.
--
-- This cannot happen in setup. The shada file is read after init.lua has run,
-- and that read overwrites whatever the variable held, so at setup time there
-- is either nothing there or a value about to be replaced. VimEnter is the
-- first moment the stored cash registers are really there -- and setup itself
-- can run later than that, under a plugin manager that loads this plugin on an
-- event, which is why the caller checks.
--
-- searchRegister is what the search register held before setup touched it. It
-- is only passed by the caller that runs after startup, where initializeData
-- has already cleared the value this needs to see; left out, the search
-- register is read as it stands
---@param searchRegister? string what the search register held before setup
--- touched it. Read as it stands when left out
CashModule.restoreCashRegisters = function(searchRegister)
    if not CashModule.opts.persistCashRegisters then
        return
    end

    -- from here on this session is entitled to save, even if there turns out to
    -- be nothing stored: a first run with an empty drawer is still a session
    -- whose cash registers are its own
    CashModule.restoreHasRun = true

    searchRegister = searchRegister or vim.fn.getreg('/')

    persist.warnIfUnavailable()

    local restored = persist.load()
    if restored == nil then
        return
    end

    CashModule.state.cashRegisters = restored.cashRegisters
    CashModule.state.currentIndex = restored.currentIndex

    local working = CashModule.state.cashRegisters[restored.currentIndex]

    -- shada puts the search register back as it was, so it still agrees with
    -- the stored one unless something set it during startup. A search is the
    -- thing that does: nvim +/pattern and nvim -c /pattern both run before
    -- VimEnter, and both have already moved the cursor to a match by the time
    -- this runs. Putting the stored pattern back over that would leave the
    -- cursor on one match while vim highlighted another, so the startup search
    -- is taken as a search into the working cash register -- which is what it
    -- would have been had the user typed it.
    --
    -- Only when the stored search register was not empty, though. Shada does
    -- not record an empty search pattern, it just leaves the last non-empty
    -- one in the file, so a session that ended with nothing being searched for
    -- -- which is exactly what :Cash reset and :Cash clear leave behind -- is
    -- met on the way back by a stale pattern from some earlier session. A
    -- difference proves nothing there, and reading it as a startup search
    -- would write that stale pattern into the cash register the user had just
    -- emptied. So the cash registers win, and the stale pattern goes
    if
        restored.searchRegister ~= ''
        and searchRegister ~= restored.searchRegister
    then
        working.pattern = searchRegister
        vim.fn.setreg('/', searchRegister == '' and {} or searchRegister)
    else
        -- the search register mirrors the working cash register, so it is put
        -- back in step with what was just restored
        vim.fn.setreg('/', working.pattern == '' and {} or working.pattern)
    end

    -- nothing here touches v:hlsearch, so a restored cash register lights up
    -- when the next search or n turns highlighting on, and not before. That is
    -- what vim does with the search pattern it restores, and it falls out of
    -- cash register highlighting following v:hlsearch rather than being a case
    -- handled here
    CashModule.updateHighlights()
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
    -- issue #16: for people who want the highlighting to stop following them
    -- around. Off by default, and switchable at any time with :Cash autohide.
    --
    -- v:hlsearch is set from a schedule rather than from the callback, because
    -- it is saved and restored around autocmd execution: assigned here
    -- directly it would hold for the rest of this callback and then be thrown
    -- away, and the highlighting would flicker off and straight back on
    vim.api.nvim_create_autocmd('CursorMoved', {
        group = group,
        callback = function()
            if not CashModule.opts.autoNoHighlight then
                return
            end

            -- spent here rather than below, because a movement is a movement
            -- whether or not there is anything lit to take away. Left standing
            -- when the highlighting happens to be off, the expectation would
            -- be spent on the user's next move instead, and that one would go
            -- unnoticed
            local thisIsTheSearch = searchIsMovingTheCursor
            searchIsMovingTheCursor = false

            if thisIsTheSearch or vim.v.hlsearch == 0 then
                return
            end

            -- what the counter says now. The schedule below runs after the
            -- rest of the keys waiting to be dealt with, and if a search is
            -- among them the highlighting it turns on is the newer answer:
            -- clearing then would leave the cursor sitting on a match with
            -- nothing marking it
            local requestedWhenScheduled = highlightingRequests

            vim.schedule(function()
                if requestedWhenScheduled ~= highlightingRequests then
                    return
                end

                pcall(function()
                    vim.v.hlsearch = 0
                end)
                CashModule.updateHighlights()
            end)
        end,
    })

    local lastHighlightState = vim.v.hlsearch
    vim.api.nvim_create_autocmd('SafeState', {
        group = group,
        callback = function()
            -- a search that was expected to move the cursor and did not is
            -- forgotten here. Not every search moves: one that finds nothing
            -- leaves the cursor where it was, and so does * with
            -- disableStarPoundJump, which is the default. The expectation
            -- would otherwise sit there waiting to be spent on whatever the
            -- user did next, and that move would not clear the highlighting
            -- the way every other move does.
            --
            -- SafeState is vim about to wait for the next key, which is after
            -- the search has had its chance to move the cursor and after the
            -- CursorMoved it would have caused
            searchIsMovingTheCursor = false

            if vim.v.hlsearch == lastHighlightState then
                return
            end
            lastHighlightState = vim.v.hlsearch
            CashModule.updateHighlights()
        end,
    })

    -- the cash registers go out on the way down, and shada writes them moments
    -- later. This is the same promise vim makes for the search pattern it
    -- restores: a clean exit keeps them, and a crash does not
    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = group,
        callback = CashModule.saveCashRegisters,
    })

    -- and come back at VimEnter, which is the first moment shada has been
    -- read. Setup can run after that moment rather than before it, when a
    -- plugin manager loads this plugin on an event, and then the autocmd would
    -- never fire -- so the answer is asked for rather than assumed
    if vim.v.vim_did_enter == 1 then
        CashModule.restoreCashRegisters(searchRegisterBeforeSetup)
    else
        vim.api.nvim_create_autocmd('VimEnter', {
            group = group,
            once = true,
            callback = function()
                CashModule.restoreCashRegisters()
            end,
        })
    end
end

return CashModule
