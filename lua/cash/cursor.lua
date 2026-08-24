-- Which cash register is highlighting the text under the cursor.
--
-- The question ?? asks. The user is looking at some text whose color they can
-- see, and wants to work in whichever cash register painted it, without having
-- to remember which number that color is.
--
-- Nothing in vim can be asked what color a piece of text came out, so the
-- answer is worked out the other way round: every cash register's pattern is
-- asked whether one of its matches covers the cursor. They are asked one at a
-- time rather than as one joined pattern, for the same reason n and N ask one
-- at a time -- \c and \C apply to a whole pattern wherever they are written.
-- See util.resolveCase.

local util = require('cash.util')

local cursor = {}

-- true if position a is at or before position b in the buffer. Rows and
-- columns are both counted from 1, which is how searchpos hands them back
---@param a cash.BufferPosition
---@param b cash.BufferPosition
---@return boolean
local isAtOrBefore = function(a, b)
    if a[1] ~= b[1] then
        return a[1] < b[1]
    end
    return a[2] <= b[2]
end

-- true when one of the given pattern's matches covers the cursor in the
-- current window.
--
-- Three searches rather than one, and each of the three is there for a reason:
--
--   - backward, for a match start at or before the cursor. A backward search
--     can only answer with a position at or before the cursor, so half of the
--     containment question is settled just by asking it this way round.
--   - forward from that start, for the end of a match. The cursor is moved to
--     the start first because vim's end-of-match search scans from the line
--     the cursor is on: asked from where the user actually is, it never sees a
--     multi-line match that began further up.
--   - backward from that end, for the start again. This is what makes the
--     first two answers describe one match rather than two. A pattern that
--     matches without covering anything -- ^, \<, or ^\s* on a line with no
--     indent -- has no end of its own, so the second search runs on and
--     answers with some later match's end, and the round trip comes back
--     somewhere other than where it set off. Vim paints nothing for those, and
--     neither does this.
--
-- The cursor is put back before anything else can see it, so no CursorMoved
-- comes of this and autoNoHighlight has nothing to react to
---@param matchPattern string what vim is actually asked to match
---@param position cash.BufferPosition where the cursor is
---@return boolean
local coversCursor = function(matchPattern, position)
    local start = vim.fn.searchpos(matchPattern, 'bcnW')
    if start[1] == 0 then
        return false
    end

    local view = vim.fn.winsaveview()

    vim.fn.cursor(start[1], start[2])
    local finish = vim.fn.searchpos(matchPattern, 'cenW')

    local roundTrip = { 0, 0 }
    if finish[1] ~= 0 then
        vim.fn.cursor(finish[1], finish[2])
        roundTrip = vim.fn.searchpos(matchPattern, 'bcnW')
    end

    vim.fn.winrestview(view)

    if finish[1] == 0 or not vim.deep_equal(roundTrip, start) then
        return false
    end

    -- the backward search has already settled that the match starts at or
    -- before the cursor, so where it ends is all that is left to ask
    return isAtOrBefore(position, finish)
end

-- The cash register to switch to when the user asks for the one under the
-- cursor: the first one after the working cash register with a match covering
-- it, wrapping round, and the working cash register itself considered last.
--
-- Starting after the working one is what makes asking again walk through the
-- cash registers that overlap here, rather than landing on the same one every
-- time. Leaving the working one until last is what lets the caller tell
-- "nothing matches here" from "you are already in the only one that does"
---@param cashRegisters cash.Register[]
---@param currentIndex cash.RegisterIndex
---@return cash.RegisterIndex|nil index nil when nothing matches under the cursor
cursor.cashRegister = function(cashRegisters, currentIndex)
    -- line() and col() rather than nvim_win_get_cursor, because they count
    -- columns from 1, which is how searchpos answers below
    local position = { vim.fn.line('.'), vim.fn.col('.') }

    for offset = 1, 9 do
        local index = (currentIndex + offset - 1) % 9 + 1
        local pattern = cashRegisters[index].pattern

        -- an empty cash register highlights nothing, and neither does one
        -- holding a pattern vim cannot compile
        if pattern ~= '' then
            local matchPattern = util.resolveCase(pattern)
            if
                util.isUsablePattern(matchPattern)
                and coversCursor(matchPattern, position)
            then
                return index
            end
        end
    end

    return nil
end

return cursor
