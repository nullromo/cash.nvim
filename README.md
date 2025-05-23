# 💸 Cash.nvim

**CASH**: **C**hoose from **A**vailable **S**earch **H**ighlights

## 💰 Overview

This plugin adds additional search registers to Neovim. Normally when you
perform a search in (Neo-)Vim, your previous search is overwritten. Cash.nvim
provides you with 9 "cash registers" (haha) that you can use to store multiple
searches at once. Highlighting and jump functionality is handled separately for
each cash register.

## 💳 TL;DR / Quick Start

Use <kbd>?</kbd>`<number>` (1-9) to select a cash register. This gives you 9
individual searches that can be highlighted simultaneously.

## 🪙 Video Demo

https://github.com/nullromo/cash.nvim/assets/8991581/5c29fb81-a3e8-4de2-8c15-9acf62d2a99d

## 💵 How to Install

Lazy.nvim config:

```lua
{
    'nullromo/cash.nvim',
    opts = {}, -- specify options here
    config = function(_, opts)
        local cash = require('cash')
        cash.setup(opts)
    end,
}
```

## 💶 Compatibility Issues / Warnings

Cash.nvim will overwrite the default behavior of the <kbd>?</kbd> key.

## 💲 How to Use

### Search Normally

With Cash.nvim, you can perform searches normally, and they will show up
normally. Start a search with <kbd>/</kbd>, <kbd>\*</kbd>, or <kbd>#</kbd> (but
not <kbd>?</kbd>; see below) from normal mode, then use <kbd>n</kbd> and
<kbd>N</kbd> to navigate through the highlighted matches.

### Select Cash Register

By default, your working cash register is cash register 1. Every time you
search, the contents of cash register 1 will update to match your search terms.
You will jump between instances of the search term stored in cash register 1.

To switch to a different cash register, press <kbd>?</kbd> followed by a single
digit. This will change the working cash register to the specified number. For
example, use <kbd>?</kbd><kbd>2</kbd> to switch to cash register 2.

Once you change cash registers, the search highlighting of the old cash register
will remain on the screen. You can then perform a new search independent of the
previous one. Any search you perform will always overwrite the contents of the
working cash register.

Jumping always jumps between occurrences that match the contents of the working
cash register, skipping over matches for other cash registers. If you want to
jump between matches for a different cash register other than the working one,
simply switch back to that cash register and start jumping.

### Clear Cash Registers

To clear the contents of the working cash register, use `:clc`. This will also
set Vim's search to an empty string.

To clear all cash registers and reset the plugin to its initial state, use the
`:ResetCashRegisters` user command (or the
`require('cash').resetCashRegisters()` function). This will set Vim's search
register to an empty string and clear the contents of all cash registers.

### Case Sensitivity

Cash.nvim will respect the `ignorecase` option, but the case sensitivity can be
overridden in the search pattern as normal using `\c` or `\C` (see `:help /\c`).

