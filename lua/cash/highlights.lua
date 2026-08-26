local cursor = require('cash.cursor')
local util = require('cash.util')

-- one match this module has added: the ID matchdelete needs, and the pattern it
-- was built from, so that a pattern which has since changed can be told apart
-- from one that has not
---@class cash.LedgerEntry
---@field id integer
---@field matchPattern string

-- which matches this plugin has added to which windows, keyed by window ID and
-- then by cash register
---@alias cash.Ledger table<integer, table<integer, cash.LedgerEntry|nil>>

local highlights = {}

-- colors for the 9 cash registers. Set once during setup
---@type cash.ResolvedColorOptions|nil
local colors = nil

-- record of the matches this module has added to each window. An index with no
-- entry has no match, and that is the only way absence is spelled: there are no
-- sentinel values, and no entry never means that adding one was tried and
-- failed
---@type cash.Ledger
local ledger = {}

-- the current-match highlight one window has: the ID matchdelete needs, and
-- the anchored pattern it was built from
---@class cash.CurrentMatchEntry
---@field id integer
---@field matchPattern string

-- which windows this module has given a current-match highlight to. Kept
-- apart from the ledger because it answers a different question -- where the
-- cursor is, rather than what a cash register holds -- and changes on a
-- different beat. Absence is spelled the same way: no entry means no match
---@type table<integer, cash.CurrentMatchEntry|nil>
local currentMatches = {}

-- everything about a window and the cash registers that the match under its
-- cursor depends on. Two of these being equal is the whole reason a look can
-- be skipped, so anything that can change the answer belongs in here
---@class cash.CurrentMatchQuestion
---@field buffer integer
---@field changedtick integer how many times that buffer has been changed
---@field position integer[] where the window's cursor is
---@field signature string what the search set comes to. See signatureOf

-- the last current-match question asked about a window and the answer it got.
--
-- Purely a memo. Unlike the ledger it records nothing that is on screen, so
-- throwing it away costs a little work rather than correctness. It is here
-- because the question is asked every time vim waits for a key, and answering
-- it means searching the buffer: the cheap comparison below is what keeps
-- that off the keystroke path when nothing has moved
---@type table<integer, {question: cash.CurrentMatchQuestion, answer: string|nil}>
local lastLook = {}

-- wrapper for matchdelete that will not throw an error. A failure here almost
-- always means the match already went away with its window, so it is not worth
-- reporting
---@param matchID integer
---@param windowID integer
local deleteMatch = function(matchID, windowID)
    pcall(vim.fn.matchdelete, matchID, windowID)
end

-- the pattern that the index-th cash register should be highlighting in every
-- window right now, or nil if it should not be highlighted at all
---@param cashRegisters cash.Register[]
---@param currentIndex cash.RegisterIndex
---@param index cash.RegisterIndex
---@return string|nil matchPattern
local desiredPattern = function(cashRegisters, currentIndex, index)
    -- the working cash register is highlighted by vim's own Search highlight,
    -- not by a match, so that hlsearch and :nohlsearch keep working normally
    if index == currentIndex then
        return nil
    end

    local pattern = cashRegisters[index].pattern
    if pattern == '' then
        return nil
    end

    local matchPattern = util.resolveCase(pattern)

    -- a cash register holds whatever the user typed, which includes patterns
    -- vim cannot compile. Those highlight nothing because vim has already
    -- complained about the search itself
    if not util.isUsablePattern(matchPattern) then
        return nil
    end

    return matchPattern
end

-- adds a match to one window. Returns the match ID or nil. The pattern has
-- already been checked, so a refusal here is about the window rather than the
-- pattern, and sorts itself out on the next update
---@param group string the highlight group to paint the match in
---@param priority integer
---@param windowID integer
---@param matchPattern string
---@return integer|nil matchID
local addMatch = function(group, priority, windowID, matchPattern)
    local addOK, matchID = pcall(
        vim.fn.matchadd,
        group,
        matchPattern,
        priority,
        -1, -- automatically choose ID
        { window = windowID }
    )

    if not addOK or matchID == nil or matchID == -1 then
        return nil
    end

    return matchID
end

-- vim gives its own search highlighting priority 0, so a cash register sits
-- just under it: where two of them match the same text, the working one is the
-- one you see
local registerPriority = -1

-- the current match sits above both, because it is the one thing on screen
-- that says where you are. It is the only highlight this plugin puts above
-- vim's own
local currentMatchPriority = 1

