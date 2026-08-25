-- The indicator: the always-on answer to which cash register is the working
-- one.
--
-- Three things, in the order they carry weight:
--
--   - indicator.label is the answer as data. Everything else here is built
--     from it, and so is anything a user builds for a statusline of their own.
--   - indicator.statusline is the same answer in statusline syntax.
--   - indicator.update draws it in a window of this plugin's own.
--
-- The last of those is the only surface Cash.nvim can promise anything about,
-- which is why it is the one that is built in. 'statusline' belongs to
-- whatever set it, and lualine and heirline both write it on every redraw, so
-- a plugin that assigned it would lose the race without a word being said --
-- and at laststatus=0 there is nothing to write to at all. A float of this
-- plugin's own works under all of that. What it costs is being a window that
-- has to be kept in step, which is what update is.

local options = require('cash.options')
local ui = require('cash.ui')
local util = require('cash.util')

local indicator = {}

-- What the indicator says, as data.
--
-- text is the whole thing in one piece, for anywhere a highlight cannot go.
-- chunks is the same text split at every change of color, which is what the
-- float draws with extmarks and what statusline turns into %# items. group is
-- the working cash register's own highlight group, for a statusline plugin
-- that colors a component with one name rather than painting it in pieces
---@class cash.Label
---@field index cash.RegisterIndex the working cash register
---@field pattern string what it holds, as the user typed it
---@field text string
---@field group string
---@field chunks cash.Chunk[]

-- the color a cash register's number is drawn in on the strip.
--
-- Three states in one cell and no room for a marker, so the working cash
-- register is the one wearing its color as a swatch, a cash register holding a
-- pattern wears it as text, and an empty one is drawn in Comment.
--
-- The chooser reads the swatch differently -- there it means "holds a pattern"
-- and the marker answers "working" -- because the chooser is asked which
-- number is the green one and has a column to answer in. The indicator is
-- asked where the user is, from the corner of the screen, and a marker that
-- moved along the strip would shift the other eight numbers about every time
-- the answer changed
---@param cash cash.Module
---@param index cash.RegisterIndex the cell being drawn
---@return string
local stripGroup = function(cash, index)
    if index == cash.state.currentIndex then
        return 'CashRegister' .. index
    end

    if cash.state.cashRegisters[index].pattern == '' then
        return 'Comment'
    end

    return 'CashRegisterFg' .. index
end

-- what the indicator says, as data.
--
-- overrides is the indicator's options with something changed, for a caller
-- that wants an answer other than the configured one: :Cash where asks for the
-- pattern whether or not the indicator is showing it, and a statusline can ask
-- for the narrow style while the float stays on the strip. It is read as it
-- comes, since it never reaches vim as anything but text
---@param cash cash.Module
---@param overrides? cash.IndicatorOptions
---@return cash.Label
indicator.label = function(cash, overrides)
    local opts = cash.opts.indicator
    if overrides ~= nil then
        opts = vim.tbl_extend('force', opts, overrides)
    end

    local index = cash.state.currentIndex
    local register = cash.state.cashRegisters[index]

    -- resolved again here rather than trusted, because an override can name a
    -- pair as well as give one, and overrides do not go through setup
    local brackets = options.resolveBrackets(opts.brackets)

    -- the brackets carry the working cash register's color in both styles. On
    -- the strip they are the only thing that does, since each of the nine
    -- numbers is wearing its own
    local tint = 'CashRegisterFg' .. index

    ---@type cash.Chunk[]
    local chunks = { { brackets.left, tint } }

    -- every chunk names a group, including the spaces between the numbers.
    -- The float would draw an unpainted chunk in NormalFloat and a statusline
    -- would leave it in whatever group came before it, and the two renderings
    -- have to be the same thing
    if opts.style == 'strip' then
        for cell = 1, 9 do
            if cell > 1 then
                table.insert(chunks, { ' ', tint })
            end
            table.insert(chunks, { tostring(cell), stripGroup(cash, cell) })
        end
    else
        table.insert(chunks, { tostring(index), 'CashRegister' .. index })
    end

    if opts.pattern and register.pattern ~= '' then
        table.insert(chunks, {
            ' ' .. util.truncate(register.pattern, opts.patternWidth),
            tint,
        })
    end

    table.insert(chunks, { brackets.right, tint })

    local text = ''
    for _, chunk in ipairs(chunks) do
        text = text .. chunk[1]
    end

    return {
        index = index,
        pattern = register.pattern,
        text = text,
        group = 'CashRegister' .. index,
        chunks = chunks,
    }
