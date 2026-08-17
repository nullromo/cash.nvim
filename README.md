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

Everything below is also available inside Neovim as [vimdoc](./doc/cash.txt):
`:help cash.nvim`.

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

By default, pressing <kbd>?</kbd> brings up a chooser showing all nine cash
registers in their own colors, so you can see which number is the one you want.

```
╭─ Choose a cash register ───────────────╮
│  ▸ 1  foo      2  bar      3  \<baz\>  │
│    4  ·        5  ·        6  ·        │
│    7  ·        8  ·        9  TODO     │
╰────────────────────────────────────────╯
```

The look of the chooser can be customized via the `chooser.style` option.

Once you change cash registers, the search highlighting of the old cash register
will remain on the screen. You can then perform a new search independent of the
previous one. Any search you perform will always overwrite the contents of the
working cash register.

Jumping normally jumps between occurrences that match the contents of the
working cash register, skipping over matches for other cash registers. If you
want to jump between matches for a different cash register other than the
working one, either switch back to that cash register and start jumping, or use
the `includeInSearch` option.

### Include in Search

By default, <kbd>n</kbd> and <kbd>N</kbd> jump between the matches of the
working cash register only. Switching `includeInSearch` on for another cash
register causes jumps to match the contents of that cash register as well.
<kbd>n</kbd> visits whichever match comes next from among the search patterns in
all cash registers that have `includeInSearch` enabled.

```lua
require('cash').setIncludeInSearch(2, true) -- include register 2 matches when pressing n/N
require('cash').toggleIncludeInSearch(2)    -- toggle whether or not to include register 2
```

For example, say cash register 1 holds `foo` and cash register 2 holds `bar`. If
both registers 1 and 2 have `includeInSearch` = `true`, then <kbd>n</kbd> walks
through every `foo` and every `bar` in whatever order they appear. They keep
their own colors while it happens. Including a cash register changes where
<kbd>n</kbd>/<kbd>N</kbd> go, not what is highlighted.

The working cash register is always included, no matter what its own
`includeInSearch` setting says.

Each cash register keeps its own case sensitivity. If one register holds `\Cfoo`
and another holds `bar`, the first stays case-sensitive and the second still
follows `ignorecase`.

### The Cash Drawer (cha-ching!)

`:Cash` opens a popup showing all nine cash registers at once: their contents,
their colors, which ones <kbd>n</kbd>/<kbd>N</kbd> will visit, and how many
matches each one has in the buffer you came from.

Other possible actions from the drawer are listed in the table below.

