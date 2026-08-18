local cash = require('cash.cash')
local keymaps = require('cash.keymaps')
local options = require('cash.options')
local persist = require('cash.persist')

-- What :checkhealth cash reports.
--
-- Everything in here is something that can be wrong without anything having
-- gone wrong loudly. This plugin's failures are quiet ones: colors that do not
-- render, eight cash registers that stop painting, a mapping something else
-- took, patterns that did not come back from the last session. None of those
-- raise an error, and every one of them looks from the outside like the plugin
-- being broken. This is where they get to say what actually happened.
--
-- Nothing here changes anything. A health check that repaired what it found
-- would report a plugin that works and leave the user with one that only works
-- after they run :checkhealth
local health = {}

-- the oldest neovim this plugin is documented to run on. |cash-requirements|
-- in doc/cash.txt says the same number, and the two have to keep saying the
-- same number
local minimumVersion = { major = 0, minor = 10 }

-- the running neovim as major.minor.patch. Built out of the fields rather than
-- handed to tostring, because the one time this string matters is on a neovim
-- older than the minimum, and a version check that leans on anything newer
-- than the version it is checking for is no version check at all
---@return string
local versionString = function()
    local version = vim.version()
    return version.major .. '.' .. version.minor .. '.' .. version.patch
end

-- true when the mapping currently on a key is one this plugin made. Every
-- mapping Cash.nvim sets carries the same desc prefix, which is also how
-- addKeyTrigger tells its own work apart from someone else's
---@param keymap table whatever maparg handed back
---@return boolean
local isOurs = function(keymap)
    return type(keymap.desc) == 'string'
        and vim.startswith(keymap.desc, keymaps.ownMapping)
end

-- names the mapping that took a key, so that the report says who to go and
-- look at rather than only that somebody is there. A description is what the
-- other plugin chose to be called; a right-hand side is the next best thing;
-- a callback with neither is all that is left to say
---@param keymap table whatever maparg handed back
---@return string
local describeMapping = function(keymap)
    if type(keymap.desc) == 'string' and keymap.desc ~= '' then
        return keymap.desc
    end

    if type(keymap.rhs) == 'string' and keymap.rhs ~= '' then
        return keymap.rhs
    end

    return 'a lua callback with no description'
end

-- one key this plugin maps, and what stops working when something else owns it
---@class cash.ClaimedKey
---@field mode string
---@field key string
---@field label string the key as it should read in the report
---@field breaks string what the user loses, as a sentence of its own

-- every key Cash.nvim maps. n and N are checked only when manageJumps is on,
-- which is the one claim the user can call off
---@type cash.ClaimedKey[]
local claimedKeys = {
    {
        mode = 'n',
        key = '?',
        label = '?',
        breaks = 'The chooser is out of reach, though :Cash use <number> '
            .. 'still switches cash registers.',
    },
    {
        mode = 'n',
        key = '*',
        label = '*',
        breaks = 'Searching with * no longer fills the working cash '
            .. 'register.',
    },
    {
        mode = 'n',
        key = '#',
        label = '#',
        breaks = 'Searching with # no longer fills the working cash '
            .. 'register.',
    },
    {
        mode = 'n',
        key = 'g*',
        label = 'g*',
        breaks = 'Searching with g* no longer fills the working cash '
            .. 'register.',
    },
    {
        mode = 'n',
        key = 'g#',
        label = 'g#',
        breaks = 'Searching with g# no longer fills the working cash '
            .. 'register.',
    },
    {
        mode = 'c',
        key = '<CR>',
        label = '<CR> in the command line',
        breaks = 'A / search no longer fills the working cash register, '
            .. 'and centerAfterSearch does nothing for it.',
    },
}

