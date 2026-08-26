-- The cash drawer: the popup that :Cash opens.
--
-- The buffer holds nothing but the nine search patterns, one per line.
-- Everything else on screen -- the marker, the register number, the include
-- dot, the match count, the header, the legend, the key hints -- is an
-- extmark. So there is no chrome for an edit to damage, the cursor can never
-- get into it, and G lands on cash register 9 rather than on a key hint.
--
-- That is what lets the patterns be edited with ordinary vim commands. cw, D,
-- A, x and macros all work on the line under the cursor, and none of them need
-- a mapping, because the line is nothing but the pattern. Only the commands
-- that change the *number* of lines are a problem, and those are guarded.

local cursor = require('cash.cursor')
local jump = require('cash.jump')
local util = require('cash.util')

local ui = {}

-- the content width, which every rendered row is padded to
local WIDTH = 58

-- how wide the gutter in front of each pattern is:
--
--     '  ' marker ' ' digit '  ' dot '  '
--
-- The legend under the rows points at columns 2, 4 and 7 of it, so the two
-- have to be read together
local GUTTER = 10

local namespace = vim.api.nvim_create_namespace('CashNvimDrawer')

-- Everything about the drawer while it is open.
--
-- The snapshot is what <C-c> puts back. The counts are the match counts already
-- worked out, keyed by match pattern: the buffers behind cannot change while
-- the drawer is open, so an answer stays good for as long as the drawer does.
-- writing is true while the plugin is writing to the buffer, so that its own
-- writes do not come back round as user edits.
--
-- Most of what follows runs only while the drawer is open, and reads drawer
-- without checking it. Each of those functions says so with a ---@cast, which
-- is that precondition written down instead of assumed
---@class cash.Drawer
---@field buffer integer holds the nine patterns, one per line, and nothing else
---@field window integer
---@field height integer
---@field cash cash.Module
---@field originWindow integer the window the user came from
---@field snapshot cash.State
---@field counts table<string, string>
---@field writing boolean
---@field pane? integer the detail pane, while it is open
---@field paneBuffer? integer

-- the drawer while it is open, nil the rest of the time
---@type cash.Drawer|nil
local drawer = nil

-- declared up here because render calls it and it is defined further down,
-- where the rest of the detail pane lives
---@type fun()
local paneRender

---@type string[][]
local FOOTER = {
    { '<CR>', 'select reg, close', '<Tab>', 'select reg, stay open' },
    { '<Space>', 'toggle include', ']/[', 'swap register down/up' },
    { '?', 'show details', '<C-c>', 'close, undo changes' },
    { 'q/<Esc>', 'apply and close' },
}

-- written out rather than padded into place, because box drawing characters
-- are several bytes each and the alignment here has to be exact
---@type string[][]
local LEGEND = {
    { '  │ │  │' },
    { '  │ │  ╰─', 'Include in search' },
    { '  │ ╰─', 'Cash register number' },
    { '  ╰─', 'Selected cash register' },
}