-- the anchored pattern for the match under the cursor in the current window,
-- or nil when the cursor is not on one. For a window that is not the current
-- one, call this from inside nvim_win_call.
--
-- The working cash register is left out. Its pattern is in @/, so vim already
-- paints its current match, in the same CurSearch highlight and without being
-- asked.
--
-- The pattern is anchored to where the match starts, with \%23l\%5c, rather
-- than its extent being measured here. Vim then works the extent out itself,
-- which is what makes a multi-line or multi-byte match come out right without
-- any arithmetic. The \%(\) around it is not decoration: without it the
-- anchors would bind to the first branch alone of a pattern like foo\|bar.
--
-- The look back for a match starting before the cursor stops at the top of the
-- window. This runs every time vim waits for a key, and letting it scan to the
-- top of the buffer costs milliseconds per keystroke in a large one. What it
-- gives up is a match that begins above the window and reaches down over the
-- cursor, which takes a pattern matching across lines to arrive at
---@param searchable cash.SearchablePattern[]
---@param currentIndex cash.RegisterIndex
---@return string|nil matchPattern
local currentMatchPattern = function(searchable, currentIndex)
    -- line() and col() rather than nvim_win_get_cursor, because they count
    -- columns from 1, which is how searchpos answers
    local position = { vim.fn.line('.'), vim.fn.col('.') }
    local topLine = vim.fn.line('w0')

    for _, entry in ipairs(searchable) do
        if entry.index ~= currentIndex then
            local start =
                cursor.matchStart(entry.matchPattern, position, topLine)
            if start ~= nil then
                return string.format(
                    '\\%%%dl\\%%%dc\\%%(%s\\)',
                    start[1],
                    start[2],
                    entry.matchPattern
                )
            end
        end
    end

    return nil
end

-- the working cash register is shown using vim's Search highlight
---@param currentIndex cash.RegisterIndex
local setSearchHighlight = function(currentIndex)
    -- colors is nil when the plugin is not set up yet
    if colors == nil then
        return
    end
    local color = colors.highlightColors[currentIndex]
    vim.api.nvim_set_hl(0, 'Search', {
        fg = color.fg or colors.defaultFG,
        bg = color.bg or colors.defaultBG,
    })
end

-- forgets what is recorded about windows that no longer exist. Their matches
-- went away with them, so there is nothing to delete
---@param liveWindows table<integer, boolean> every window that still exists
local pruneClosedWindows = function(liveWindows)
    for windowID in pairs(ledger) do
        if not liveWindows[windowID] then
            ledger[windowID] = nil
        end
    end

    for windowID in pairs(currentMatches) do
        if not liveWindows[windowID] then
            currentMatches[windowID] = nil
        end
    end

    for windowID in pairs(lastLook) do
        if not liveWindows[windowID] then
            lastLook[windowID] = nil
        end
    end
end

-- brings one window's current-match highlight in line with what it should be,
-- the same way the cash registers' own matches are dealt with: a match built
-- from a pattern that has since changed is dropped, and one that is wanted and
-- not there is added
---@param windowID integer
---@param wanted string|nil the anchored pattern, or nil for no highlight
local setCurrentMatch = function(windowID, wanted)
    local existing = currentMatches[windowID]

    if
        existing ~= nil
        and (wanted == nil or existing.matchPattern ~= wanted)
    then
        deleteMatch(existing.id, windowID)
        currentMatches[windowID] = nil
        existing = nil
    end

    if existing == nil and wanted ~= nil then
        local matchID =
            addMatch('CurSearch', currentMatchPriority, windowID, wanted)
        if matchID ~= nil then
            currentMatches[windowID] = { id = matchID, matchPattern = wanted }
        end
    end
end

-- everything about the search set that can change where the current match is,
-- as one string, so that the memo notices a change to any of it. The resolved
-- patterns are in here rather than the raw ones, which is what makes a change
-- to ignorecase count as a change
---@param searchable cash.SearchablePattern[]
---@param currentIndex cash.RegisterIndex
---@return string
local signatureOf = function(searchable, currentIndex)
    local parts = { tostring(currentIndex) }

    for _, entry in ipairs(searchable) do
        table.insert(parts, entry.index .. '=' .. entry.matchPattern)
    end

    return table.concat(parts, ' ')
end

