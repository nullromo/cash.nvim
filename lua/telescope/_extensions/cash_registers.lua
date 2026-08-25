-- The telescope extension: :Telescope cash_registers.
--
-- A list of the nine cash registers that can be filtered by typing part of a
-- pattern, where choosing one makes it the working cash register. It answers
-- the question the ? chooser cannot: which cash register holds the thing I am
-- looking for, when there are more patterns than I can hold in my head.
--
-- Telescope is an optional dependency, and nothing in this file is loaded
-- unless the extension is asked for. The file is found because it sits at
-- lua/telescope/_extensions/, which is where telescope looks for an extension
-- by name -- so cash.nvim has to be on the runtimepath before :Telescope
-- cash_registers can work, which is worth knowing if the plugin is lazy-loaded.
--
-- Everything that does not need telescope lives in lua/cash/picker.lua, which
-- is the half the test suite can reach.

local actionState = require('telescope.actions.state')
local actions = require('telescope.actions')
local cash = require('cash')
local cashPicker = require('cash.picker')
local config = require('telescope.config')
local entryDisplay = require('telescope.pickers.entry_display')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local telescope = require('telescope')

-- the columns, which are the drawer's row with the count moved in front of the
-- pattern. The drawer can right-align the count against a border of its own; a
-- telescope window is whatever size the user's telescope config makes it, and a
-- count that hangs off the right of that is worse than one in a fixed place
local displayer = entryDisplay.create({
    separator = ' ',
    items = {
        -- the marker, the number, the include dot, the match count, and then
        -- the pattern for as long as it is
        { width = 1 },
        { width = 1 },
        { width = 1 },
        { width = 4, right_justify = true },
        { remaining = true },
    },
})

---@param row cash.PickerRow
---@return string display
---@return table highlights
local makeDisplay = function(row)
    -- the number wears the full swatch and everything else around it wears the
    -- same color as text, exactly as in the drawer
    local swatch = 'CashRegister' .. row.index
    local colored = 'CashRegisterFg' .. row.index

    -- the working cash register is in the search set whatever its own switch
    -- says, so the dot answers "will n and N visit it" rather than reporting
    -- the switch. The drawer's dot answers the same question
    local included = row.selected or row.includeInSearch

    return displayer({
        { row.selected and '▸' or ' ', colored },
        { tostring(row.index), swatch },
        { included and '●' or '○', included and colored or 'Comment' },
        { row.count, colored },
        row.pattern ~= '' and { row.pattern, swatch } or { '·', 'Comment' },
    })
end

---@param row cash.PickerRow
---@return table entry
local entryMaker = function(row)
    return {
        value = row,
        ordinal = row.ordinal,
        display = function(entry)
            return makeDisplay(entry.value)
        end,
    }
end

---@param opts? table telescope's own options, from the command line or a call
local open = function(opts)
    opts = opts or {}

    -- the picker reads the state and selecting one searches, so there has to be
    -- a plugin to ask. Nothing else in cash.nvim exists before setup either,
    -- but this is the one entry point that can be reached without it: the
    -- extension is found on the runtimepath rather than created by setup
    if cash.state == nil then
        vim.notify(
            'Cash.nvim: require("cash").setup() has to run before the picker',
            vim.log.levels.WARN
        )
        return
    end

    -- opened from the drawer, everything the picker does would be about the
    -- list of patterns rather than about a buffer: the counts would count
    -- patterns, and selecting would jump about inside the drawer. The drawer
    -- selects a cash register with a <CR> of its own anyway.
    --
    -- The mark is read the way updateHighlights reads it. A buffer variable
    -- that was never set is a failure rather than a nil
    if pcall(vim.api.nvim_buf_get_var, 0, 'cashDrawer') then
        vim.notify(
            'Cash.nvim: the picker cannot be opened from inside the cash '
                .. 'drawer',
            vim.log.levels.WARN
        )
        return
    end

    -- taken before telescope has a window of its own, because both the match
    -- counts and the search that selecting does belong to the window the user
    -- came from
    local originWindow = vim.api.nvim_get_current_win()
    local rows = cashPicker.rows(cash, originWindow)

    local telescopePicker = pickers.new(opts, {
        prompt_title = 'Cash registers',
        finder = finders.new_table({
            results = rows,
            entry_maker = opts.entry_maker or entryMaker,
        }),
        sorter = config.values.generic_sorter(opts),
        -- the picker opens on the cash register being worked in, the way the
        -- drawer's cursor starts on its row
        default_selection_index = cash.state.currentIndex,
        attach_mappings = function(promptBuffer)
            actions.select_default:replace(function()
                local entry = actionState.get_selected_entry()

                -- closed first, because that is what puts the user's own
                -- window back in front of the search that follows
                actions.close(promptBuffer)

                -- nothing is selected when the prompt matches no cash register
                if entry == nil then
                    return
                end

                cashPicker.select(cash, entry.value.index, originWindow)
            end)

            -- keep everything else telescope maps
            return true
        end,
    })

    telescopePicker:find()

    -- after find, because the windows being kept out of the highlighting are
    -- the ones find has just opened
    local windows = {
        telescopePicker.results_win,
        telescopePicker.prompt_win,
    }

    -- a telescope border is a window of its own, holding its box-drawing
    -- characters as ordinary text, so a cash register holding \s or . would
    -- paint those too. Walked with pairs rather than ipairs because either
    -- border is missing when the user's telescope config asks for none
    for _, border in pairs({
        telescopePicker.results_border,
        telescopePicker.prompt_border,
    }) do
        table.insert(windows, border.win_id)
    end

    cashPicker.excludeFromHighlighting(cash, windows)
end

-- the export is named after the extension, which is what makes :Telescope
-- cash_registers reach it with no function name after it
return telescope.register_extension({
    exports = { cash_registers = open },
})