---@param text string
---@param width integer
---@return string
local pad = function(text, width)
    return text .. string.rep(' ', math.max(0, width - #text))
end

-- where a popup sits, as a fraction of the space left over once it has been
-- placed. 0 is flush against the top or left, 1 against the bottom or right
---@type table<cash.Position, number[]>
local PLACEMENT = {
    ['top-left'] = { 0, 0 },
    ['top'] = { 0, 0.5 },
    ['top-right'] = { 0, 1 },
    ['left'] = { 0.5, 0 },
    ['center'] = { 0.5, 0.5 },
    ['right'] = { 0.5, 1 },
    ['bottom-left'] = { 1, 0 },
    ['bottom'] = { 1, 0.5 },
    ['bottom-right'] = { 1, 1 },
}

-- how many rows at the top of the screen the tabline is using: one when there
-- is a tabline, none when there is not.
--
-- A float placed against the editor counts row 0 from the very top of the
-- screen, and that row belongs to the tabline whenever there is one, so a
-- popup put along the top would sit over it
---@return integer
local tablineRows = function()
    local showing = vim.o.showtabline == 2
        or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
    return showing and 1 or 0
end

-- the row and column for a popup of this size in this position. A border adds
-- a row and a column on each side, and the tabline, the status line and the
-- command line are not free to be covered, so none of them counts as space to
-- place into
---@param position cash.Position
---@param width integer without its border
---@param height integer without its border
---@param frame? integer how many rows and columns the border adds on each
--- side, which is 1 when left out. The indicator is drawn without one and
--- passes 0, since its brackets are its border
---@return { row: integer, col: integer }
ui.placement = function(position, width, height, frame)
    frame = frame or 1
    local fraction = PLACEMENT[position] or PLACEMENT['center']

    -- the tabline is taken off the space to place into and added back to the
    -- row, so that the top positions start below it and the bottom ones stay
    -- where they were
    local tabline = tablineRows()

    local rowsFree = vim.o.lines
        - vim.o.cmdheight
        - 1
        - tabline
        - (height + frame * 2)
    local columnsFree = vim.o.columns - (width + frame * 2)

    return {
        row = tabline + math.max(0, math.floor(rowsFree * fraction[1])),
        col = math.max(0, math.floor(columnsFree * fraction[2])),
    }
end

-- a piece of text and the highlight group to draw it in, which is the shape
-- nvim_buf_set_extmark takes for virt_text. The group may be left out, and text
-- without one is deliberately unpainted: naming a group for the plain spaces in
-- the gutter would punch holes through cursorline on the row the cursor is on
---@alias cash.Chunk string[]

-- where one highlight group goes on a row, as byte offsets into its text
---@class cash.RowMark
---@field from integer
---@field to integer
---@field group string

-- a line the drawer or the pane is building: the text, and the highlights that
-- go over it
---@class cash.Row
---@field text string
---@field marks cash.RowMark[]

-- a line under construction, kept as text plus the highlights that go over it.
-- Built together because the highlights are byte ranges into the text, and a
-- pattern can hold anything the user typed, multibyte included
---@return cash.Row
local newRow = function()
    return { text = '', marks = {} }
end

---@param row cash.Row
---@param text string
---@param group? string left out for text that should not be painted
local addChunk = function(row, text, group)
    if group ~= nil then
        table.insert(row.marks, {
            from = #row.text,
            to = #row.text + #text,
            group = group,
        })
    end
    row.text = row.text .. text
end

---@param row cash.Row
---@param width integer in display cells
local padRowTo = function(row, width)
    local shortfall = width - vim.fn.strdisplaywidth(row.text)
    if shortfall > 0 then
        addChunk(row, string.rep(' ', shortfall))
    end
end

-- how many matches a cash register has in the buffer the user came from.
--
-- util.matchCount is bounded on both sides already, but bounded is not cheap
-- enough on its own here, because the counts are redrawn on every keystroke
-- while a pattern is being typed. So an answer is only asked for once, and the
-- window it is asked about is the one the user came from rather than the drawer
---@param matchPattern string
---@return string count as it is drawn, so 999+ rather than a number, and empty
--- when there is no answer
local matchCount = function(matchPattern)
    ---@cast drawer cash.Drawer
    local cached = drawer.counts[matchPattern]
    if cached ~= nil then
        return cached
    end

    local answer = util.matchCount(matchPattern, drawer.originWindow)
    drawer.counts[matchPattern] = answer
    return answer
end

-- one row of the gutter, as extmark chunks.
--
-- The plain spaces are left without a highlight group on purpose. Naming one
-- would paint them, and they would then punch holes through cursorline on the
-- row the cursor is on
---@param cash cash.Module
---@param index cash.RegisterIndex
---@return cash.Chunk[]
local gutterFor = function(cash, index)
    local register = cash.state.cashRegisters[index]
    local isSelected = index == cash.state.currentIndex
    local colored = 'CashRegisterFg' .. index

    return {
        { '  ' },
        { isSelected and '▸' or ' ', colored },
        { ' ' },
        { tostring(index), 'CashRegister' .. index },
        { '  ' },
        {
            (isSelected or register.includeInSearch) and '●' or '○',
            (isSelected or register.includeInSearch) and colored or 'Comment',
        },
        { '  ' },
    }
end

-- the column headings, as a winbar rather than a virtual line above cash
-- register 1. Virtual lines above the first line of a buffer are never drawn,
-- and a winbar is a row of the window rather than of the buffer, so the cursor
-- cannot reach it either. %= right-aligns what follows, which puts "Match
-- count" over the counts however wide the drawer is
---@return string
local winbar = function()
    return '%#Comment#'
        .. string.rep(' ', GUTTER)
        .. 'Register contents%=Match count   '
end

-- the line naming the search set. It is the only place the drawer says which
-- cash registers n and N will visit, since an included register looks exactly
-- like an excluded one out in the buffer
---@param cash cash.Module
---@return cash.Chunk[]
local searchSetLine = function(cash)
    local chunks = { { '  n/N will jump between  ', 'Comment' } }

    for position, index in
        ipairs(
            jump.searchSet(cash.state.cashRegisters, cash.state.currentIndex)
        )
    do
        if position > 1 then
            table.insert(chunks, { ' ' })
        end
        table.insert(chunks, { tostring(index), 'CashRegister' .. index })
    end

    return chunks
end

---@return cash.Chunk[]
local separatorLine = function()
    return { { string.rep('─', WIDTH), 'NonText' } }
end

---@return cash.Chunk[][]
local footerLines = function()
    local lines = {}

    for _, row in ipairs(FOOTER) do
        local chunks = {
            { ' ' },
            { pad(row[1], 9), 'Special' },
            { pad(row[2], 19), 'Comment' },
        }
        if row[3] ~= nil then
            table.insert(chunks, { pad(row[3], 7), 'Special' })
            table.insert(chunks, { row[4], 'Comment' })
        end
        table.insert(lines, chunks)
    end

    return lines
end

---@return cash.Chunk[][]
local legendLines = function()
    local lines = {}

    for _, row in ipairs(LEGEND) do
        local chunks = { { row[1], 'NonText' } }
        if row[2] ~= nil then
            table.insert(chunks, { row[2], 'Comment' })
        end
        table.insert(lines, chunks)
    end

    return lines
end

-- draws everything that is not the patterns themselves. Called again after
-- every change, including every keystroke while a pattern is being typed, so
-- it never touches the buffer's text or the cursor
local decorate = function()
    ---@cast drawer cash.Drawer
    local cash = drawer.cash
    local buffer = drawer.buffer

    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)

    for index = 1, 9 do
        local line = index - 1
        local register = cash.state.cashRegisters[index]

        -- the gutter, rendered in front of the pattern rather than inserted
        -- into it
        vim.api.nvim_buf_set_extmark(buffer, namespace, line, 0, {
            virt_text = gutterFor(cash, index),
            virt_text_pos = 'inline',
            right_gravity = false,
        })

        -- the pattern wears its own cash register's color, so that the drawer
        -- shows what each one looks like out in the buffer
        if register.pattern ~= '' then
            vim.api.nvim_buf_set_extmark(buffer, namespace, line, 0, {
                end_col = #register.pattern,
                hl_group = 'CashRegister' .. index,
            })

            local count = matchCount(util.resolveCase(register.pattern))
            vim.api.nvim_buf_set_extmark(buffer, namespace, line, 0, {
                virt_text = {
                    {
                        string.format('%4s   ', count),
                        'CashRegisterFg' .. index,
                    },
                },
                virt_text_pos = 'right_align',
            })
        end
    end

    local below = legendLines()
    table.insert(below, separatorLine())
    table.insert(below, searchSetLine(cash))
    table.insert(below, separatorLine())
    for _, line in ipairs(footerLines()) do
        table.insert(below, line)
    end

    vim.api.nvim_buf_set_extmark(buffer, namespace, 8, 0, {
        virt_lines = below,
    })
end

-- writes the nine patterns into the buffer.
--
-- forgetUndo is for the very first write only. Dropping undolevels and putting
-- it back is vim's documented way to throw away the undo history (:h
-- clear-undo) -- not to skip recording one change, which is what it looks like
-- it does. Used on every write it wipes the history each time, and u stops
-- working altogether. Used once, at the start, it is exactly right: u must not
-- be able to rewind to the empty buffer the drawer began as, because the
-- row-count guard would read that back as nine empty cash registers
---@param forgetUndo? boolean true on the first write only
local writeLines = function(forgetUndo)
    ---@cast drawer cash.Drawer
    local buffer = drawer.buffer
    local patterns = {}
    for index = 1, 9 do
        table.insert(patterns, drawer.cash.state.cashRegisters[index].pattern)
    end

    drawer.writing = true

    local undolevels = vim.bo[buffer].undolevels
    if forgetUndo then
        vim.bo[buffer].undolevels = -1
    end
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, patterns)
    if forgetUndo then
        vim.bo[buffer].undolevels = undolevels
    end

    drawer.writing = false