end

-- the same label in statusline syntax, for 'statusline', 'winbar' or
-- 'tabline'.
--
-- This has to be embedded as an expression, and specifically as the %{% %}
-- form:
--
--     :set statusline=%f\ %m%=%{%v:lua.require'cash'.statusline()%}
--
-- Vim re-parses the result of that form as statusline items, which is the only
-- thing that makes the %# highlights in here mean anything -- inside a plain
-- %{ } they are printed as the text they are. And a statusline built by
-- concatenating this call at config time holds whatever the label said the
-- moment the config was read, and says it for the rest of the session.
--
-- Every % in the label is doubled, because a cash register holds whatever the
-- user typed and %d is a search for a digit rather than a request to draw the
-- line number
---@param cash cash.Module
---@param overrides? cash.IndicatorOptions as indicator.label takes them
---@return string
indicator.statusline = function(cash, overrides)
    local pieces = {}
    local group = nil

    for _, chunk in ipairs(indicator.label(cash, overrides).chunks) do
        -- named only where it changes, since a statusline keeps drawing in the
        -- last group it was given
        if chunk[2] ~= group then
            group = chunk[2]
            table.insert(pieces, '%#' .. group .. '#')
        end

        table.insert(pieces, (chunk[1]:gsub('%%', '%%%%')))
    end

    -- back to the line's own colors, so that whatever follows the indicator is
    -- not drawn in a cash register's
    table.insert(pieces, '%*')

    return table.concat(pieces)
end

local namespace = vim.api.nvim_create_namespace('CashNvimIndicator')

-- The one buffer every indicator window shows.
--
-- One rather than one each, because there is only ever one thing to say: the
-- working cash register is not per-window or per-tab-page, so a second tab
-- page's indicator says exactly what the first one's does. Sharing the buffer
-- is what makes the text and its extmarks written once however many windows
-- are showing them
---@type integer|nil
local buffer = nil

-- the indicator's window in each tab page it is open in. A float belongs to a
-- tab page rather than to the editor, so there is one of them per tab page the
-- user has visited with the indicator on
---@type table<integer, integer>
local windows = {}

-- what the buffer already says, and where the windows already are. Both are
-- compared before anything is written, because update runs before vim waits
-- for every keypress and almost every one of those finds nothing to do
---@type string|nil
local drawn = nil

---@type { width: integer, row: integer, col: integer }|nil
local geometry = nil

-- the buffer every indicator window shows, made on the first call and after
-- anything has wiped it
---@return integer
local indicatorBuffer = function()
    if buffer ~= nil and vim.api.nvim_buf_is_valid(buffer) then
        return buffer
    end

    buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].buftype = 'nofile'
    vim.bo[buffer].bufhidden = 'hide'
    vim.bo[buffer].swapfile = false

    -- the indicator can hold a pattern as literal text, so it is kept out of
    -- the highlighting the way the drawer, the chooser and the picker are.
    -- Painted in the colors it is reporting, it would be reporting the colors
    -- it is painted in
    vim.b[buffer].cashDrawer = true

    -- a new buffer says nothing yet, whatever the last one said
    drawn = nil

    return buffer
end

-- puts the label in the buffer, when it is not there already
---@param label cash.Label
local draw = function(label)
    local target = indicatorBuffer()

    if drawn == label.text then
        return
    end

    vim.api.nvim_buf_set_lines(target, 0, -1, false, { label.text })
    vim.api.nvim_buf_clear_namespace(target, namespace, 0, -1)

    local column = 0
    for _, chunk in ipairs(label.chunks) do
        vim.api.nvim_buf_set_extmark(target, namespace, 0, column, {
            end_col = column + #chunk[1],
            hl_group = chunk[2],
        })
        column = column + #chunk[1]
    end

    drawn = label.text
end

