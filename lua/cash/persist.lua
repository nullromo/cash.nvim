local util = require('cash.util')

-- what goes into the shada file. The field names are shorter than the ones in
-- cash.State because they are written to a file the user can look at, and
-- because they are read back by name: renaming one is a format change
---@class cash.SerializedState
---@field version integer the format version, checked on the way back in
---@field index cash.RegisterIndex the working cash register
---@field registers cash.Register[] nine of them
---@field searchRegister string what @/ held when this was written

-- what came back out of the shada file, once every field has been checked. The
-- search register is carried alongside the cash registers so that the next
-- session can tell whether something set @/ during startup; it is only ever
-- compared against, never installed
---@class cash.StoredState : cash.State
---@field searchRegister string

local persist = {}

-- the shada file carries a global variable from one neovim to the next when
-- its name is written in capitals with no lowercase letter anywhere in it.
-- That is what the ! flag in 'shada' selects, and it is why this is not
-- g:cash. Nothing else about the name matters, so it is spelled out in full
-- rather than shortened: it is a name in a namespace shared with every other
-- plugin, and it is a name the user can look at with :echo and remove with
-- :unlet
persist.variableName = 'CASH_NVIM'

-- bumped only when the shape written below changes in a way that an older
-- Cash.nvim would read as something it is not. A stored version this one does
-- not recognise is left alone rather than guessed at, so a downgrade loses the
-- cash registers instead of misreading them
persist.formatVersion = 1

-- true when shada has been switched off altogether. nvim -l, nvim -i NONE and
-- embedded sessions all do this, and it is only ever done on purpose, so it is
-- the one unavailable case that says nothing about itself. Only an uppercase
-- NONE counts, which is 'shadafile' 's own rule
---@return boolean
persist.shadaIsOff = function()
    return vim.o.shadafile == 'NONE'
end

-- true when 'shada' still has the ! flag that makes it save and restore global
-- variables. Compared item by item rather than searched for, so that a ! inside
-- an r/path/ item cannot answer for the flag
---@return boolean
persist.carriesGlobals = function()
    for _, item in ipairs(vim.split(vim.o.shada, ',', { trimempty = true })) do
        if item == '!' then
            return true
        end
    end

    return false
end

-- says so, once, when this plugin has been asked to persist cash registers and
-- shada is not going to carry them.
--
-- The two unavailable cases are told apart deliberately. Shada switched off
-- altogether is a decision made by whoever started this neovim, and gets no
-- message. Shada left on with its ! flag taken out is a configuration that
-- means to keep a shada file and has given up global variables without
-- noticing, which is worth one line at startup. It cannot fire on a default
-- neovim, because ! is in the default 'shada'
persist.warnIfUnavailable = function()
    if persist.shadaIsOff() or persist.carriesGlobals() then
        return
    end

    vim.notify(
        'Cash.nvim: cash registers cannot be persisted, because "shada" has '
            .. 'no ! flag. Add ! to "shada", or set persistCashRegisters = '
            .. 'false to stop this message',
        vim.log.levels.WARN
    )
end

-- turns the module state into the table that goes into the shada file. The
-- search register is stored alongside the cash registers, not because anything
-- reads it back as a value, but so that the next session can tell whether
-- something changed it during startup. See CashModule.restoreCashRegisters
---@param state cash.State
---@return cash.SerializedState
persist.serialize = function(state)
    local registers = {}
    for index = 1, 9 do
        registers[index] = {
            pattern = state.cashRegisters[index].pattern,
            includeInSearch = state.cashRegisters[index].includeInSearch
                    and true
                or false,
        }
    end

    return {
        version = persist.formatVersion,
        index = state.currentIndex,
        registers = registers,
        searchRegister = vim.fn.getreg('/'),
    }
end

-- vim.g hands booleans back as booleans, so this is only ever asked about a
-- value that vimscript or a person put there. Anything that is not plainly on
-- is off: a cash register wrongly left out of the search set is a smaller
-- surprise than one wrongly in it
---@param value any whatever vimscript or a person left in the shada file
---@return boolean
local isOn = function(value)
    return value == true or value == 1
end

-- one stored cash register. A malformed entry becomes an empty cash register
-- rather than taking the other eight down with it, since the eight are
-- perfectly good and there is nothing better to put in the ninth
---@param stored any
---@return cash.Register
local readRegister = function(stored)
    if type(stored) ~= 'table' or type(stored.pattern) ~= 'string' then
        return { pattern = '', includeInSearch = false }
    end

    return {
        pattern = stored.pattern,
        includeInSearch = isOn(stored.includeInSearch),
    }
end

-- turns what came out of the shada file back into cash registers, or nil if
-- there is nothing usable there.
--
-- Every field is checked rather than trusted. The shada file outlives any one
-- version of this plugin, it can be hand-edited, and g:CASH_NVIM is a name
-- anything else can write to, so a stored value that is not the shape this
-- version writes must not reach the rest of the plugin. nil means "carry on
-- with the defaults", which is what a first run does anyway
---@param stored any straight out of g:CASH_NVIM, so trusted for nothing
---@return cash.StoredState|nil
persist.deserialize = function(stored)
    if type(stored) ~= 'table' or stored.version ~= persist.formatVersion then
        return nil
    end

    if type(stored.registers) ~= 'table' then
        return nil
    end

    local cashRegisters = {}
    for index = 1, 9 do
        cashRegisters[index] = readRegister(stored.registers[index])
    end

    return {
        currentIndex = util.isCashRegisterIndex(stored.index) and stored.index
            or 1,
        cashRegisters = cashRegisters,
        -- what the search register held when this was written. Only ever
        -- compared against, never installed
        searchRegister = type(stored.searchRegister) == 'string'
                and stored.searchRegister
            or '',
    }
end

-- puts the state where shada will find it. Whether shada is actually in a
-- position to write it is not asked here: this sets a global variable, and what
-- becomes of a global variable is shada's business, which also makes it the
-- one part of persistence that can be tested in a neovim that has no shada file
---@param state cash.State
persist.save = function(state)
    vim.g[persist.variableName] = persist.serialize(state)
end

-- what the last session left behind, or nil if there is nothing to put back
---@return cash.StoredState|nil
persist.load = function()
    return persist.deserialize(vim.g[persist.variableName])
end

return persist