end

---@param forgetUndo? boolean true on the first write only
local render = function(forgetUndo)
    writeLines(forgetUndo)
    decorate()
    paneRender()
end

-- there are always nine cash registers, so there are always nine lines.
--
-- dd, o and insert-mode <CR> are mapped away, but this is the backstop for
-- everything that was not thought of: a linewise paste, a visual line delete,
-- :move, a macro. Repairing is better than refusing, since refusing would mean
-- watching every route into the buffer rather than the one invariant
local enforceNineLines = function()
    ---@cast drawer cash.Drawer
    local buffer = drawer.buffer
    local count = vim.api.nvim_buf_line_count(buffer)
    if count == 9 then
        return
    end

    drawer.writing = true

    -- the repair belongs to the change that caused it, so that one u takes
    -- both back together. Without this the user's dd and the row it puts back
    -- are two separate undo steps, and u appears to do nothing at all.
    -- undojoin refuses right after an undo, which is not worth reporting
    pcall(function()
        vim.cmd('silent! undojoin')
    end)

    if count > 9 then
        vim.api.nvim_buf_set_lines(buffer, 9, -1, false, {})
    else
        local padding = {}
        for _ = count + 1, 9 do
            table.insert(padding, '')
        end
        vim.api.nvim_buf_set_lines(buffer, count, count, false, padding)
    end

    drawer.writing = false
end

-- reads the buffer back into the cash registers. The buffer is the truth while
-- the drawer is open, because it is what the user has been typing into
local syncFromBuffer = function()
    ---@cast drawer cash.Drawer
    local lines = vim.api.nvim_buf_get_lines(drawer.buffer, 0, 9, false)
    for index = 1, 9 do
        drawer.cash.state.cashRegisters[index].pattern = lines[index] or ''
    end
end

-- ---------------------------------------------------------------- the pane
--
-- What ? opens beside the drawer. Everything here is about one cash register
-- and does not fit on its row: the pattern vim is really matching, the color
-- it came out as, and which windows are carrying a match for it.
--
-- It sits to the side rather than underneath because the drawer is already 23
-- rows tall, which is most of a small terminal. Height is the scarce
-- direction here; width is not.

local PANE_WIDTH = 40

-- wide enough for "matching window IDs", the longest label there is
local PANE_LABEL = 20
local PANE_VALUE = PANE_WIDTH - 2 - PANE_LABEL

