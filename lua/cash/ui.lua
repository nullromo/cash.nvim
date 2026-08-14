-- The cash drawer: the popup that :Cash opens.
--
-- The buffer holds nothing but the nine search patterns, one per line.
-- Everything else on screen -- the marker, the register number, the include
-- dot, the match count, the header, the legend, the key hints -- is an
-- extmark. So there is no chrome for an edit to damage, the cursor can never
-- get into it, and G lands on cash register 9 rather than on a key hint.

local highlights = require('cash.highlights')
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

-- how many matches a cash register has in the buffer the user came from.
-- Bounded on both sides: maxcount stops a pattern that matches nearly every
-- character from being counted to the end, and timeout stops an expensive one
-- from being counted at all
local matchCount = function(originWindow, matchPattern)
    local counted = nil

    pcall(vim.api.nvim_win_call, originWindow, function()
        counted = vim.fn.searchcount({
            pattern = matchPattern,
            maxcount = 999,
            timeout = 50,
        })
    end)

    if counted == nil or counted.total == nil then
        return ''
    end
    if counted.incomplete == 2 then
        return '999+'
    end
    return tostring(counted.total)
end

-- one row of the gutter, as extmark chunks.
--
-- The plain spaces are left without a highlight group on purpose. Naming one
-- would paint them, and they would then punch holes through cursorline on the
-- row the cursor is on
local gutterFor = function(cash, index)
    local register = cash.state.cashRegisters[index]
    local isWorking = index == cash.state.currentIndex
    local colored = 'CashRegisterFg' .. index

    return {
        { '  ' },
        { isWorking and '▸' or ' ', colored },
        { ' ' },
        { tostring(index), 'CashRegister' .. index },
        { '  ' },
        {
            (isWorking or register.includeInSearch) and '●' or '○',
            (isWorking or register.includeInSearch) and colored or 'Comment',
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

-- draws everything that is not the patterns themselves. Clears first, so that
-- it can be called again after anything at all has changed
local render = function()
    local cash = drawer.cash
    local buffer = drawer.buffer

    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)

    local patterns = {}
    for index = 1, 9 do
        table.insert(patterns, cash.state.cashRegisters[index].pattern)
    end

    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, patterns)
    vim.bo[buffer].modifiable = false

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

            local count = matchCount(
                drawer.originWindow,
                util.resolveCase(register.pattern)
            )
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

-- the cash register the cursor is on
local registerUnderCursor = function()
    return vim.api.nvim_win_get_cursor(drawer.window)[1]
end

local setUpKeymaps = function(cash)
    local buffer = drawer.buffer
    local map = function(key, action)
        vim.keymap.set('n', key, action, { buffer = buffer, nowait = true })
    end

    map('q', ui.close)
    map('<Esc>', ui.close)
    map('<C-c>', ui.close)

    map('<CR>', function()
        cash.setCashRegister(registerUnderCursor())
        ui.close()
    end)

    map('<Tab>', function()
        cash.setCashRegister(registerUnderCursor())
        render()
    end)

    map('<Space>', function()
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
        render()
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

    map(']', swap(1))
    map('[', swap(-1))

    map('?', function()
        vim.notify(
            'Cash.nvim: the detail pane is not built yet',
            vim.log.levels.INFO
        )
    end)
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

    local window = vim.api.nvim_open_win(buffer, true, {
        relative = 'editor',
        width = WIDTH,
        height = height,
        row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
        col = math.max(0, math.floor((vim.o.columns - WIDTH) / 2)),
        style = 'minimal',
        border = cash.opts.ui.border,
        -- opening a window fires WinNew while it is still showing the buffer
        -- the user came from, so the update that triggers would add a match to
        -- the drawer's window before the drawer's buffer is even in it. The
        -- match would then stay there, on a buffer full of search patterns.
        -- Nothing needs updating for a window that is excluded anyway
        noautocmd = true,
        -- the leading dash continues the border rather than sitting apart
        -- from it, which needs the title drawn in the border's own colors.
        -- FloatTitle is a global group, so it is redirected for this window
        -- only
        title = '─ Cash.nvim Registers ',
        title_pos = 'left',
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
    -- here. That is not the ledger and excluding the window from it does not
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
    }

    render()
    setUpKeymaps(cash)

    vim.api.nvim_win_set_cursor(window, { cash.state.currentIndex, 0 })

    -- closing the window by any other route still has to forget the drawer
    vim.api.nvim_create_autocmd('WinClosed', {
        pattern = tostring(window),
        once = true,
        callback = function()
            drawer = nil
        end,
    })
end

-- kept out of highlights.lua, which has no business knowing the drawer exists
ui.namespace = namespace

return ui
