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

-- the drawer while it is open, nil the rest of the time
local drawer = nil

local FOOTER = {
    { '<CR>', 'select reg, close', '<Tab>', 'select reg, stay open' },
    { '<Space>', 'toggle include', ']/[', 'swap register down/up' },
    { '?', 'show details', '<C-c>', 'close, undo changes' },
    { 'q/<Esc>', 'apply and close' },
}

-- written out rather than padded into place, because box drawing characters
-- are several bytes each and the alignment here has to be exact
local LEGEND = {
    { '  │ │  │' },
    { '  │ │  ╰─', 'Include in search' },
    { '  │ ╰─', 'Cash register number' },
    { '  ╰─', 'Selected cash register' },
}

local pad = function(text, width)
    return text .. string.rep(' ', math.max(0, width - #text))
end

-- where a popup sits, as a fraction of the space left over once it has been
-- placed. 0 is flush against the top or left, 1 against the bottom or right
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

-- the row and column for a popup of this size in this position. The border
-- adds a row and a column on each side, and the command line and status line
-- are not free to be covered, so neither counts as space to place into
local placement = function(position, width, height)
    local fraction = PLACEMENT[position] or PLACEMENT['center']

    local rowsFree = vim.o.lines - vim.o.cmdheight - 1 - (height + 2)
    local columnsFree = vim.o.columns - (width + 2)

    return {
        row = math.max(0, math.floor(rowsFree * fraction[1])),
        col = math.max(0, math.floor(columnsFree * fraction[2])),
    }
end

-- a line under construction, kept as text plus the highlights that go over it.
-- Built together because the highlights are byte ranges into the text, and a
-- pattern can hold anything the user typed, multibyte included
local newRow = function()
    return { text = '', marks = {} }
end

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

local padRowTo = function(row, width)
    local shortfall = width - vim.fn.strdisplaywidth(row.text)
    if shortfall > 0 then
        addChunk(row, string.rep(' ', shortfall))
    end
end

local truncate = function(text, width)
    if vim.fn.strdisplaywidth(text) <= width then
        return text
    end
    return vim.fn.strcharpart(text, 0, width - 1) .. '~'
end

-- how many matches a cash register has in the buffer the user came from.
--
-- Bounded on both sides: maxcount stops a pattern matching nearly every
-- character from being counted to the end, and timeout stops an expensive one
-- from being counted at all. Bounded is not cheap enough on its own, though,
-- because the counts are redrawn on every keystroke while a pattern is being
-- typed -- so an answer is only worked out for a pattern that has not been
-- asked about before
local matchCount = function(matchPattern)
    local cached = drawer.counts[matchPattern]
    if cached ~= nil then
        return cached
    end

    local counted = nil
    pcall(vim.api.nvim_win_call, drawer.originWindow, function()
        counted = vim.fn.searchcount({
            pattern = matchPattern,
            maxcount = 999,
            timeout = 50,
        })
    end)

    local answer = ''
    if counted ~= nil and counted.total ~= nil then
        answer = counted.incomplete == 2 and '999+' or tostring(counted.total)
    end

    drawer.counts[matchPattern] = answer
    return answer
end

-- one row of the gutter, as extmark chunks.
--
-- The plain spaces are left without a highlight group on purpose. Naming one
-- would paint them, and they would then punch holes through cursorline on the
-- row the cursor is on
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
local winbar = function()
    return '%#Comment#'
        .. string.rep(' ', GUTTER)
        .. 'Register contents%=Match count   '
end

-- the line naming the search set. It is the only place the drawer says which
-- cash registers n and N will visit, since an included register looks exactly
-- like an excluded one out in the buffer
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

local separatorLine = function()
    return { { string.rep('─', WIDTH), 'NonText' } }
end

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
local writeLines = function(forgetUndo)
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

local render = function(forgetUndo)
    writeLines(forgetUndo)
    decorate()
end

-- there are always nine cash registers, so there are always nine lines.
--
-- dd, o and insert-mode <CR> are mapped away, but this is the backstop for
-- everything that was not thought of: a linewise paste, a visual line delete,
-- :move, a macro. Repairing is better than refusing, since refusing would mean
-- watching every route into the buffer rather than the one invariant
local enforceNineLines = function()
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
    pcall(vim.cmd, 'silent! undojoin')

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
    local lines = vim.api.nvim_buf_get_lines(drawer.buffer, 0, 9, false)
    for index = 1, 9 do
        drawer.cash.state.cashRegisters[index].pattern = lines[index] or ''
    end
end

ui.isOpen = function()
    return drawer ~= nil and vim.api.nvim_win_is_valid(drawer.window)
end

ui.close = function()
    if drawer == nil then
        return
    end

    local window = drawer.window
    drawer = nil

    if vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_close(window, true)
    end
end

-- everything the user typed is already in the cash registers, because the
-- preview put it there as they typed. What is left is the search register,
-- which mirrors the selected cash register and would otherwise still hold what
-- that register said when the drawer opened
local apply = function()
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
    local cash = drawer.cash
    cash.state.cashRegisters = drawer.snapshot.cashRegisters
    cash.state.currentIndex = drawer.snapshot.currentIndex

    local pattern = cash.state.cashRegisters[cash.state.currentIndex].pattern
    vim.fn.setreg('/', pattern)

    cash.updateHighlights()
    ui.close()
end

local registerUnderCursor = function()
    return vim.api.nvim_win_get_cursor(drawer.window)[1]
end

-- selecting a cash register searches for its pattern, and that has to happen
-- in the window the user came from. Run with the drawer focused, the jump
-- would land in the list of patterns instead
local selectRegister = function(index)
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

local setUpKeymaps = function(cash)
    local buffer = drawer.buffer
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
    end)

    -- swapping moves the pattern and the switch, but not the color: that
    -- belongs to the slot, which is what makes this a way to recolor a search
    local swap = function(step)
        return function()
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
        vim.notify(
            'Cash.nvim: the detail pane is not built yet',
            vim.log.levels.INFO
        )
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

-- a grid cell is the marker, the number, a space and the pattern
local CHOOSER_COLUMN = 12
local CHOOSER_PATTERN = CHOOSER_COLUMN - 5

local chooserCell = function(row, cash, index, patternWidth)
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

    addChunk(
        row,
        ' ' .. index .. ' ',
        filled and ('CashRegister' .. index) or ('CashRegisterFg' .. index)
    )

    if patternWidth == nil then
        return
    end

    addChunk(row, ' ')
    if filled then
        addChunk(
            row,
            truncate(register.pattern, patternWidth),
            'CashRegister' .. index
        )
    else
        addChunk(row, '·', 'Comment')
    end
end

-- 'grid' lays the nine out the way a numpad does, which is not a coincidence
-- worth wasting, and shows what each one holds. 'strip' is one line of numbers
-- for when that is the only question
local chooserRows = function(cash, style)
    local rows = {}

    if style == 'strip' then
        local row = newRow()
        addChunk(row, '  ')
        for index = 1, 9 do
            chooserCell(row, cash, index)
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
            chooserCell(row, cash, line * 3 + column + 1, CHOOSER_PATTERN)
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
ui.openChooser = function(cash, style)
    local rows = chooserRows(cash, style or cash.opts.prompt.style)

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

    local where = placement(cash.opts.prompt.position, width, #rows)
    local window = vim.api.nvim_open_win(buffer, false, {
        relative = 'editor',
        width = width,
        height = #rows,
        row = where.row,
        col = where.col,
        style = 'minimal',
        border = cash.opts.prompt.border,
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

-- shows the chooser and waits for one keypress. Returns the cash register the
-- user picked, or nil if they pressed anything else
ui.chooseRegister = function(cash)
    local window = nil

    if cash.opts.prompt.style == 'none' then
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

    if not pressed then
        return nil
    end

    local index = tonumber(vim.fn.nr2char(character))
    if not util.isCashRegisterIndex(index) then
        return nil
    end
    return index
end

ui.open = function(cash)
    if ui.isOpen() then
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

    local where = placement(cash.opts.ui.position, WIDTH, height)

    local window = vim.api.nvim_open_win(buffer, true, {
        relative = 'editor',
        width = WIDTH,
        height = height,
        row = where.row,
        col = where.col,
        style = 'minimal',
        border = cash.opts.ui.border,
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