-- the windows where this cash register's pattern actually occurs.
--
-- Deliberately not the ledger. The ledger records where the plugin *added* a
-- match, which is a different question, and answers this one wrongly in both
-- directions: a pattern with a match added but nothing to match reads as
-- present, and the selected cash register reads as absent even while it is lit
-- up on screen, because it is drawn by hlsearch rather than by a match. The
-- line says "matching window IDs", so it counts matches.
--
-- maxcount stops at the first hit, since the question is only whether there is
-- one, and timeout keeps a pathological pattern from stalling the pane while
-- someone is still typing it
---@param matchPattern string
---@return integer[] windowIDs sorted, and never the drawer or the pane
local matchingWindows = function(matchPattern)
    local found = {}

    for _, windowID in ipairs(vim.api.nvim_list_wins()) do
        local buffer = vim.api.nvim_win_get_buf(windowID)
        local isOurs = pcall(vim.api.nvim_buf_get_var, buffer, 'cashDrawer')

        if not isOurs then
            local counted = nil
            pcall(vim.api.nvim_win_call, windowID, function()
                counted = vim.fn.searchcount({
                    pattern = matchPattern,
                    maxcount = 1,
                    timeout = 20,
                })
            end)

            if counted ~= nil and (counted.total or 0) > 0 then
                table.insert(found, windowID)
            end
        end
    end

    table.sort(found)
    return found
end

---@param cash cash.Module
---@param index cash.RegisterIndex the cash register the pane is about
---@return cash.Row[]
local paneRows = function(cash, index)
    local register = cash.state.cashRegisters[index]
    local rows = {}

    ---@param label string
    ---@param chunks? cash.Chunk[]
    local line = function(label, chunks)
        local row = newRow()
        addChunk(row, '  ')
        addChunk(row, pad(label, PANE_LABEL), label ~= '' and 'Comment' or nil)
        for _, chunk in ipairs(chunks or {}) do
            addChunk(row, chunk[1], chunk[2])
        end
        padRowTo(row, PANE_WIDTH)
        table.insert(rows, row)
    end

    ---@param answer boolean
    ---@return cash.Chunk[]
    local yesNo = function(answer)
        return { answer and { 'yes' } or { 'no', 'Comment' } }
    end

    local header = newRow()
    addChunk(header, '  cash register ', 'Comment')
    addChunk(header, tostring(index), 'CashRegister' .. index)
    padRowTo(header, PANE_WIDTH)
    table.insert(rows, header)
    line('')

    if register.pattern == '' then
        line('contents', { { 'empty', 'Comment' } })
    else
        line('contents', {
            {
                util.truncate(register.pattern, PANE_VALUE),
                'CashRegister' .. index,
            },
        })

        -- the match pattern: what vim is actually given, with the case flag
        -- resolved onto the front of it. Usually the first thing to look at
        -- when a search is behaving oddly. Named here exactly as CONTEXT.md
        -- names it, since there is no friendlier word that is also accurate
        local matchPattern = util.resolveCase(register.pattern)
        if util.isUsablePattern(matchPattern) then
            line(
                'match pattern',
                { { util.truncate(matchPattern, PANE_VALUE) } }
            )
        else
            line('match pattern', { { 'vim cannot compile', 'WarningMsg' } })
        end
    end

    -- the selected cash register is in the search set whatever its own switch
    -- says, so this answers "will n and N visit it" rather than reporting the
    -- flag. That is also what the dot in the drawer shows, and the two would
    -- contradict each other otherwise
    local isSelected = index == cash.state.currentIndex
    line('include in search', yesNo(register.includeInSearch or isSelected))
    line('selected', yesNo(isSelected))
    line('')

    local found = {}
    if register.pattern ~= '' then
        local matchPattern = util.resolveCase(register.pattern)
        if util.isUsablePattern(matchPattern) then
            found = matchingWindows(matchPattern)
        end
    end

    if #found == 0 then
        line('matching window IDs', { { 'none', 'Comment' } })
    else
        local windows = {}
        for _, windowID in ipairs(found) do
            table.insert(windows, tostring(windowID))
        end
        line('matching window IDs', {
            {
                util.truncate(table.concat(windows, '  '), PANE_VALUE),
                'Comment',
            },
        })
    end

    return rows
end