-- the two keys manageJumps asks for, kept apart from the rest because whether
-- they are claimed at all is an option
---@type cash.ClaimedKey[]
local jumpKeys = {
    {
        mode = 'n',
        key = 'n',
        label = 'n',
        breaks = 'Include-in-search stops working: n visits the matches of '
            .. 'the working cash register only.',
    },
    {
        mode = 'n',
        key = 'N',
        label = 'N',
        breaks = 'Include-in-search stops working: N visits the matches of '
            .. 'the working cash register only.',
    },
}

-- reports on one key: ours, somebody else's, or nobody's
---@param claimed cash.ClaimedKey
local checkKey = function(claimed)
    local keymap = vim.fn.maparg(claimed.key, claimed.mode, false, true) --[[@as table]]

    if next(keymap) == nil then
        vim.health.warn(
            claimed.label .. ' is not mapped',
            'Cash.nvim mapped it during setup and something has removed '
                .. 'it. '
                .. claimed.breaks
        )
        return
    end

    if isOurs(keymap) then
        vim.health.ok(claimed.label .. " is Cash.nvim's")
        return
    end

    vim.health.warn(
        claimed.label
            .. ' belongs to something else: '
            .. describeMapping(keymap),
        'Whatever set it loaded after Cash.nvim did and replaced the '
            .. 'mapping rather than wrapping it. '
            .. claimed.breaks
    )
end

-- the two documented requirements, which are the two ways this plugin can be
-- installed correctly and still look wrong
local checkRequirements = function()
    vim.health.start('Requirements')

    local version = vim.version()
    local running = versionString()
    local wanted = minimumVersion.major .. '.' .. minimumVersion.minor

    if
        version.major > minimumVersion.major
        or (
            version.major == minimumVersion.major
            and version.minor >= minimumVersion.minor
        )
    then
        vim.health.ok('Neovim ' .. running)
    else
        vim.health.error(
            'Neovim ' .. running .. ' is older than ' .. wanted,
            'Cash.nvim needs Neovim '
                .. wanted
                .. ' or newer. The cash drawer is drawn with inline virtual '
                .. 'text, which older versions cannot render'
        )
    end

    if vim.o.termguicolors then
        vim.health.ok("'termguicolors' is on")
    else
        vim.health.warn(
            "'termguicolors' is off",
            'Cash register colors are given as #RRGGBB, which needs '
                .. "'termguicolors'. Without it every cash register looks "
                .. 'the same and searching appears to do nothing. Set '
                .. 'vim.o.termguicolors = true, or give every cash register a '
                .. 'cterm color of its own'
        )
    end
end

-- whether setup ran at all. Returns false when it did not, since everything
-- below this reads options that setup is what puts there
---@return boolean
local checkSetup = function()
    vim.health.start('Setup')

    if cash.opts == nil then
        vim.health.error(
            "require('cash').setup() has not been called",
            'Cash.nvim maps nothing and holds nothing until setup runs. Call '
                .. "require('cash').setup({}) from your config, or give "
                .. 'your plugin manager an opts table so it calls setup for '
                .. 'you'
        )
        return false
    end

    vim.health.ok('setup has run')
    return true
end

-- the options the user has actually got, which is what makes a bug report
-- usable on arrival. Only what differs from the defaults, since the defaults
-- are already written down
local checkConfiguration = function()
    vim.health.start('Configuration')

    local changed = {}
    for key, default in pairs(options.defaultOptions) do
        if not vim.deep_equal(cash.opts[key], default) then
            table.insert(
                changed,
                key
                    .. ' = '
                    .. vim.inspect(
                        cash.opts[key],
                        { newline = ' ', indent = '' }
                    )
            )
        end
    end
    table.sort(changed)

    if #changed == 0 then
        vim.health.ok('every option is at its default')
        return
    end

    -- info rather than ok: a changed option is not a problem, it is the first
    -- thing anyone reading this report needs to know
    vim.health.info('options that differ from their defaults:')
    for _, line in ipairs(changed) do
        vim.health.info(line)
    end
end

