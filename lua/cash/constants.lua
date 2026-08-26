local constants = {}

-- color constants taken from kanagawa.nvim
---@type table<string, string>
constants.colors = {
    sumiInk0 = '#16161D',
    fujiWhite = '#DCD7BA',
    roninYellow = '#FF9E3B',
    springBlue = '#7FB4CA',
    sakuraPink = '#D27E99',
    springGreen = '#98BB6C',
    autumnYellow = '#DCA561',
    oniViolet = '#957FB8',
    autumnGreen = '#76946A',
    autumnRed = '#C34043',
    waveBlue2 = '#2D4F67',
}

-- where a popup can sit on screen. Written out as a type as well as a list
-- because the list is what checkOneOf compares against at runtime, and the
-- type is what offers the nine names to anyone writing them in their config.
-- Annotating the list with the type is what keeps the two in step: adding a
-- name to one without the other is a mismatch lua-language-server reports
---@alias cash.Position
---| 'top-left'
---| 'top'
---| 'top-right'
---| 'left'
---| 'center'
---| 'right'
---| 'bottom-left'
---| 'bottom'
---| 'bottom-right'

-- the nine places a popup can sit on screen. Named rather than numbered: a
-- numpad digit would read well for the grid and badly at a call site, where 1
-- meaning bottom-left is a trap for anyone not picturing a numpad
---@type cash.Position[]
constants.positions = {
    'top-left',
    'top',
    'top-right',
    'left',
    'center',
    'right',
    'bottom-left',
    'bottom',
    'bottom-right',
}

---@alias cash.ChooserStyle 'grid' | 'strip' | 'none'

-- what the ? chooser can look like
---@type cash.ChooserStyle[]
constants.chooserStyles = { 'grid', 'strip', 'none' }

---@alias cash.IndicatorStyle 'current' | 'strip'

-- what the indicator can say. 'current' is the working cash register on its
-- own, 'strip' is all nine of them
---@type cash.IndicatorStyle[]
constants.indicatorStyles = { 'current', 'strip' }

---@alias cash.IndicatorDisplay 'number' | 'pattern' | 'number-and-pattern'

-- what the indicator puts inside its brackets. The number is the cash
-- register's, drawn the way indicator.style asks for; the pattern is what that
-- cash register holds
---@type cash.IndicatorDisplay[]
constants.indicatorDisplays = { 'number', 'pattern', 'number-and-pattern' }

-- one pair of brackets for the indicator to wear
---@class cash.Brackets
---@field left string
---@field right string

-- the bracket pairs the indicator can be asked for by name
---@alias cash.BracketStyle
---| 'ascii'
---| 'angle'
---| 'heavy-angle'
---| 'box-light'
---| 'box-heavy'
---| 'small-cap'
---| 'large-cap'
---| 'short-corner'
---| 'tall-corner'
---| 'double-square'
---| 'white-square'

-- The names, in the order a complaint should list them: the plainest pair
-- first, then each kind together with the lighter of the two in front.
--
-- Not alphabetical, because what is being chosen here is what the thing looks
-- like, and alphabetical order puts the light and the heavy version of one
-- pair at opposite ends of the list.
--
-- Written out as a list as well as an alias for the same reason the positions
-- are: the list is what checkOneOf compares against at runtime, the alias is
-- what offers the names to anyone writing them in their config, and
-- annotating the list with the alias is what keeps the two in step, since an
-- element the alias does not have is a mismatch lua-language-server reports
---@type cash.BracketStyle[]
constants.bracketStyles = {
    'ascii',
    'angle',
    'heavy-angle',
    'box-light',
    'box-heavy',
    'small-cap',
    'large-cap',
    'short-corner',
    'tall-corner',
    'double-square',
    'white-square',
}

-- What each of those names is made of.
--
-- Every pair in here is one cell on each side, which is the whole point of
-- having names at all: the fullwidth CJK brackets this option started with are
-- two cells each and missing from most programming fonts, so a named pair is
-- one that can be relied on to draw. Anything else is still available by
-- writing the two strings out.
--
-- The four made of box drawing and block characters are East Asian Ambiguous,
-- so they take two cells each under ambiwidth=double rather than one. Nothing
-- here has to care: the indicator measures what it is about to draw rather
-- than counting on a width.
--
-- Nothing checks these keys against the list above -- a key type is one of the
-- few things lua-language-server does not compare against an alias -- so the
-- suite asks instead, by resolving every name in the list
---@type table<string, cash.Brackets>
constants.brackets = {
    ['ascii'] = { left = '[', right = ']' },
    ['angle'] = { left = '‹', right = '›' },
    ['heavy-angle'] = { left = '❰', right = '❱' },
    ['box-light'] = { left = '│', right = '│' },
    ['box-heavy'] = { left = '┃', right = '┃' },
    ['small-cap'] = { left = '▏', right = '▕' },
    ['large-cap'] = { left = '▌', right = '▐' },
    ['short-corner'] = { left = '⌜', right = '⌟' },
    ['tall-corner'] = { left = '｢', right = '｣' },
    ['double-square'] = { left = '⟬', right = '⟭' },
    ['white-square'] = { left = '⟦', right = '⟧' },
}

-- the pair the indicator wears when nothing else is asked for. Named here
-- rather than written into the defaults, so that the fallback in
-- resolveBrackets and the default itself cannot come apart
---@type cash.BracketStyle
constants.defaultBracketStyle = 'heavy-angle'

constants.invalidOptionMessage = 'is not a valid option for Cash.nvim'

return constants
