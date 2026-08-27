-- Minimal test harness for Cash.nvim.
--
-- Tests run inside a real Neovim, because everything worth testing here is
-- about what vim actually does with matches, windows, and search patterns. A
-- fake would have to reimplement enough of vim to be trustworthy, so there
-- isn't one, and there is no test framework dependency either.
--
-- Run the suite with:
--
--     nvim --headless -u NONE -l tests/run.lua

local harness = {}

local passed = 0
local failed = 0
local known = 0

-- the plugin's own directory, so the suite can be run from anywhere
harness.pluginRoot =
    vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

harness.group = function(name)
    print('\n' .. name)
end

harness.check = function(name, condition, detail)
    if condition then
        passed = passed + 1
        print('  ok     ' .. name)
    else
        failed = failed + 1
        print('  FAIL   ' .. name)
        if detail then
            print('           ' .. detail)
        end
    end
end

-- for behaviour that is known to be wrong and not fixed yet. It reports
-- without failing the run, but fails if it ever starts passing, so that the
-- check gets promoted to a real one when the bug is dealt with
harness.knownBroken = function(name, condition, detail)
    if condition then
        failed = failed + 1
        print('  FIXED  ' .. name)
        print('           this passes now; make it a normal check')
    else
        known = known + 1
        print('  known  ' .. name)
        if detail then
            print('           ' .. detail)
        end
    end
end

-- What the cash registers are painting in a window, as a map from cash register
-- index to the pattern it is painting.
--
-- A cash register's highlighting is an extmark added while vim is drawing and
-- gone again afterwards, so there is nothing left behind to read: the plugin
-- has to be asked instead. These three are what the suite used to ask
-- vim.fn.getmatches() for, and they are here rather than in each spec because
-- six of them need the same question
---@param windowID? integer the current window when left out
---@return table<integer, string>
harness.lit = function(windowID)
    return require('cash.highlights').litCashRegisters(windowID)
end

-- how many cash registers are painting in a window
---@param windowID? integer
---@return integer
harness.litCount = function(windowID)
    return vim.tbl_count(harness.lit(windowID))
end

-- the pattern one cash register is painting in a window, or nil when it is
-- painting nothing
---@param windowID? integer
---@param index integer
---@return string|nil
harness.litPattern = function(windowID, index)
    return harness.lit(windowID)[index]
end

-- every cash register painting in a window, as "CashRegisterN=pattern", sorted
-- so that it can be compared as a single string
---@param windowID? integer
---@return string
harness.litSummary = function(windowID)
    local out = {}
    for index, matchPattern in pairs(harness.lit(windowID)) do
        table.insert(out, 'CashRegister' .. index .. '=' .. matchPattern)
    end
    table.sort(out)
    return table.concat(out, ' ')
end

-- returns the number of failures, so the runner can set an exit code
harness.summary = function()
    print(
        string.format(
            '\n%d passed, %d failed, %d known broken',
            passed,
            failed,
            known
        )
    )
    return failed
end

return harness
