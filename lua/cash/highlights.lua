local cursor = require('cash.cursor')
local util = require('cash.util')

local highlights = {}

-- colors for the 9 cash registers. Set once during setup
---@type cash.ResolvedColorOptions|nil
local colors = nil

-- the namespace the cash registers are painted in, and the one the decoration
-- provider that paints them is registered under. One namespace for both,
-- because an ephemeral extmark belongs to the redraw its provider was called
-- for and to nothing else
local namespace = vim.api.nvim_create_namespace('cash.highlights')

-- what the decoration provider paints from: the pattern each cash register
-- should be showing, worked out once by highlights.update rather than again on
-- every line of every redraw.
--
-- A cash register with nothing to show is absent rather than present and empty,
-- and the working one is always absent, because it is painted by vim's own
-- Search highlight. See desiredPattern
---@class cash.Painting
---@field patterns table<cash.RegisterIndex, string>

-- nil until highlights.update has run, which is how "nobody has said what to
-- paint yet" is spelled. Nothing is painted then
---@type cash.Painting|nil
local painting = nil

-- the patterns the window vim is drawing is being painted with, put here by the
-- decoration provider's on_win so that on_line does not work them out again for
-- every line. nil between redraws, and for a window that is not painted at all
---@type table<cash.RegisterIndex, string>|nil
local paintingThisWindow = nil

-- compiled patterns, keyed by the resolved pattern each was compiled from.
--
-- Compiling is the expensive half of matching, and the provider needs every
-- pattern again on every line it paints, so the answers are kept. A resolved
-- pattern always compiles to the same thing, so an entry here cannot go stale
-- and there is nothing to invalidate. false rather than absent for a pattern
-- vim will not compile, so that a refusal is remembered as well
---@type table<string, vim.regex|false>
local compiled = {}

-- how many patterns the cache holds, and how many is too many. Nine cash
-- registers cannot be holding more than nine patterns at once, so anything past
-- this is a long session's history rather than anything in use, and the cache
-- is emptied rather than grown
local compiledCount = 0
local compiledLimit = 64

-- the highlight group each cash register is painted in, built once. Nine string
-- concatenations rather than one for every cash register of every line of every
-- redraw
---@type string[]
local groupNames = {}
for index = 1, 9 do
    groupNames[index] = 'CashRegister' .. index
end

-- the current-match highlight one window has: the ID matchdelete needs, and
-- the anchored pattern it was built from
---@class cash.CurrentMatchEntry
---@field id integer
---@field matchPattern string

-- which windows this module has given a current-match highlight to. Absence is
-- spelled the way it is everywhere else here: no entry means no match
---@type table<integer, cash.CurrentMatchEntry|nil>
local currentMatches = {}

-- the windows this module is keeping track of: every window it would paint in,
-- as of the last full update.
--
-- Nothing about the cash registers' own painting needs this, since a
-- decoration provider is handed the window it is painting. It is here because
-- the current match is per window and is kept up to date on its own, which
-- means knowing which windows there are without asking vim again
---@type table<integer, boolean|nil>
local knownWindows = {}

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
-- Purely a memo. Unlike the current matches themselves it records nothing that
-- is on screen, so throwing it away costs a little work rather than
-- correctness. It is here because the question is asked every time vim waits
-- for a key, and answering it means searching the buffer: the cheap comparison
-- below is what keeps that off the keystroke path when nothing has moved
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

-- the pattern that the index-th cash register should be showing, or nil if it
-- should not be showing anything at all
---@param cashRegisters cash.Register[]
---@param currentIndex cash.RegisterIndex
---@param index cash.RegisterIndex
---@return string|nil matchPattern
local desiredPattern = function(cashRegisters, currentIndex, index)
    -- the working cash register is highlighted by vim's own Search highlight,
    -- not by this plugin, so that hlsearch and :nohlsearch keep working
    -- normally
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

-- the pattern each cash register should be painting right now.
--
-- The patterns themselves are the ones highlights.update worked out. What is
-- decided here is whether to paint at all, and v:hlsearch is read rather than
-- remembered because this runs at redraw time: a :nohlsearch is off the screen
-- the moment vim next draws, without anything having to tell this module
---@return table<cash.RegisterIndex, string>
local desiredPatterns = function()
    if painting == nil then
        return {}
    end

    -- :nohlsearch turns v:hlsearch off, and the cash registers go with it. Vim
    -- only ever applied that to the working one, since the other eight are
    -- this plugin's painting rather than hlsearch; following the same flag is
    -- what makes :nohlsearch mean "clear the search highlighting", all nine of
    -- them
    if vim.v.hlsearch == 0 then
        return {}
    end

    return painting.patterns