-- the anchored pattern one window's current-match highlight should be built
-- from, or nil when there should not be one.
--
-- The buffer, how many times it has been changed, and where the cursor is are
-- between them everything about the window that the answer depends on; the
-- signature is everything about the cash registers that it depends on. Asked
-- the same question as last time, the memo answers it, and the searches are
-- not run again
---@param windowID integer
---@param searchable cash.SearchablePattern[]
---@param currentIndex cash.RegisterIndex
---@param signature string
---@return string|nil matchPattern
local desiredCurrentMatch = function(
    windowID,
    searchable,
    currentIndex,
    signature
)
    local askedOK, question = pcall(function()
        local buffer = vim.api.nvim_win_get_buf(windowID)

        return {
            buffer = buffer,
            changedtick = vim.api.nvim_buf_get_changedtick(buffer),
            position = vim.api.nvim_win_get_cursor(windowID),
            signature = signature,
        }
    end)

    -- a window that cannot be asked where its cursor is has gone, and the next
    -- update will forget it
    if not askedOK then
        return nil
    end

    local remembered = lastLook[windowID]
    if remembered ~= nil and vim.deep_equal(remembered.question, question) then
        return remembered.answer
    end

    local lookedOK, answer = pcall(vim.api.nvim_win_call, windowID, function()
        return currentMatchPattern(searchable, currentIndex)
    end)

    answer = lookedOK and answer or nil
    lastLook[windowID] = { question = question, answer = answer }

    return answer
end

-- makes this true, in each of the given windows:
--
--     window W has a current-match highlight exactly when v:hlsearch is on and
--     W's cursor is on a match of a cash register that is in the search set
--     and is not the working one
--
---@param searchable cash.SearchablePattern[]
---@param currentIndex cash.RegisterIndex
---@param windows integer[]
local updateCurrentMatches = function(searchable, currentIndex, windows)
    -- whether there is anything here for a current match to be found in. The
    -- working cash register is not: vim paints its current match itself. So
    -- this is false for every search that never touches includeInSearch, which
    -- is what keeps the whole thing off the keystroke path by default
    local anyIncluded = false
    for _, entry in ipairs(searchable) do
        if entry.index ~= currentIndex then
            anyIncluded = true
            break
        end
    end

    -- the current match follows v:hlsearch like everything else this plugin
    -- draws, so :nohlsearch takes it away with the rest
    local wantAny = anyIncluded and vim.v.hlsearch ~= 0
    local signature = wantAny and signatureOf(searchable, currentIndex) or ''

    for _, windowID in ipairs(windows) do
        local wanted = nil
        if wantAny then
            wanted = desiredCurrentMatch(
                windowID,
                searchable,
                currentIndex,
                signature
            )
        end

        setCurrentMatch(windowID, wanted)
    end
end

-- a cash register's color as a foreground, for the places in the drawer where
-- a full swatch would be too heavy: the include dot and the match count.
--
-- A color chosen to be a background is not necessarily legible as a
-- foreground. waveBlue2, cash register 9's default, is dark enough to carry
-- light text but nearly invisible as text itself, so anything too dark is
-- lightened until it is not. Blending toward white raises perceived brightness
-- by exactly the amount blended, which is what makes the arithmetic this short
---@param hex string a color as #RRGGBB
---@return string
local readableForeground = function(hex)
    local red = tonumber(hex:sub(2, 3), 16)
    local green = tonumber(hex:sub(4, 5), 16)
    local blue = tonumber(hex:sub(6, 7), 16)

    -- the usual weighting for perceived brightness, 0 for black and 1 for
    -- white
    local brightness = (0.299 * red + 0.587 * green + 0.114 * blue) / 255

    local floor = 0.55
    if brightness < floor then
        local blend = (floor - brightness) / (1 - brightness)
        red = red + (255 - red) * blend
        green = green + (255 - green) * blend
        blue = blue + (255 - blue) * blend
    end

    return string.format(
        '#%02X%02X%02X',
        math.floor(red + 0.5),
        math.floor(green + 0.5),
        math.floor(blue + 0.5)
    )
end

-- stores the colors and creates the highlight group for each cash register
---@param colorOpts cash.ResolvedColorOptions
highlights.setup = function(colorOpts)
    colors = colorOpts

    for index = 1, 9 do
        local bg = colors.highlightColors[index].bg or colors.defaultBG
        local fg = colors.highlightColors[index].fg or colors.defaultFG
        vim.cmd.highlight(
            'CashRegister' .. index,
            'guibg=' .. bg .. ' guifg=' .. fg
        )

        -- the same color as text rather than as a swatch
        vim.cmd.highlight(
            'CashRegisterFg' .. index,
            'guifg=' .. readableForeground(bg)
        )
    end
end

