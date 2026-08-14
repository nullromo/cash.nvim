-- n and N, when more than one cash register is in play.
--
-- Vim's own n reads @/, and @/ also drives hlsearch, which is how the working
-- cash register gets its color. Putting foo\|bar in @/ to make n visit both
-- would therefore paint them the same color -- the one thing this plugin
-- exists to prevent -- so the union pattern is never built. Each cash register
-- is asked separately where its next match is, and the closest answer wins.
--
-- Keeping them apart is not only about color. \c and \C apply to a whole
-- pattern wherever they are written, group or no group, so one cash register
-- with an explicit \C would otherwise decide the case sensitivity of all of
-- them. See util.resolveCase.

local util = require('cash.util')

local jump = {}

-- the cash registers whose matches n and N move between. The working cash
-- register is always one of them: the user has just searched for its pattern,
-- so n has to be able to find it, whatever its own switch says
jump.searchSet = function(cashRegisters, currentIndex)
    local indices = {}

    for index = 1, 9 do
        if index == currentIndex or cashRegisters[index].includeInSearch then
            table.insert(indices, index)
        end
    end

    return indices
end

-- the search set, minus the cash registers there is nothing to find in: the
-- empty ones, and the ones holding a pattern vim cannot compile. Each entry
-- keeps its index, because the caller needs to know whether what is left is
-- just the working cash register
jump.searchablePatterns = function(cashRegisters, currentIndex)
    local searchable = {}

    for _, index in ipairs(jump.searchSet(cashRegisters, currentIndex)) do
        local pattern = cashRegisters[index].pattern
        if pattern ~= '' then
            local matchPattern = util.resolveCase(pattern)
            if util.isUsablePattern(matchPattern) then
                table.insert(
                    searchable,
                    { index = index, matchPattern = matchPattern }
                )
            end
        end
    end

    return searchable
end

-- true if position a comes before position b in the buffer
local isBefore = function(a, b)
    if a[1] ~= b[1] then
        return a[1] < b[1]
    end
    return a[2] < b[2]
end

-- the position to move to, and whether getting there meant wrapping round the
-- end of the buffer. Returns nil if there is nowhere to go.
--
-- Everything reachable without wrapping is considered first, so that a cash
-- register with no match ahead of the cursor never drags the jump backwards to
-- one behind it. Only when no register has anything ahead does the search wrap
local nearest = function(searchable, forward)
    local isCloser = forward and isBefore
        or function(a, b)
            return isBefore(b, a)
        end

    local best = nil
    local consider = function(position)
        if position[1] ~= 0 and (best == nil or isCloser(position, best)) then
            best = position
        end
    end

    for _, entry in ipairs(searchable) do
        consider(
            vim.fn.searchpos(entry.matchPattern, forward and 'nW' or 'bnW')
        )
    end
    if best ~= nil then
        return best, false
    end

    -- nothing ahead in any cash register, so wrap -- but only if vim is
    -- willing to, which is what wrapscan says
    if not vim.o.wrapscan then
        return nil, false
    end

    for _, entry in ipairs(searchable) do
        consider(
            vim.fn.searchpos(entry.matchPattern, forward and 'nw' or 'bnw')
        )
    end

    return best, best ~= nil
end

-- vim's own wrap message, which a hand-rolled jump has to produce itself. An
-- 's' in shortmess is the user asking not to see it
local announceWrap = function(forward)
    if string.find(vim.o.shortmess, 's', 1, true) then
        return
    end

    vim.api.nvim_echo({
        {
            forward and 'search hit BOTTOM, continuing at TOP'
                or 'search hit TOP, continuing at BOTTOM',
            'WarningMsg',
        },
    }, false, {})
end

-- vim's own not-found message. Every pattern that was looked for is named,
-- since with a search set there is no single pattern to blame
local announceNotFound = function(searchable)
    local patterns = {}
    for _, entry in ipairs(searchable) do
        table.insert(patterns, entry.matchPattern)
    end

    vim.api.nvim_echo({
        {
            'E486: Pattern not found: ' .. table.concat(patterns, ', '),
            'ErrorMsg',
        },
    }, true, {})
end

-- shows a failure from :normal the way vim would have, without the lua
-- traceback wrapped round it
local echoVimError = function(err)
    local message = tostring(err):match('(E%d+:.*)$') or tostring(err)
    vim.api.nvim_echo({ { message, 'ErrorMsg' } }, true, {})
end

-- moves the cursor the way n does: the jump is recorded so that '' comes back
-- here, and a fold closed over the match is opened
local moveTo = function(position)
    vim.cmd("normal! m'")
    vim.api.nvim_win_set_cursor(0, { position[1], position[2] - 1 })
    vim.cmd('normal! zv')

    -- vim turns search highlighting back on when it jumps, so a jump after
    -- :nohlsearch brings the cash registers back with it
    pcall(function()
        vim.v.hlsearch = 1
    end)
end

-- what n (forward = true) and N (forward = false) do.
--
-- Hands straight back to vim whenever the search set comes down to the working
-- cash register on its own, which is every search that does not use the
-- include-in-search switch. Counts, search offsets, the wrap message, folds
-- and the jumplist then all come from vim itself, so the ordinary case is not
-- a reimplementation of anything
jump.go = function(cash, forward)
    local count = vim.v.count1
    local state = cash.state

    -- the movement about to happen belongs to a search, so autoNoHighlight
    -- should not read it as the user wandering off
    cash.expectSearchMove()

    local searchable =
        jump.searchablePatterns(state.cashRegisters, state.currentIndex)

    if
        #searchable == 0
        or (#searchable == 1 and searchable[1].index == state.currentIndex)
    then
        local ok, err =
            pcall(vim.cmd, 'normal! ' .. count .. (forward and 'n' or 'N'))
        if not ok then
            echoVimError(err)
            return
        end
        cash.centerWindow()
        return
    end

    -- n repeats the direction of the last search; N reverses it
    local goForward = forward == (vim.v.searchforward == 1)
    local wrapped = false

    for _ = 1, count do
        local position, didWrap = nearest(searchable, goForward)
        if position == nil then
            announceNotFound(searchable)
            return
        end
        moveTo(position)
        wrapped = wrapped or didWrap
    end

    -- centered before anything is said, because the scroll redraws the screen
    -- and would wipe the message off it
    cash.centerWindow()

    -- announced once, after the last hop, the way vim reports a counted jump
    if wrapped then
        announceWrap(goForward)
    end
end

return jump