local checkMappings = function()
    vim.health.start('Mappings')

    for _, claimed in ipairs(claimedKeys) do
        checkKey(claimed)
    end

    if not cash.opts.manageJumps then
        vim.health.info(
            'manageJumps is off, so n and N are left alone. '
                .. 'Include-in-search does nothing while it is off'
        )
        return
    end

    for _, claimed in ipairs(jumpKeys) do
        checkKey(claimed)
    end
end

-- whether the nine highlight groups still exist.
--
-- Worth asking because they are created once, during setup, and a colorscheme
-- loaded afterwards clears every highlight group it did not set itself. The
-- working cash register survives that, since its color goes on the Search
-- group on every update; the other eight do not, and their matches carry on
-- matching while painting nothing at all
local checkHighlightGroups = function()
    vim.health.start('Highlight groups')

    local missing = {}
    for index = 1, 9 do
        local name = 'CashRegister' .. index
        if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = name })) then
            table.insert(missing, name)
        end
    end

    if #missing == 0 then
        vim.health.ok('CashRegister1 to CashRegister9 are all defined')
        return
    end

    vim.health.warn(
        'these highlight groups are empty: ' .. table.concat(missing, ', '),
        'Cash.nvim defines them during setup, and a colorscheme loaded after '
            .. 'setup clears them. Their cash registers are still matching, '
            .. 'but the matches have no color to paint. Run '
            .. "require('cash').setup() again after your colorscheme, or "
            .. 'from a ColorScheme autocommand'
    )
end

-- whether the cash registers will survive this neovim, and what the last one
-- left behind
local checkPersistence = function()
    vim.health.start('Persistence')

    if not cash.opts.persistCashRegisters then
        vim.health.info(
            'persistCashRegisters is off, so every session starts with nine '
                .. 'empty cash registers'
        )
        return
    end

    if persist.shadaIsOff() then
        vim.health.info(
            "'shadafile' is NONE, so this neovim was started without shada "
                .. 'and nothing will be carried to the next one. nvim -l, '
                .. 'nvim -i NONE and embedded sessions all do this on purpose'
        )
    elseif not persist.carriesGlobals() then
        vim.health.warn(
            "'shada' has no ! flag, so the cash registers cannot be saved",
            'The ! flag is what makes shada carry global variables, and it is '
                .. "in the default 'shada'. Add ! to 'shada', or set "
                .. 'persistCashRegisters = false'
        )
    else
        vim.health.ok(
            "'shada' has the ! flag, so the cash registers are carried in "
                .. 'g:'
                .. persist.variableName
        )
    end

    -- what is in the variable right now, which is what the last session left.
    -- "My cash registers did not come back" is otherwise a question nothing
    -- can answer
    local stored = persist.load()

    if stored == nil then
        if vim.g[persist.variableName] == nil then
            vim.health.info(
                'g:'
                    .. persist.variableName
                    .. ' is empty. Nothing has been saved yet, which is what '
                    .. 'a first run looks like'
            )
            return
        end

        vim.health.warn(
            'g:'
                .. persist.variableName
                .. ' holds something this version of Cash.nvim cannot read',
            'It is left alone rather than guessed at, so this session started '
                .. 'with nine empty cash registers. A downgrade does this. '
                .. 'The next clean exit writes it back in the current format, '
                .. 'which is version '
                .. persist.formatVersion
        )
        return
    end

    local filled = 0
    for index = 1, 9 do
        if stored.cashRegisters[index].pattern ~= '' then
            filled = filled + 1
        end
    end

    vim.health.ok(
        'g:'
            .. persist.variableName
            .. ' holds a readable set: '
            .. filled
            .. ' of 9 cash registers have a pattern, and the working one is '
            .. stored.currentIndex
    )
end

-- what :checkhealth cash calls
health.check = function()
    checkRequirements()

    if not checkSetup() then
        return
    end

    checkConfiguration()
    checkMappings()
    checkHighlightGroups()
    checkPersistence()
end

return health