_Note: changing the value of the `ignorecase` option will not update the
highlighting for non-active cash registers. See
[#4](https://github.com/nullromo/cash.nvim/issues/4#issuecomment-1988941540) for
details_

## 💱 Customization

### Default Options

```lua
{
    -- center the screen after each search
    centerAfterSearch = true,
    -- color settings
    colors = {
        -- default colors for foreground and background (used for highlight
        -- groups where fg/bg are not specified)
        defaultBG = constants.colors.roninYellow,
        defaultFG = constants.colors.sumiInk0,
        -- define colors for highlight groups 1-9
        highlightColors = {
            { bg = constants.colors.roninYellow },
            { bg = constants.colors.springBlue },
            { bg = constants.colors.sakuraPink },
            { bg = constants.colors.springGreen },
            { bg = constants.colors.autumnYellow },
            { bg = constants.colors.oniViolet },
            { bg = constants.colors.autumnGreen },
            { bg = constants.colors.autumnRed },
            { bg = constants.colors.waveBlue2, fg = constants.colors.fujiWhite },
        },
    },
    -- control whether or not using * or # from normal mode will jump to the
    -- next occurrence. Vim will jump by default; this plugin disables the jump
    -- by default
    disableStarPoundJump = true,
    -- leave vim's hlsearch setting alone. This plugin overrides hlsearch by
    -- default
    respectHLSearch = false,
}
```

### Options Table

| Option                                    | Data Type                                      | Default   | Description                                                                                                                                                                                                                                                                                                                |
| ----------------------------------------- | ---------------------------------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `centerAfterSearch`                       | boolean                                        | `true`    | Each time you perform a search, Cash.nvim will center the current window for you.<br />If you don't like this behavior, you can disable it by setting this option to `false`.                                                                                                                                              |
| `colors.defaultBG` and `colors.defaultFG` | string (`'#RRGGBB'`)                           | see above | These will be the highlight background and foreground, respectively, for highlight colors that do not have a `bg` or `fg` color specified, respectively.                                                                                                                                                                   |
| `colors.highlightColors`                  | list of 9 `{ bg = string, fg = string }` items | see above | This is a table of 9 values, each with a `bg` and `fg` field. These define the highlight colors for each of the 9 available cash registers. If a `bg` or `fg` value is not specified in one of these entries, then the `colors.defaultBG`/`colors.defaultFG` color will be used. Colors should be of the form `'#RRGGBB'`. |
| `disableStarPoundJump`                    | boolean                                        | `true`    | By default, Vim will jump you to the next occurrence of a search term if you initiate the search using <kbd>\*</kbd> or <kbd>#</kbd>. Cash.nvim disables this by default. You can preserve Vim's default behavior by setting this option to `false`.                                                                       |
| `respectHLSearch`                         | boolean                                        | `false`   | In order to enable search highlighting for the current search, you need to enable the `hlsearch` Vim option. Cash.nvim does this automatically, but if you want your `hlsearch` setting to be left as-is, then you can set this option to `true`.                                                                          |

## 💴 Other Tips

Here are some other searching tips that are not part of Cash.nvim's
functionality, but might be useful.

### Add a search term to the current search

When searching in Vim, `\|` is the "or" operator, meaning the pattern `foo\|bar`
will match occurrences of `foo` and occurrences of `bar`. This mapping allows
you to search for something, then press <kbd>+</kbd> to start searching for
something else in addition. It works by starting a new search that begins with
the contents of the old search register plus a `\|` at the end.

```lua
vim.keymap.set('n', '+', '/<C-r>/\\|')
```

By default, the <kbd>+</kbd> key in Vim just moves the cursor down 1 line. It is
very similar to <kbd>j</kbd>, so it's not that useful. For this reason,
<kbd>+</kbd> is a good candidate for remapping.

### Center the screen after jumping to a match

This mapping centers the screen after each jump with <kbd>n</kbd>/<kbd>N</kbd>.

```lua
vim.keymap.set('n', 'n', 'nzz')
vim.keymap.set('n', 'N', 'Nzz')
```

This can provide a more consistent experience when paired with Cash.nvim's
`centerAfterSearch` option.

## 🏦 License, Contributing, etc.

See [LICENSE](./LICENSE) and [CONTRIBUTING.md](./CONTRIBUTING.md).

I am very open to feedback and criticism.

## 💷 Special Thanks

### Bronze Tier Sponsors

-   🥉 [collindutter](https://github.com/collindutter)
-   🥉
    [`<Your name here>`](https://github.com/nullromo/cash.nvim/blob/main/README.md#-donating)

## 🤑 Donating

To say thanks with some **_cash_**,
[sponsor me on GitHub](https://github.com/sponsors/nullromo) or use
[@Kyle-Kovacs on Venmo](https://venmo.com/u/Kyle-Kovacs). Your donation is
appreciated!