-- draws the pane's contents into its buffer. The window is left alone, so this
-- is safe to call on every cursor movement inside the drawer
paneRender = function()
    if drawer == nil or drawer.pane == nil then
        return
    end

    local rows =
        paneRows(drawer.cash, vim.api.nvim_win_get_cursor(drawer.window)[1])

    local text = {}
    for _, row in ipairs(rows) do
        table.insert(text, row.text)
    end

    -- the pane and its buffer are made and cleared together, so the guard
    -- above has settled this one too
    local buffer = drawer.paneBuffer --[[@as integer]]
    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, text)
    vim.bo[buffer].modifiable = false

    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    for line, row in ipairs(rows) do
        for _, mark in ipairs(row.marks) do
            vim.api.nvim_buf_set_extmark(
                buffer,
                namespace,
                line - 1,
                mark.from,
                { end_col = mark.to, hl_group = mark.group }
            )
        end
    end

    vim.api.nvim_win_set_height(drawer.pane, #rows)
end

-- puts the drawer where drawer.position asks for, and the pane beside it.
--
-- With the pane open the two are placed as one block, so that 'center' still
-- centers what the user is actually looking at rather than centering the
-- drawer and letting the pane hang off the side
local placeWindows = function()
    ---@cast drawer cash.Drawer
    local cash = drawer.cash
    local paneRoom = drawer.pane ~= nil and (PANE_WIDTH + 2) or 0
    local where =
        ui.placement(cash.opts.drawer.position, WIDTH + paneRoom, drawer.height)

    vim.api.nvim_win_set_config(drawer.window, {
        relative = 'editor',
        row = where.row,
        col = where.col,
    })

    if drawer.pane ~= nil then
        vim.api.nvim_win_set_config(drawer.pane, {
            relative = 'editor',
            row = where.row,
            col = where.col + WIDTH + 2,
        })
    end
end

ui.closePane = function()
    if drawer == nil or drawer.pane == nil then
        return
    end

    local pane = drawer.pane --[[@as integer]]
    drawer.pane = nil
    drawer.paneBuffer = nil

    if vim.api.nvim_win_is_valid(pane) then
        vim.api.nvim_win_close(pane, true)
    end
    placeWindows()
end

ui.openPane = function()
    if drawer == nil or drawer.pane ~= nil then
        return
    end

    local cash = drawer.cash

    -- the drawer and the pane side by side need this much room. Refusing is
    -- better than opening something clipped in half
    local needed = WIDTH + 2 + PANE_WIDTH + 2
    if vim.o.columns < needed then
        vim.notify(
            'Cash.nvim: the detail pane needs a window at least '
                .. needed
                .. ' columns wide',
            vim.log.levels.WARN
        )
        return
    end

    local buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].buftype = 'nofile'
    vim.bo[buffer].bufhidden = 'wipe'
    vim.bo[buffer].swapfile = false
    -- the pane names patterns too, so it is kept out of the ledger for the
    -- same reason the drawer is
    vim.b[buffer].cashDrawer = true

    drawer.paneBuffer = buffer
    drawer.pane = vim.api.nvim_open_win(buffer, false, {
        relative = 'editor',
        width = PANE_WIDTH,
        height = 1,
        row = 0,
        col = 0,
        style = 'minimal',
        border = cash.opts.drawer.border,
        title = '─ Details ',
        title_pos = 'left',
        focusable = false,
        noautocmd = true,
    })

    vim.wo[drawer.pane].wrap = false
    vim.wo[drawer.pane].winhighlight = table.concat({
        'FloatTitle:FloatBorder',
        'Search:CashDrawerNoSearch',
        'CurSearch:CashDrawerNoSearch',
        'IncSearch:CashDrawerNoSearch',
    }, ',')

    paneRender()
    placeWindows()
end

---@return boolean
ui.isOpen = function()
    return drawer ~= nil and vim.api.nvim_win_is_valid(drawer.window)
end

---@return boolean
ui.isOpenPane = function()
    return drawer ~= nil
        and drawer.pane ~= nil
        and vim.api.nvim_win_is_valid(drawer.pane)
end

-- what the pane is currently saying, as lines. For tests, and for anyone who
-- wants the same facts without a window
---@return string[] lines # empty while the pane is closed
ui.paneContents = function()
    if not ui.isOpenPane() then
        return {}
    end
    ---@cast drawer cash.Drawer
    return vim.api.nvim_buf_get_lines(
        drawer.paneBuffer --[[@as integer]],
        0,
        -1,
        false
    )
end

ui.close = function()
    if drawer == nil then
        return
    end

    local window = drawer.window
    local pane = drawer.pane
    drawer = nil

    if pane ~= nil and vim.api.nvim_win_is_valid(pane) then
        vim.api.nvim_win_close(pane, true)
    end
    if vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_close(window, true)
    end
end

-- everything the user typed is already in the cash registers, because the
-- preview put it there as they typed. What is left is the search register,
-- which mirrors the selected cash register and would otherwise still hold what
-- that register said when the drawer opened
local apply = function()
    ---@cast drawer cash.Drawer
    local cash = drawer.cash
    enforceNineLines()
    syncFromBuffer()

    local pattern = cash.state.cashRegisters[cash.state.currentIndex].pattern
    vim.fn.setreg('/', pattern)

    cash.updateHighlights()
    ui.close()
end

-- puts back the cash registers exactly as they were when the drawer opened
local discard = function()
    ---@cast drawer cash.Drawer
    local cash = drawer.cash
    cash.state.cashRegisters = drawer.snapshot.cashRegisters
    cash.state.currentIndex = drawer.snapshot.currentIndex

    local pattern = cash.state.cashRegisters[cash.state.currentIndex].pattern
    vim.fn.setreg('/', pattern)

    cash.updateHighlights()
    ui.close()
end

---@return cash.RegisterIndex index there are nine rows and nine cash
--- registers, so the cursor's row is one of them
local registerUnderCursor = function()
    ---@cast drawer cash.Drawer
    return vim.api.nvim_win_get_cursor(drawer.window)[1]
end

-- selecting a cash register searches for its pattern, and that has to happen
-- in the window the user came from. Run with the drawer focused, the jump
-- would land in the list of patterns instead
---@param index cash.RegisterIndex
local selectRegister = function(index)
    ---@cast drawer cash.Drawer
    local cash = drawer.cash
    local originWindow = drawer.originWindow

    if vim.api.nvim_win_is_valid(originWindow) then
        vim.api.nvim_win_call(originWindow, function()
            cash.setCashRegister(index)
        end)
    else
        cash.setCashRegister(index)
    end