end

-- how many bytes one line of a buffer holds, or nil when the buffer cannot
-- answer.
--
-- The line itself is not wanted, only how far along it there is any point
-- looking, and building the string to find that out costs an allocation per
-- line of every redraw. nvim_buf_get_offset counts each line's newline and
-- treats the last line as having one, so the gap between two lines' offsets is
-- the line plus that newline
---@param buffer integer
---@param row integer 0-based
---@return integer|nil
local lineLengthOf = function(buffer, row)
    local start = vim.api.nvim_buf_get_offset(buffer, row)
    local following = vim.api.nvim_buf_get_offset(buffer, row + 1)

    -- -1 from both when the buffer has no offset index to answer from
    if start < 0 or following < 0 then
        return nil
    end

    return following - start - 1
end

-- the compiled form of one resolved pattern, or nil when vim will not compile
-- it. See the cache above
---@param matchPattern string
---@return vim.regex|nil
local regexFor = function(matchPattern)
    local remembered = compiled[matchPattern]
    if remembered ~= nil then
        return remembered or nil
    end

    if compiledCount >= compiledLimit then
        compiled = {}
        compiledCount = 0
    end

    local compileOK, regex = pcall(vim.regex, matchPattern)
    compiled[matchPattern] = compileOK and regex or false
    compiledCount = compiledCount + 1

    return compileOK and regex or nil
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

-- where a cash register sits among the extmarks that could be covering the same
-- text.
--
-- Only extmarks. Vim's own search highlighting is a match, and a match covers
-- an extmark whatever priority the extmark was given, which is what keeps the
-- working cash register the one you see where two of them agree.
--
-- The number is above the 4096 that coc.nvim clamps its own highlights to and
-- well above the 100 or so that treesitter and the built-in semantic token
-- support use, so a syntax highlight cannot take a cash register's color away.
-- What those highlights say and a cash register does not -- bold, italic, an
-- underline -- is merged in rather than dropped, which is the whole reason
-- these are extmarks and not matches. See issue #13
local registerPriority = 5000

-- the current match sits above everything, including vim's own search
-- highlighting: it is the one thing on screen that says where you are. Only a
-- match can do that, since vim gives its own search highlighting priority 0 and
-- only a match above 0 overrules it, so this one highlight stays a match while
-- the cash registers are extmarks
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

-- the working cash register is shown using vim's Search highlight.
--
-- Which is why it is the one cash register whose color another plugin's
-- highlighting cannot be combined with: vim's search highlighting is a match,
-- and a match takes the text whole. Making it paint nothing does not hand the
-- text back either, so the only way out would be to stop using hlsearch for
-- this cash register, and that is what keeps :nohlsearch working for all nine.
-- See CONTEXT.md
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
    for windowID in pairs(knownWindows) do
        if not liveWindows[windowID] then
            knownWindows[windowID] = nil
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

-- brings one window's current-match highlight in line with what it should be:
-- a match built from a pattern that has since changed is dropped, and one that
-- is wanted and not there is added
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

-- one highlight this module paints: which cash register asked for it, the group
-- to paint it in, and where on the line it goes. Both columns are byte columns
-- counted from 0, and the end is the column the highlight stops before, which
-- is what nvim_buf_set_extmark's end_col means
---@class cash.Paint
---@field index cash.RegisterIndex
---@field group string
---@field startColumn integer
---@field endColumn integer

-- whether this plugin leaves a buffer alone.
--
-- The drawer, the chooser and the telescope picker all hold the search
-- patterns as literal text, so matching them there would paint the list in the
-- very colors it is trying to explain.
--
-- The mark is on the buffer rather than the window because nvim_open_win fires
-- WinNew and WinEnter before it returns, so an update can run while a
-- window-local mark would still be unset. The buffer is made first, and can be
-- marked before anything can look at it
---@param buffer integer
---@return boolean
highlights.isExcluded = function(buffer)
    return (pcall(vim.api.nvim_buf_get_var, buffer, 'cashDrawer'))
end

-- which cash registers this plugin is painting in a window, as the pattern each
-- of them is painting.
--
-- About intent rather than about what is on screen: a cash register is in here
-- whether or not the window happens to be showing any of its matches. Public
-- because a cash register's painting leaves nothing behind to look at
-- afterwards, so this is the only way to ask what is lit
---@param windowID? integer the current window when left out
---@return table<cash.RegisterIndex, string>
highlights.litCashRegisters = function(windowID)
    local gotBuffer, buffer = pcall(vim.api.nvim_win_get_buf, windowID or 0)

    if not gotBuffer or highlights.isExcluded(buffer) then
        return {}
    end

    -- a copy, because the answer is the table the provider paints from
    local lit = {}
    for index, matchPattern in pairs(desiredPatterns()) do
        lit[index] = matchPattern
    end

    return lit