-- opens the indicator in the current tab page
---@param width integer in display cells
---@param where { row: integer, col: integer }
---@return integer window
local openWindow = function(width, where)
    local window = vim.api.nvim_open_win(indicatorBuffer(), false, {
        relative = 'editor',
        width = width,
        height = 1,
        row = where.row,
        col = where.col,
        style = 'minimal',
        -- there is nothing in here to do, and a focusable float is one more
        -- window for CTRL-W and :wincmd to land in
        focusable = false,
        -- nvim_open_win fires WinNew while the new window is still showing the
        -- buffer the user came from, and nothing in here wants an autocmd
        -- anyway
        noautocmd = true,
        -- under the 50 a float gets by default, so that the indicator is never
        -- the thing covering a completion menu, the cash drawer, or anything
        -- else that is on screen because it was asked for
        zindex = 45,
    })

    -- vim's own hlsearch matches the pattern the indicator is holding as text,
    -- which would paint the indicator in the color it is reporting. Same
    -- reasoning as the chooser, and the empty group is set here rather than
    -- once during setup because a colorscheme could have cleared it since
    vim.api.nvim_set_hl(0, 'CashDrawerNoSearch', {})
    vim.wo[window].winhighlight = table.concat({
        'Search:CashDrawerNoSearch',
        'CurSearch:CashDrawerNoSearch',
        'IncSearch:CashDrawerNoSearch',
    }, ',')

    return window
end

-- takes the indicator off the screen. The buffer is kept, since what it holds
-- is worked out from the state and not from anything that has been lost
local hide = function()
    for tabpage, window in pairs(windows) do
        if vim.api.nvim_win_is_valid(window) then
            vim.api.nvim_win_close(window, true)
        end
        windows[tabpage] = nil
    end

    geometry = nil
end

-- Makes this true:
--
--     the indicator is on screen in the current tab page exactly when
--     indicator.show is on and the cash drawer is not, and it says what the
--     label says.
--
-- The same shape as highlights.update, for the same reason: anything that can
-- invalidate what is on screen calls this rather than working out what to
-- redraw. It is idempotent, and a call that finds nothing out of place does
-- not touch vim at all -- which it has to be, because it runs before vim waits
-- for every keypress
---@param cash cash.Module
indicator.update = function(cash)
    -- read first, so that the default costs one table lookup per keystroke.
    -- The cash drawer is the second way out: it says everything the indicator
    -- says and eight more things besides, and drawer.position can put the two
    -- of them in the same corner
    if not cash.opts.indicator.show or ui.isOpen() then
        if next(windows) ~= nil then
            hide()
        end
        return
    end

    local label = indicator.label(cash)
    draw(label)

    -- a label wider than the screen is drawn as much of itself as fits rather
    -- than as a window vim refuses to open
    local width =
        math.max(1, math.min(vim.fn.strdisplaywidth(label.text), vim.o.columns))
    local where = ui.placement(cash.opts.indicator.position, width, 1, 0)
    local moved = geometry == nil
        or geometry.width ~= width
        or geometry.row ~= where.row
        or geometry.col ~= where.col

    for tabpage, window in pairs(windows) do
        -- a tab page that has been closed took its float with it, and a window
        -- something else closed is not one to keep a handle on
        if
            not vim.api.nvim_tabpage_is_valid(tabpage)
            or not vim.api.nvim_win_is_valid(window)
        then
            windows[tabpage] = nil
        elseif moved then
            vim.api.nvim_win_set_config(window, {
                relative = 'editor',
                width = width,
                height = 1,
                row = where.row,
                col = where.col,
            })
        end
    end

    local tabpage = vim.api.nvim_get_current_tabpage()
    if windows[tabpage] == nil then
        windows[tabpage] = openWindow(width, where)
    end

    geometry = { width = width, row = where.row, col = where.col }
end

-- the indicator's windows, lowest handle first.
--
-- Which tab pages it is open in is not observable from anywhere else, and it
-- is what a test has to ask about to find out whether opening it twice opened
-- it twice
---@return integer[]
indicator.windows = function()
    local result = {}

    for _, window in pairs(windows) do
        if vim.api.nvim_win_is_valid(window) then
            table.insert(result, window)
        end
    end

    table.sort(result)
    return result
end

return indicator