end

---@param cash cash.Module
local setUpKeymaps = function(cash)
    ---@cast drawer cash.Drawer
    local buffer = drawer.buffer
    ---@param mode string
    ---@param key string
    ---@param action string|fun()
    local map = function(mode, key, action)
        vim.keymap.set(mode, key, action, { buffer = buffer, nowait = true })
    end

    map('n', 'q', apply)
    map('n', '<Esc>', apply)
    map('n', '<C-c>', discard)

    map('n', '<CR>', function()
        selectRegister(registerUnderCursor())
        apply()
    end)

    map('n', '<Tab>', function()
        selectRegister(registerUnderCursor())
        render()
    end)

    map('n', '<Space>', function()
        local index = registerUnderCursor()
        if index == cash.state.currentIndex then
            vim.notify(
                'Cash.nvim: the selected cash register is always in the '
                    .. 'search set',
                vim.log.levels.INFO
            )
            return
        end
        cash.toggleIncludeInSearch(index)
        decorate()
        paneRender()
    end)

    -- swapping moves the pattern and the switch, but not the color: that
    -- belongs to the slot, which is what makes this a way to recolor a search
    ---@param step integer -1 for up, 1 for down
    ---@return fun()
    local swap = function(step)
        return function()
            ---@cast drawer cash.Drawer
            local index = registerUnderCursor()
            local other = index + step
            if other < 1 or other > 9 then
                return
            end

            -- whatever is in the buffer is newer than what is in the state,
            -- so it is read back before anything is moved around
            syncFromBuffer()

            local registers = cash.state.cashRegisters
            registers[index], registers[other] =
                registers[other], registers[index]

            -- the selected cash register travels with its contents, so that
            -- swapping does not quietly change which one you are searching in
            if cash.state.currentIndex == index then
                cash.state.currentIndex = other
            elseif cash.state.currentIndex == other then
                cash.state.currentIndex = index
            end

            cash.updateHighlights()
            render()
            vim.api.nvim_win_set_cursor(drawer.window, { other, 0 })
        end
    end

    map('n', ']', swap(1))
    map('n', '[', swap(-1))

    -- there are always nine rows, so dd empties one rather than removing it.
    -- D, C, cc, S and cw need no mapping at all: the line is nothing but the
    -- pattern, so they already do the right thing
    map('n', 'dd', function()
        ---@cast drawer cash.Drawer
        local index = registerUnderCursor()
        vim.api.nvim_buf_set_lines(
            drawer.buffer,
            index - 1,
            index,
            false,
            { '' }
        )
    end)

    -- these would add a row
    map('n', 'o', '<Nop>')
    map('n', 'O', '<Nop>')
    map('i', '<CR>', '<Esc>')

    map('n', '?', function()
        ---@cast drawer cash.Drawer
        if drawer.pane == nil then
            ui.openPane()
        else
            ui.closePane()
        end
    end)
end

-- ------------------------------------------------------------------ chooser
--
-- The popup ? brings up. Its whole job is to answer "which number is the green
-- one" on screen instead of from memory, which is what makes it a different
-- tool from the drawer: it appears, you press a digit, it is gone.
--
-- An empty cash register still shows its number, in its own color as text
-- rather than as a swatch. It is worth knowing which colors are free.
--
-- The cash register a second ? would switch to -- the one highlighting the
-- text under the cursor -- is marked with a ? after its number, so that the
-- answer is on screen before the key is pressed rather than after it.

-- a grid cell is the marker, the number, a space and the pattern
local CHOOSER_COLUMN = 12
local CHOOSER_PATTERN = CHOOSER_COLUMN - 5

---@param row cash.Row
---@param cash cash.Module
---@param index cash.RegisterIndex
---@param underCursor cash.RegisterIndex|nil the one a second ? would switch
--- to, which gets a ? of its own
---@param patternWidth? integer left out for the strip, which has room for the
--- number only
local chooserCell = function(row, cash, index, underCursor, patternWidth)
    local register = cash.state.cashRegisters[index]
    local filled = register.pattern ~= ''

    -- the grid marks the selected cash register the same way the drawer does,
    -- so that the two read alike. The strip has no room for it and is not
    -- trying to answer that question anyway
    if patternWidth ~= nil then
        addChunk(
            row,
            index == cash.state.currentIndex and '▸' or ' ',
            'CashRegisterFg' .. index
        )
    end

    -- the ? marking the cash register under the cursor goes in the space the
    -- number already had after it, so that a marked cell is exactly as wide as
    -- an unmarked one and nothing shifts about as the cursor moves
    addChunk(
        row,
        ' ' .. index .. (index == underCursor and '?' or ' '),
        filled and ('CashRegister' .. index) or ('CashRegisterFg' .. index)
    )

    if patternWidth == nil then
        return
    end

    addChunk(row, ' ')
    if filled then
        addChunk(
            row,
            util.truncate(register.pattern, patternWidth),
            'CashRegister' .. index
        )
    else
        addChunk(row, '·', 'Comment')
    end
end