end

-- adds every match of one cash register's pattern on one line to paints
---@param paints cash.Paint[] added to in place
---@param index cash.RegisterIndex
---@param regex vim.regex
---@param buffer integer
---@param row integer 0-based
---@param length integer how many bytes the line holds
local scanLine = function(paints, index, regex, buffer, row, length)
    local group = groupNames[index]
    local from = 0

    -- from is never past the end of the line: a match cannot end past it, and
    -- a match with no extent steps one byte and is checked again here
    while from <= length do
        local startColumn, endColumn = regex:match_line(buffer, row, from)

        if startColumn == nil then
            return
        end

        -- the columns come back relative to where the search started
        startColumn = from + startColumn
        endColumn = from + endColumn

        if endColumn > startColumn then
            table.insert(paints, {
                index = index,
                group = group,
                startColumn = startColumn,
                endColumn = endColumn,
            })
            from = endColumn
        else
            -- a pattern matching without covering anything -- ^, \<, ^\s* on a
            -- line with no indent -- has nothing to paint and nothing to move
            -- past either, so it is stepped over rather than asked again
            -- forever. Vim paints nothing for those, and neither does this
            from = startColumn + 1
        end
    end
end

-- every cash register highlight one line of a buffer should hold, given the
-- patterns to paint it with.
--
-- Split from paintsFor because the provider below has already settled the
-- patterns once for the window it is drawing, and settling them again for every
-- line of it means asking vim about v:hlsearch and about the buffer's marks
-- forty times over
---@param buffer integer
---@param row integer 0-based
---@param wanted table<cash.RegisterIndex, string>
---@return cash.Paint[]
local paintsWith = function(buffer, row, wanted)
    local paints = {}

    local length = lineLengthOf(buffer, row)
    if length == nil or length == 0 then
        return paints
    end

    -- lowest cash register first, so that where two of them match the same
    -- text the higher-numbered one is painted over it. Extmarks of equal
    -- priority are settled by the order they were added, and going in index
    -- order is what makes that the same answer every time rather than whichever
    -- cash register was written to most recently
    for index = 1, 9 do
        local matchPattern = wanted[index]
        local regex = matchPattern ~= nil and regexFor(matchPattern) or nil

        if regex ~= nil then
            scanLine(paints, index, regex, buffer, row, length)
        end
    end

    return paints
end

-- every cash register highlight one line of a buffer should hold.
--
-- The whole painting decision, and the decoration provider below is a shell
-- around it. Public for the same reason litCashRegisters is: an ephemeral
-- extmark is gone by the time anything could read it, so a test that wants to
-- know what a line is painted has to ask rather than look.
--
-- Matching is line by line, which is what gives up a pattern needing more than
-- the line it is on: one reaching across a line break, and one anchored to a
-- position -- \%23l, \%>10l, \%#, \%V. Vim's own regex engine is doing the
-- matching either way, so nothing else about pattern semantics changes; what
-- this decides is only which lines to run it on, and the answer is the ones vim
-- is about to draw
---@param buffer integer
---@param row integer 0-based
---@return cash.Paint[]
highlights.paintsFor = function(buffer, row)
    if highlights.isExcluded(buffer) then
        return {}
    end

    local wanted = desiredPatterns()
    if next(wanted) == nil then
        return {}
    end

    -- one pcall for the line, rather than one for every cash register on it. A
    -- pattern that compiled can still fail against a particular line by running
    -- out of the room 'maxmempattern' allows, and a row that does not exist can
    -- be asked for from out here; neither is worth reporting, and neither is
    -- worth paying for on every line of every redraw
    local askedOK, paints = pcall(paintsWith, buffer, row, wanted)

    return askedOK and paints or {}
end

-- puts one line's highlights on screen.
--
-- An ephemeral extmark rather than a stored one: it is added while vim is
-- drawing the line and is gone when the redraw ends, so there is never a mark
-- to move, delete, or reconcile against an edit
---@param buffer integer
---@param row integer 0-based
---@param paints cash.Paint[]
local paintLine = function(buffer, row, paints)
    for _, paint in ipairs(paints) do
        vim.api.nvim_buf_set_extmark(
            buffer,
            namespace,
            row,
            paint.startColumn,
            {
                end_col = paint.endColumn,
                hl_group = paint.group,
                priority = registerPriority,
                ephemeral = true,
            }
        )
    end
end

