local constants = {}

-- color constants taken from kanagawa.nvim
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

-- the nine places a popup can sit on screen. Named rather than numbered: a
-- numpad digit would read well for the grid and badly at a call site, where 1
-- meaning bottom-left is a trap for anyone not picturing a numpad
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

-- what the ? chooser can look like
constants.promptStyles = { 'grid', 'strip', 'none' }

constants.invalidOptionMessage = 'is not a valid option for Cash.nvim'

return constants