-- 'grid' lays the nine out the way a numpad does, which is not a coincidence
-- worth wasting, and shows what each one holds. 'strip' is one line of numbers
-- for when that is the only question
---@param cash cash.Module
---@param style cash.ChooserStyle
---@return cash.Row[]
local chooserRows = function(cash, style)
    local rows = {}

    -- asked once rather than once per cell, and asked here rather than in
    -- openChooser because this runs while the user's own window is still the
    -- current one. The chooser's window is opened without being entered, but
    -- the answer is about where the cursor is, so it is worked out before
    -- there is any other window it could be read from
    local underCursor =
        cursor.cashRegister(cash.state.cashRegisters, cash.state.currentIndex)

    if style == 'strip' then
        local row = newRow()
        addChunk(row, '  ')
        for index = 1, 9 do
            chooserCell(row, cash, index, underCursor)
            if index < 9 then
                addChunk(row, ' ')
            end
        end
        addChunk(row, '  ')
        table.insert(rows, row)
        return rows
    end

    for line = 0, 2 do
        local row = newRow()
        addChunk(row, '  ')
        for column = 0, 2 do
            chooserCell(
                row,
                cash,
                line * 3 + column + 1,
                underCursor,
                CHOOSER_PATTERN
            )
            padRowTo(row, 2 + (column + 1) * CHOOSER_COLUMN)
        end
        -- a pattern that fills its column exactly would otherwise sit against
        -- the border with nothing between them
        addChunk(row, '  ')
        table.insert(rows, row)
    end
    return rows
end