-- works one line out and paints it. One function so that one pcall covers
-- both, since a failure in either leaves the same nothing on screen
---@param buffer integer
---@param row integer 0-based
---@param wanted table<cash.RegisterIndex, string>
local paintRow = function(buffer, row, wanted)
    paintLine(buffer, row, paintsWith(buffer, row, wanted))
end

-- paints the cash registers, and is the only thing that does.
--
-- A decoration provider rather than a match per cash register per window,
-- because two matches covering the same text never blend: exactly one of them
-- is painted, and the other is dropped whole. An extmark is combined with
-- whatever else has something to say about the same text instead, so a cash
-- register's color survives a semantic token that only asks for bold. That is
-- issue #13, and it is not something a priority can fix.
--
-- What this costs is a regex over the lines vim is about to draw, on the redraw
-- path, plus an extmark per match. That is the same matching vim was doing for
-- the matches this replaces and about half as much again for the extmarks:
-- measured against eight cash registers whose patterns all match every visible
-- line, a forced full redraw went from 1.0ms to 1.7ms over a baseline of 0.4ms.
-- Returning false from on_win is what keeps it to nothing at all until there is
-- something to paint, which is every session until the first search
local registerProvider = function()
    vim.api.nvim_set_decoration_provider(namespace, {
        on_win = function(_, _, buffer, _, _)
            -- what this window is being painted with, worked out once here
            -- rather than again for each of its lines. nil is on_line's way of
            -- being told there is nothing to do, for the redraw where vim calls
            -- it anyway
            paintingThisWindow = nil

            -- false means vim does not call on_line for this window at all,
            -- which is what keeps a session with nothing to paint -- every
            -- session until the first search -- off the redraw path
            if highlights.isExcluded(buffer) then
                return false
            end

            local wanted = desiredPatterns()
            if next(wanted) == nil then
                return false
            end

            paintingThisWindow = wanted
            return true
        end,

        on_line = function(_, _, buffer, row)
            local wanted = paintingThisWindow
            if wanted == nil then
                return
            end

            -- one pcall for the line. See paintsFor
            pcall(paintRow, buffer, row, wanted)
        end,
    })
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

-- stores the colors, creates the highlight group for each cash register, and
-- puts the decoration provider in place
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

    -- setting a provider for a namespace that already has one replaces it, so
    -- this is safe to call again, which the ColorScheme event does
    registerProvider()
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
-- The first of those is settled by handing the decoration provider the patterns
-- and letting the next redraw paint them, which is why nothing here walks the
-- windows for it. The second is a match, and matches belong to windows, so that
-- half still does.
--
-- Safe to call at any time and as often as you like
---@param cashRegisters cash.Register[]
---@param currentIndex cash.RegisterIndex
---@param searchable cash.SearchablePattern[] the search set, minus the cash
--- registers there is nothing to find in. See jump.searchablePatterns
highlights.update = function(cashRegisters, currentIndex, searchable)
    -- the working cash register's color comes from the Search highlight
    setSearchHighlight(currentIndex)

    -- worked out here, once, rather than on every line of every redraw:
    -- resolving a pattern's case and asking vim whether it will compile are
    -- both too expensive to be on the redraw path
    local patterns = {}
    for index = 1, 9 do
        local matchPattern = desiredPattern(cashRegisters, currentIndex, index)
        if matchPattern ~= nil then
            patterns[index] = matchPattern
        end
    end
    painting = { patterns = patterns }

    -- ask vim which windows exist. Note that this covers all windows in all
    -- tabs. The ones this plugin leaves alone are left out, so that a current
    -- match cannot land in a list of patterns either
    local liveWindows = {}
    local windowOrder = {}
    for _, windowID in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(windowID)
        if not highlights.isExcluded(buffer) then
            liveWindows[windowID] = true
            knownWindows[windowID] = true
            table.insert(windowOrder, windowID)
        end
    end

    pruneClosedWindows(liveWindows)

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
-- Windows are taken from what this module is already tracking rather than asked
-- for again, so a window opened since the last full update has no current match
-- until the WinNew or WinEnter that brings it in, which happens in the same
-- breath
---@param searchable cash.SearchablePattern[]
---@param currentIndex cash.RegisterIndex
highlights.updateCurrentMatch = function(searchable, currentIndex)
    updateCurrentMatches(searchable, currentIndex, highlights.trackedWindows())
end

-- the windows this module is keeping track of.
--
-- The record is private, and stays that way. This exists because whether a
-- closed window has been forgotten is not observable from anywhere else, and
-- that is worth a test
---@return integer[]
highlights.trackedWindows = function()
    local windows = {}

    for windowID in pairs(knownWindows) do
        table.insert(windows, windowID)
    end

    table.sort(windows)
    return windows
end

return highlights
