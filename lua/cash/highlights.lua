local util = require('cash.util')

local highlights = {}

-- colors for the 9 cash registers. Set once during setup
local colors = nil

-- record of the matches this module has added to each window. An index with no
-- entry has no match.
-- Data format: ledger[windowID][index] = { id = <match ID>, matchPattern = <string> }
local ledger = {}

-- wrapper for matchdelete that will not throw an error. A failure here almost
-- always means the match already went away with its window, so it is not worth
-- reporting
local deleteMatch = function(matchID, windowID)
    pcall(vim.fn.matchdelete, matchID, windowID)
end

-- the pattern that the index-th cash register should be highlighting in every
-- window right now, or nil if it should not be highlighted at all
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
local addMatch = function(index, windowID, matchPattern)
    local addOK, matchID = pcall(
        vim.fn.matchadd,
        'CashRegister' .. index,
        matchPattern,
        -1, -- use priority lower than search
        -1, -- automatically choose ID
        { window = windowID }
    )

    if not addOK or matchID == nil or matchID == -1 then
        return nil
    end

    return matchID
end

-- the working cash register is shown using vim's Search highlight
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

-- forgets the ledger entries for windows that no longer exist. Their matches
-- went away with them, so there is nothing to delete
local pruneClosedWindows = function(liveWindows)
    for windowID in pairs(ledger) do
        if not liveWindows[windowID] then
            ledger[windowID] = nil
        end
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
-- Safe to call at any time and as often as you like; a call that finds nothing
-- out of place does not touch vim at all
highlights.update = function(cashRegisters, currentIndex)
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
    for _, windowID in ipairs(vim.api.nvim_list_wins()) do
        local isDrawer = pcall(
            vim.api.nvim_buf_get_var,
            vim.api.nvim_win_get_buf(windowID),
            'cashDrawer'
        )
        if not isDrawer then
            liveWindows[windowID] = true
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
                local matchID = addMatch(index, windowID, wanted)
                if matchID ~= nil then
                    matches[index] = { id = matchID, matchPattern = wanted }
                end
            end
        end
    end
end

-- the windows the ledger is keeping track of.
--
-- The ledger is private, and stays that way. This exists because whether a
-- closed window has been forgotten is not observable from anywhere else, and
-- that is worth a test
highlights.trackedWindows = function()
    local windows = {}

    for windowID in pairs(ledger) do
        table.insert(windows, windowID)
    end

    table.sort(windows)
    return windows
end

return highlights