-- shows the chooser and waits for one keypress. Returns the cash register the
-- user picked, or nil if they pressed anything else
-- puts the chooser on screen and hands back its window, without waiting for
-- anything. Kept separate from chooseRegister so that what gets drawn can be
-- looked at without a keypress blocking the loop, which is also how it is
-- tested
---@param cash cash.Module
---@param style? cash.ChooserStyle chooser.style when left out
---@return integer window
ui.openChooser = function(cash, style)
    local rows = chooserRows(cash, style or cash.opts.chooser.style)

    local width = 0
    local text = {}
    for _, row in ipairs(rows) do
        width = math.max(width, vim.fn.strdisplaywidth(row.text))
        table.insert(text, row.text)
    end

    local buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].bufhidden = 'wipe'
    -- the chooser holds patterns as literal text too, so it is kept out of the
    -- ledger for the same reason the drawer is
    vim.b[buffer].cashDrawer = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, text)

    for line, row in ipairs(rows) do
        for _, mark in ipairs(row.marks) do
            vim.api.nvim_buf_set_extmark(
                buffer,
                namespace,
                line - 1,
                mark.from,
                { end_col = mark.to, hl_group = mark.group }
            )
        end
    end

    local where = ui.placement(cash.opts.chooser.position, width, #rows)
    local window = vim.api.nvim_open_win(buffer, false, {
        relative = 'editor',
        width = width,
        height = #rows,
        row = where.row,
        col = where.col,
        style = 'minimal',
        border = cash.opts.chooser.border,
        -- the leading dash continues the border rather than sitting apart from
        -- it, which needs the title drawn in the border's own colors
        title = '─ Choose a cash register ',
        title_pos = 'left',
        focusable = false,
        noautocmd = true,
    })

    -- the chooser lists the patterns, so vim's own hlsearch would match them
    -- in here as well. Same reasoning as the drawer
    vim.api.nvim_set_hl(0, 'CashDrawerNoSearch', {})
    vim.wo[window].winhighlight = table.concat({
        'FloatTitle:FloatBorder',
        'Search:CashDrawerNoSearch',
        'CurSearch:CashDrawerNoSearch',
        'IncSearch:CashDrawerNoSearch',
    }, ',')

    return window
end

-- what the chooser can be answered with: one of the nine cash registers, or
-- the one that is highlighting the text under the cursor
---@alias cash.Choice cash.RegisterIndex | 'under-cursor'

-- shows the chooser and waits for one keypress. Returns what the user picked,
-- or nil if they pressed anything else
---@param cash cash.Module
---@return cash.Choice|nil choice nil when the key was neither a digit from 1
--- to 9 nor a second ?
ui.chooseRegister = function(cash)
    local window = nil

    if cash.opts.chooser.style == 'none' then
        vim.notify('Enter a digit to choose a cash register')
    else
        window = ui.openChooser(cash)
        -- drawn before the wait, or it would only appear once the key had
        -- already been pressed
        vim.cmd('redraw')
    end

    local pressed, character = pcall(vim.fn.getchar)

    if window ~= nil and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_close(window, true)
    end
    -- clear the command line, whichever way the answer was asked for
    vim.api.nvim_echo({ { '', '' } }, false, {})

    if not pressed or type(character) ~= 'number' then
        return nil
    end

    local key = vim.fn.nr2char(character)

    -- a second ? asks for the cash register that is highlighting the text
    -- under the cursor, which is the one question the nine digits cannot
    -- answer: the color is on screen, and the number it belongs to is not
    if key == '?' then
        return 'under-cursor'
    end

    local index = tonumber(key)
    if not util.isCashRegisterIndex(index) then
        return nil
    end
    return index
end

---@param cash cash.Module
ui.open = function(cash)
    if ui.isOpen() then
        ---@cast drawer cash.Drawer
        vim.api.nvim_set_current_win(drawer.window)
        return
    end

    -- taken before the float steals focus, because the match counts have to be
    -- worked out against the buffer the user was actually looking at
    local originWindow = vim.api.nvim_get_current_win()

    local buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].buftype = 'nofile'
    vim.bo[buffer].bufhidden = 'wipe'
    vim.bo[buffer].swapfile = false
    vim.bo[buffer].filetype = 'cash'

    -- marked before the window exists, because opening one fires WinNew and
    -- WinEnter, and the update those trigger would otherwise match the
    -- patterns inside the drawer as though it were an ordinary buffer
    vim.b[buffer].cashDrawer = true

    -- the winbar takes a row of the window, then the nine cash registers, then
    -- the legend, the two rules, the search set line and the key hints
    local height = 1 + 9 + #LEGEND + 3 + #FOOTER

    local where = ui.placement(cash.opts.drawer.position, WIDTH, height)

    local window = vim.api.nvim_open_win(buffer, true, {
        relative = 'editor',
        width = WIDTH,
        height = height,
        row = where.row,
        col = where.col,
        style = 'minimal',
        border = cash.opts.drawer.border,
        -- the leading dash continues the border rather than sitting apart
        -- from it, which needs the title drawn in the border's own colors
        title = '─ Cash.nvim Registers ',
        title_pos = 'left',
        -- opening a window fires WinNew while it is still showing the buffer
        -- the user came from, so the update that triggers would add a match to
        -- the drawer's window before the drawer's buffer is even in it. The
        -- match would then stay there, on a buffer full of search patterns.
        -- Nothing needs updating for a window that is excluded anyway
        noautocmd = true,
    })

    vim.wo[window].wrap = false
    vim.wo[window].cursorline = true
    vim.wo[window].winbar = winbar()

    -- Two redirections, both for this window only.
    --
    -- FloatTitle so that the title's leading dash continues the border instead
    -- of sitting apart from it.
    --
    -- Search, CurSearch and IncSearch because the drawer's buffer holds the
    -- search patterns as literal text, so vim's own hlsearch matches them
    -- here. That is not the ledger, and excluding the window from it does not
    -- help: it is vim highlighting @/ wherever it appears. Left alone, the
    -- pattern the user is searching for wears CurSearch in the drawer as soon
    -- as the cursor reaches its row, and a pattern that occurs inside another
    -- one lights up part of it. The drawer has one job -- showing each cash
    -- register in its own exact color -- so search highlighting is turned off
    -- inside it
    vim.api.nvim_set_hl(0, 'CashDrawerNoSearch', {})
    vim.wo[window].winhighlight = table.concat({
        'FloatTitle:FloatBorder',
        'Search:CashDrawerNoSearch',
        'CurSearch:CashDrawerNoSearch',
        'IncSearch:CashDrawerNoSearch',
    }, ',')

    drawer = {
        buffer = buffer,
        window = window,
        height = height,
        cash = cash,
        originWindow = originWindow,
        -- what <C-c> puts back
        snapshot = {
            cashRegisters = vim.deepcopy(cash.state.cashRegisters),
            currentIndex = cash.state.currentIndex,
        },
        -- match counts already worked out, keyed by match pattern. The buffer
        -- behind cannot change while the drawer is open, so an answer stays
        -- good for as long as the drawer does
        counts = {},
        -- true while the plugin is writing to the buffer, so that its own
        -- writes do not come back round as user edits
        writing = false,
    }

    -- the first write, and the only one that throws the undo history away
    render(true)
    setUpKeymaps(cash)

    vim.api.nvim_win_set_cursor(window, { cash.state.currentIndex, 0 })

    -- opening the drawer ends a :nohlsearch. There is no point showing every
    -- cash register's contents and colors in here while the buffer behind
    -- stays dark, and the preview would have nothing to preview
    cash.showHighlighting()

    if cash.opts.drawer.detailPane then
        ui.openPane()
    end

    -- the pane is about the cash register under the cursor, so it follows the
    -- cursor. Cheap: it only redraws its own dozen lines
    vim.api.nvim_create_autocmd('CursorMoved', {
        buffer = buffer,
        callback = function()
            if drawer ~= nil then
                paneRender()
            end
        end,
    })

    -- the preview. Editing a pattern updates the highlights in the buffers
    -- behind the drawer as it is typed, which is the reason to edit here
    -- rather than at a prompt
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
        buffer = buffer,
        callback = function()
            if drawer == nil or drawer.writing then
                return
            end

            enforceNineLines()
            syncFromBuffer()

            -- the selected cash register is shown by vim's own hlsearch on @/,
            -- not by a match, so it is the one register the preview cannot
            -- reach through updateHighlights. Left behind, it keeps painting
            -- whatever it said when the drawer opened -- including after the
            -- row has been emptied, which looks like highlighting that will
            -- not go away
            local cash = drawer.cash
            vim.fn.setreg(
                '/',
                cash.state.cashRegisters[cash.state.currentIndex].pattern
            )

            cash.updateHighlights()
            decorate()
            paneRender()
        end,
    })

    -- closing by any other route still has to forget the drawer
    vim.api.nvim_create_autocmd('WinClosed', {
        pattern = tostring(window),
        once = true,
        callback = function()
            drawer = nil
        end,
    })
end

return ui
