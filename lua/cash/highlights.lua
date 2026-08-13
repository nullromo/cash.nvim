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

-- works out the pattern that vim should actually be asked to match, which is
-- the cash register's pattern plus a case flag. An explicit \c or \C in the
-- pattern wins, and makes the value of ignorecase irrelevant
local resolveCase = function(pattern)
    if string.find(pattern, '\\c') or string.find(pattern, '\\C') then
        return pattern
    end
    return (vim.opt.ignorecase:get() and '\\c' or '\\C') .. pattern
end

-- the pattern that the index-th cash register should be highlighting in every
-- window right now, or nil if it should not be highlighted at all
local desiredPattern = function(cashRegisters, currentIndex, index)
    -- the working cash register is highlighted by vim's own Search highlight,
    -- not by a match, so that hlsearch and :nohlsearch keep working normally
    if index == currentIndex then
        return nil
    end

    local pattern = cashRegisters[index]
    if pattern == nil or pattern == '' then
        return nil
    end

    local matchPattern = resolveCase(pattern)

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
    end
end

-- makes this true, in every window:
--
--     window W has a highlight for cash register i exactly when i is not the
--     working cash register and cash register i's pattern is not empty
--
-- Safe to call at any time and as often as you like; a call that finds nothing
-- out of place does not touch vim at all
highlights.update = function(cashRegisters, currentIndex)
    -- the working cash register's color comes from the Search highlight
    setSearchHighlight(currentIndex)

    -- ask vim which windows exist. Note that this covers all windows in all
    -- tabs
    local liveWindows = {}
    for _, windowID in ipairs(vim.api.nvim_list_wins()) do
        liveWindows[windowID] = true
    end

    pruneClosedWindows(liveWindows)

    for windowID in pairs(liveWindows) do
        local matches = ledger[windowID]
        if matches == nil then
            matches = {}
            ledger[windowID] = matches
        end

        for index = 1, 9 do
            local wanted = desiredPattern(cashRegisters, currentIndex, index)
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

-- human-readable dump of the ledger, for printDebugInfo
highlights.debugInfo = function()
    local lines = {}

    for windowID, matches in pairs(ledger) do
        local entries = {}
        for index = 1, 9 do
            local entry = matches[index]
            table.insert(entries, entry == nil and 'nil' or tostring(entry.id))
        end
        table.insert(
            lines,
            '\twindow ' .. windowID .. ': ' .. table.concat(entries, ', ')
        )
    end

    return table.concat(lines, '\n')
end

return highlights
