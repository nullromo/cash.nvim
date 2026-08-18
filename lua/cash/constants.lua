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

constants.invalidOptionMessage = 'is not a valid option for Cash.nvim'

return constants