| Key                           | Does                                                                                                                                        |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| <kbd>j</kbd> / <kbd>k</kbd>   | Move between cash registers.                                                                                                                |
| any edit                      | Edit the cash register under the cursor. Edits here work like any regular buffer.                                                           |
| <kbd>d</kbd><kbd>d</kbd>      | Empty the highlighted cash register. It clears the row rather than removing it, because there are always nine registers.                    |
| <kbd>Space</kbd>              | Toggle `includeInSearch` for the cash register under the cursor.                                                                            |
| <kbd>Enter</kbd>              | Select the highlighted cash register and close.                                                                                             |
| <kbd>Tab</kbd>                | Select the highlighted cash register and stay open.                                                                                         |
| <kbd>]</kbd> / <kbd>[</kbd>   | Swap the highlighted cash register with the one below / above. Contents move, but colors stay put, so this is one way to re-color a search. |
| <kbd>q</kbd> / <kbd>Esc</kbd> | Apply and close the drawer.                                                                                                                 |
| <kbd>?</kbd>                  | Show or hide the detail pane (shows more information about the highlighted cash register).                                                  |
| <kbd>Ctrl-c</kbd>             | Close the drawer and undo everything changed since it was opened.                                                                           |

#### The Detail Pane

The detail pane can be opened from the drawer by pressing <kbd>?</kbd>. It
provides more details about the highlighted cash register.

```
╭─ Details ────────────────────────────╮
│  cash register 3                     │
│                                      │
│  contents          \<baz\>           │
│  match pattern     \C\<baz\>         │
│  include in search no                │
│  selected          no                │
│                                      │
│  matching window IDs 1000  1001      │
╰──────────────────────────────────────╯
```

- `contents` is the contents of the cash register.
- `match pattern` is what Vim actually matches on, with the case flag inserted
  on the left.
- `include in search` answers whether <kbd>n</kbd> and <kbd>N</kbd> will visit
  this cash register. It always reads `yes` for the selected register .
- `matching window IDs` lists the windows in which that cash register's pattern
  actually occurs.

Set `drawer.detailPane = true` to have the detail pane always appear with the
drawer.

_Note: The detail pane appears next to the drawer, so it needs a window at least
102 columns wide in order to open._

### Command

Cash.nvim takes a single user command, with verbs.

| Command                            | Does                                                                                                 |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `:Cash`                            | Open the cash drawer.                                                                                |
| `:Cash use {n}`                    | Select cash register _n_, the same as <kbd>?</kbd>_n_.                                               |
| `:Cash include {n}`                | Add cash register _n_ to the search set (`includeInSearch` = `true`).                                |
| `:Cash exclude {n}`                | Remove cash register _n_ from the search set. (`includeInSearch` = `false`).                         |
| `:Cash toggle {n}`                 | Toggle whether or not cash register _n_ is included in the search set.                               |
| `:Cash clear [{n}]`                | Empty cash register _n_, or the current working cash register if the _n_ arg is omitted.             |
| `:Cash reset`                      | Empty all nine cash registers and select cash register 1.                                            |
| `:Cash hide`                       | Hide all search highlights. The same as `:nohlsearch` (`:noh`). The registers keep their contents.   |
| `:Cash show`                       | Bring search highlights back. They will also come back when using `n`/`N`.                           |
| `:Cash autohide [on\|off\|toggle]` | Change whether search highlights clear as soon as the cursor moves. Toggles if no argument is given. |

### Case Sensitivity

Cash.nvim will respect the `ignorecase` option, but the case sensitivity can be
overridden in the search pattern as normal using `\c` or `\C` (see `:help /\c`).

### Clear Cash Registers

To clear the contents of the working cash register, use `:Cash clear` (or the
`require('cash').clearCashRegister()` function). This will also set Vim's search
to an empty string. Pass a number, as in `:Cash clear 3`, to empty a different
cash register instead.

To clear all cash registers and reset the plugin to its initial state, use
`:Cash reset` (or the `require('cash').resetCashRegisters()` function). This
will set Vim's search register to an empty string and clear the contents of all
cash registers.

### Persistence

Vim remembers your last search pattern from one session to the next, in the
[shada](https://neovim.io/doc/user/starting.html#shada) file. Similarly,
Cash.nvim remembers all nine cash registers. If you quit and start Neovim again,
all your cash registers will come back the way you left them.

Nothing is highlighted straight away. A restored cash register lights up when
your next search or your next <kbd>n</kbd> turns highlighting on, and not
before. This is exactly what Vim already does with the search pattern it
restores.

A few things worth knowing:

- The plugin state is written on the way out, so a clean exit of Neovim keeps
  them and a crash does not. This is the same thing Vim does for `@/` and your
  search history.
- There is one global copy of the plugin state shared by every instance of
  Neovim on the machine. Starting Neovim in another project gives you the cash
  registers you last quit with.

Set `persistCashRegisters = false` to start every session with nine empty cash
registers instead.

## 💶 Compatibility Issues / Warnings

Cash.nvim will overwrite the default behavior of the <kbd>?</kbd> key.

Cash.nvim also maps <kbd>n</kbd> and <kbd>N</kbd> in normal mode, so that they
can jump between the matches of more than one cash register (see
[Include in Search](#include-in-search)). Whenever the search set is a single
cash register, <kbd>n</kbd> and <kbd>N</kbd> use their native (Neo-)Vim
functions. Set `manageJumps = false` to make `includeInSearch` a no-op and leave
the <kbd>n</kbd> and <kbd>N</kbd> keys alone entirely.

If you map <kbd>n</kbd> yourself (`vim.keymap.set('n', 'n', 'nzz')` is a common
one), your mapping replaces Cash.nvim's and include-in-search will silently stop
working. Map `require('cash').nextMatch` / `require('cash').previousMatch` if
you want to maintain Cash.nvim's intended behavior. If centering is all you
need, the `centerAfterSearch` option already does that for you.

## 💱 Customization

### Default Options

```lua
{
    -- clear all highlighting as soon as the cursor moves
    autoNoHighlight = false,
    -- center the window after every search jump: /, *, #, n, N, and switching
    -- to another cash register
    centerAfterSearch = true,
    -- customize the cash register chooser that ? opens
    chooser = {
        -- 'grid', 'strip' or 'none'
        style = 'grid',
        -- where on screen the chooser appears ('center', 'bottom-right',
        -- 'bottom', 'bottom-left', 'left', 'top-left', 'top', 'top-right', or
        -- 'right')
        position = 'center',
        -- the chooser's border, in any form nvim_open_win accepts
        border = 'rounded',
    },
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
    -- the cash drawer, which :Cash opens
    drawer = {
        -- where on screen the drawer appears ('center', 'bottom-right',
        -- 'bottom', 'bottom-left', 'left', 'top-left', 'top', 'top-right', or
        -- 'right')
        position = 'center',
        -- the drawer's border, in any form nvim_open_win accepts
        border = 'rounded',
        -- whether the detail pane is already open when the drawer appears
        detailPane = false,
    },
    -- let this plugin own n and N, so that they can jump between the matches
    -- of every cash register in the search set
    manageJumps = true,
    -- carry the cash registers from one Neovim to the next in the shada file,
    -- the way Vim already remembers your last search
    persistCashRegisters = true,
    -- leave vim's hlsearch setting alone. This plugin overrides hlsearch by
    -- default
    respectHLSearch = false,
}
```

### Options Table

| Option                                    | Data Type                                      | Default     | Description                                                                                                                                                                                                                                                                                                                                                                                                    |
| ----------------------------------------- | ---------------------------------------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `centerAfterSearch`                       | boolean                                        | `true`      | Each time you arrive at a match, Cash.nvim will center the current window on it for you. This covers <kbd>/</kbd>, <kbd>\*</kbd>, <kbd>#</kbd>, switching cash registers, <kbd>n</kbd>, and <kbd>N</kbd>. A search that finds nothing leaves the window alone.<br />If you don't like this behavior, you can disable it by setting this option to `false`.                                                     |
| `colors.defaultBG` and `colors.defaultFG` | string (`'#RRGGBB'`)                           | see above   | These will be the highlight background and foreground, respectively, for highlight colors that do not have a `bg` or `fg` color specified, respectively.                                                                                                                                                                                                                                                       |
| `colors.highlightColors`                  | list of 9 `{ bg = string, fg = string }` items | see above   | This is a table of 9 values, each with a `bg` and `fg` field. These define the highlight colors for each of the 9 available cash registers. If a `bg` or `fg` value is not specified in one of these entries, then the `colors.defaultBG`/`colors.defaultFG` color will be used. Colors should be of the form `'#RRGGBB'`.                                                                                     |
| `disableStarPoundJump`                    | boolean                                        | `true`      | By default, Vim will jump you to the next occurrence of a search term if you initiate the search using <kbd>\*</kbd> or <kbd>#</kbd>. Cash.nvim disables this by default. You can preserve Vim's default behavior by setting this option to `false`.                                                                                                                                                           |
| `manageJumps`                             | boolean                                        | `true`      | Cash.nvim maps <kbd>n</kbd> and <kbd>N</kbd> so that they can jump between the matches of every cash register in the search set. With only one cash register in the search set, the mapping uses Vim's default behavior, so nothing changes until you turn `includeInSearch` on for more than one cash register. Set this to `false` to leave the keys alone, which also turns `includeInSearch` into a no-op. |
| `persistCashRegisters`                    | boolean                                        | `true`      | Carry the cash registers from one Neovim to the next in the [shada](#persistence) file, the way Vim already remembers your last search. All nine search patterns, their `includeInSearch` values, and the working cash register all come back. Set this to `false` to start every session with nine empty cash registers.                                                                                      |
| `respectHLSearch`                         | boolean                                        | `false`     | In order to enable search highlighting for the current search, you need to enable the `hlsearch` Vim option. Cash.nvim does this automatically, but if you want your `hlsearch` setting to be left as-is, then you can set this option to `true`.                                                                                                                                                              |
| `autoNoHighlight`                         | boolean                                        | `false`     | Clear every cash register's highlighting as soon as the cursor moves. The cursor movement made by the search itself does not count. Switchable with `:Cash autohide`.                                                                                                                                                                                                                                          |
| `chooser.style`                           | `'grid'`, `'strip'` or `'none'`                | `'grid'`    | What the <kbd>?</kbd> chooser looks like. `'grid'` lays the registers out like a numpad and shows what each one holds; `'strip'` is one line of numbers; `'none'` turns the chooser popup off.                                                                                                                                                                                                                 |
| `chooser.position` and `drawer.position`  | string                                         | `'center'`  | Where the chooser and the cash drawer appear: `'top-left'`, `'top'`, `'top-right'`, `'left'`, `'center'`, `'right'`, `'bottom-left'`, `'bottom'` or `'bottom-right'`.                                                                                                                                                                                                                                          |
| `drawer.detailPane`                       | boolean                                        | `false`     | Whether the drawer's detail pane is already open when it appears. Needs a window at least 102 columns wide to function.                                                                                                                                                                                                                                                                                        |
| `chooser.border` and `drawer.border`      | string or table                                | `'rounded'` | Popup border settings for the chooser and drawer, in any form `nvim_open_win` accepts.                                                                                                                                                                                                                                                                                                                         |

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

### Do something after each jump

Centering is built in—see the `centerAfterSearch` option. Anything else you want
to happen after each jump with <kbd>n</kbd>/<kbd>N</kbd> should wrap the API
functions, so that the search set is still taken into account. For example, here
is a mapping that puts the match at the top of the window instead of the middle.

```lua
local cash = require('cash')
vim.keymap.set('n', 'n', function()
    cash.nextMatch()
    vim.cmd('normal! zt')
end)
vim.keymap.set('n', 'N', function()
    cash.previousMatch()
    vim.cmd('normal! zt')
end)
```

Do not use the usual `vim.keymap.set('n', 'n', 'nzz')` for this. That mapping
calls Vim's built-in <kbd>n</kbd>, which knows nothing about the search set, so
<kbd>n</kbd> would only ever be able to visit the working cash register.

## 🏦 License, Contributing, etc.

See [LICENSE](./LICENSE) and [CONTRIBUTING.md](./CONTRIBUTING.md).

I am very open to feedback and criticism.

## 💷 Special Thanks

### Bronze Tier Sponsors

- 🥉 [collindutter](https://github.com/collindutter)
- 🥉
  [`<Your name here>`](https://github.com/nullromo/cash.nvim/blob/main/README.md#-donating)

## 🤑 Donating

To say thanks with some **_cash_**,
[sponsor me on GitHub](https://github.com/sponsors/nullromo) or use
[@Kyle-Kovacs on Venmo](https://venmo.com/u/Kyle-Kovacs). Your donation is
appreciated!