-- makes this true, in every window:
--
--     window W has a highlight for cash register i exactly when v:hlsearch is
--     on, i is not the working cash register, and cash register i's pattern is
--     not empty
--
-- and this, which is about where the cursor is rather than what the cash
-- registers hold:
--
--     window W has a current-match highlight exactly when v:hlsearch is on and
--     W's cursor is on a match of a cash register that is in the search set
--     and is not the working one
--
-- Safe to call at any time and as often as you like; a call that finds nothing
-- out of place does not touch vim at all
---@param cashRegisters cash.Register[]
---@param currentIndex cash.RegisterIndex
---@param searchable cash.SearchablePattern[] the search set, minus the cash
--- registers there is nothing to find in. See jump.searchablePatterns
highlights.update = function(cashRegisters, currentIndex, searchable)
    -- the working cash register's color comes from the Search highlight
    setSearchHighlight(currentIndex)

    -- :nohlsearch turns v:hlsearch off, and the cash registers go with it.
    -- Vim only ever applied that to the working one, since the other eight are
    -- matches rather than hlsearch; following the same flag is what makes
    -- :nohlsearch mean "clear the search highlighting", all nine of them
    local highlightingIsOn = vim.v.hlsearch ~= 0

    -- ask vim which windows exist. Note that this covers all windows in all
    -- tabs.
    --
    -- The drawer's own window is left out. Its buffer holds the search
    -- patterns as literal text, so matching them there would paint the drawer
    -- in the very colors it is trying to explain.
    --
    -- The mark is on the buffer rather than the window because nvim_open_win
    -- fires WinNew and WinEnter before it returns, so an update runs while a
    -- window-local mark would still be unset. The buffer is made first, and
    -- can be marked before anything can look at it
    local liveWindows = {}
    local windowOrder = {}
    for _, windowID in ipairs(vim.api.nvim_list_wins()) do
        local isDrawer = pcall(
            vim.api.nvim_buf_get_var,
            vim.api.nvim_win_get_buf(windowID),
            'cashDrawer'
        )
        if not isDrawer then
            liveWindows[windowID] = true
            table.insert(windowOrder, windowID)
        end
    end

    pruneClosedWindows(liveWindows)

    for windowID in pairs(liveWindows) do
        local matches = ledger[windowID]
        if matches == nil then
            matches = {}
            ledger[windowID] = matches
        end

        for index = 1, 9 do
            local wanted = nil
            if highlightingIsOn then
                wanted = desiredPattern(cashRegisters, currentIndex, index)
            end
            local existing = matches[index]

            -- drop a match that is no longer wanted, or that was built from a
            -- pattern which has since changed. Comparing the resolved pattern
            -- means a change to ignorecase is picked up here too
            if
                existing ~= nil
                and (wanted == nil or existing.matchPattern ~= wanted)
            then
                deleteMatch(existing.id, windowID)
                matches[index] = nil
                existing = nil
            end

            -- add the match if it is wanted and is not already there
            if existing == nil and wanted ~= nil then
                local matchID = addMatch(
                    'CashRegister' .. index,
                    registerPriority,
                    windowID,
                    wanted
                )
                if matchID ~= nil then
                    matches[index] = { id = matchID, matchPattern = wanted }
                end
            end
        end
    end

    updateCurrentMatches(searchable, currentIndex, windowOrder)
end

-- the current match on its own, for the windows this module already knows
-- about.
--
-- The cursor moves for all sorts of reasons -- n, j, a click, a fold opening,
-- an undo -- and every one of them can put it on or off a match, so this is
-- asked for every time vim waits for a key rather than from an event for each
-- of them. That is affordable because it is nearly always a comparison and
-- nothing more: see the memo above.
--
-- Windows are taken from the ledger rather than asked for again, so a window
-- opened since the last full update has no current match until the WinNew or
-- WinEnter that brings it into the ledger, which happens in the same breath
---@param searchable cash.SearchablePattern[]
---@param currentIndex cash.RegisterIndex
highlights.updateCurrentMatch = function(searchable, currentIndex)
    updateCurrentMatches(searchable, currentIndex, highlights.trackedWindows())
end

-- the windows the ledger is keeping track of.
--
-- The ledger is private, and stays that way. This exists because whether a
-- closed window has been forgotten is not observable from anywhere else, and
-- that is worth a test
---@return integer[]
highlights.trackedWindows = function()
    local windows = {}

    for windowID in pairs(ledger) do
        table.insert(windows, windowID)
    end

    table.sort(windows)
    return windows
end

return highlights
