-- The telescope picker: what :Telescope cash_registers shows.
--
-- Everything here is the half of the picker that does not need telescope: what
-- each row says, what selecting one does, and keeping the picker's own windows
-- out of the highlighting. The extension in
-- lua/telescope/_extensions/cash_registers.lua is the other half, and is
-- nothing but telescope plumbing.
--
-- The split is not tidiness. Telescope is an optional dependency, so the test
-- suite runs without it, and this is the side of the line the tests can reach.

local util = require('cash.util')

local picker = {}

-- one row of the picker: everything it says about one cash register
---@class cash.PickerRow
---@field index cash.RegisterIndex
---@field pattern string as the user typed it, before any case flag is applied
---@field includeInSearch boolean whether n and N visit its matches
---@field selected boolean true for the working cash register
---@field count string as it is drawn, so 999+ rather than a number, and empty
--- for a cash register that has no answer or nothing to count
---@field ordinal string what the prompt is matched against

-- the nine rows, in order.
--
-- All nine, however few of them hold anything. An empty cash register is still
-- a row for the same reason the chooser still shows its number: which colors
-- are free is part of the answer, and a row is how you get to one.
--
-- The counts are asked about the window the picker was opened from. That window
-- is named rather than assumed, because by the time an answer is wanted
-- telescope's own windows exist and one of them is current -- and asked there,
-- searchcount would count matches in the list of patterns rather than in the
-- buffer the patterns are about
---@param cash cash.Module
---@param window? integer the window the counts are about. The current one when
--- left out
---@return cash.PickerRow[]
picker.rows = function(cash, window)
    local rows = {}

    for index = 1, 9 do
        local register = cash.state.cashRegisters[index]

        -- an empty cash register is not counted at all. Its match pattern is
        -- the bare case flag, which matches at every position in the buffer,
        -- so asking would put a number in the column for a cash register that
        -- highlights nothing
        local count = ''
        if register.pattern ~= '' then
            count = util.matchCount(util.resolveCase(register.pattern), window)
        end

        table.insert(rows, {
            index = index,
            pattern = register.pattern,
            includeInSearch = register.includeInSearch,
            selected = index == cash.state.currentIndex,
            count = count,
            -- the number as well as the pattern, so that the prompt can be
            -- answered with either. Searching by pattern is the reason the
            -- picker exists; typing 4 for cash register 4 is what anyone who
            -- knows the ? chooser will try first
            ordinal = index .. ' ' .. register.pattern,
        })
    end

    return rows
end

-- makes cash register index the working one, in the window the picker was
-- opened from.
--
-- Selecting searches for the pattern, and that search belongs in the window
-- the user came from. Run with telescope's prompt still focused it would land
-- in the list of patterns, which is the same trap the drawer's <CR> avoids the
-- same way
---@param cash cash.Module
---@param index cash.RegisterIndex
---@param window? integer the window the picker was opened from. A window that
--- has since closed is treated as one that was never given
picker.select = function(cash, index, window)
    if window ~= nil and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_call(window, function()
            cash.setCashRegister(index)
        end)
        return
    end

    cash.setCashRegister(index)
end

-- keeps telescope's own windows out of the search highlighting.
--
-- The picker lists the search patterns as literal text, so both halves of the
-- highlighting would land inside it: the eight matches this plugin adds, and
-- vim's own hlsearch on the working pattern. The drawer and the chooser are
-- kept out for the same reason, since a list of patterns painted in the colors
-- it is explaining explains nothing.
--
-- What is different here is that the buffers are not this plugin's to make.
-- The drawer marks its buffer before its window exists; telescope opens its
-- windows without noautocmd, so the WinNew that fires reaches updateHighlights
-- while there is still nothing to mark, and the matches are already in place by
-- the time the picker can hand its windows over. So the mark goes on, whatever
-- arrived with the window is cleared, and the update at the end drops the
-- window from the ledger -- which is a record of matches that have already
-- gone, so it is dropped rather than deleted
---@param cash cash.Module
---@param windows integer[] telescope's own windows
picker.excludeFromHighlighting = function(cash, windows)
    -- the group the search highlights are redirected to, which is empty. Set
    -- here rather than once at setup for the same reason the drawer and the
    -- chooser set it as they open: a colorscheme could have cleared it since
    vim.api.nvim_set_hl(0, 'CashDrawerNoSearch', {})

    for _, window in ipairs(windows) do
        if vim.api.nvim_win_is_valid(window) then
            -- the mark is on the buffer, which is what updateHighlights asks
            -- about
            vim.b[vim.api.nvim_win_get_buf(window)].cashDrawer = true

            -- the matches that came with the window. Telescope adds none of
            -- its own, so there is nothing else in here to take away
            pcall(vim.fn.clearmatches, window)

            -- appended rather than assigned. Telescope sets Normal and
            -- EndOfBuffer in here itself, and its windows would lose their own
            -- background if that went
            local redirects = table.concat({
                'Search:CashDrawerNoSearch',
                'CurSearch:CashDrawerNoSearch',
                'IncSearch:CashDrawerNoSearch',
            }, ',')
            local existing = vim.wo[window].winhighlight
            vim.wo[window].winhighlight = existing == '' and redirects
                or existing .. ',' .. redirects
        end
    end

    cash.updateHighlights()
end

return picker
