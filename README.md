# 💸 Cash.nvim

**CASH**: **C**hoose **A**vailable **S**earch **H**ighlights

## 💰 Overview

This plugin adds additional search registers to Neovim. Normally when you
perform a search in (Neo-)Vim, your previous search is overwritten. Cash.nvim
provides you with 9 "cash registers" (haha) that you can use to store multiple
searches at once. Highlighting and jump functionality is handled separately for
each cash register.

## 💳 TL;DR / Quick Start

Use <kbd>?</kbd>`<number>` (1-9) to select a cash register. This gives you 9
individual searches that can be highlighted simultaneously.

## 💲 How to Install

TODO

## 💶 Compatibility Issues / Warnings

Cash.nvim will overwrite the default behavior of the <kbd>?</kbd> key.

## 💵 How to Use

### Search Normally

With Cash.nvim, you can perform searches normally, and they will show up
normally. Start a search with <kbd>/</kbd>, <kbd>\*</kbd>, or <kbd>#</kbd> (but
not <kbd>?</kbd>) from normal mode, then use <kbd>n</kbd> and <kbd>N</kbd> to
navigate through the highlighted matches.

### Select Cash Register

By default, you will be using cash register 1. Every time you search, the
contents of cash register 1 will update to match your search terms. You will
jump between instances of the search term stored in cash register 1.

To switch to a different cash register, press <kbd>?</kbd> followed by a single
digit. This will change the working cash register to the specified number. For
example, use <kbd>?</kbd><kbd>2</kbd> to switch to cash register 2.

Once you change cash registers, the search highlighting of the old cash register
will remain on the screen. You can then perform a new search independent of the
previous one. Any search you perform will overwrite the contents of the working
cash register.

Jumping always jumps between occurrences that match the contents of the working
cash register, skipping over matches for other cash registers. If you want to
jump between matches for a different cash register other than the working one,
simply switch back to that cash register and start jumping.

### Clear Cash Registers

To clear the contents of the working cash register, use `:clc`. This will also
set Vim's search to an empty string.

To clear all cash registers and reset the plugin to its initial state, use the
`:ClearSearches` command. This will set Vim's search register to an empty string
and clear the contents of all cash registers.

## 💱 Customization

TODO

## 🤑 TODO List

-   Import the code.
-   Make the code actually work as a plugin.
-   Finish README.
-   Make current number and current color display next to clock.
-   Create better debug function other than current `<Leader>v`.
-   Debug case sensitivity and try to respect `smartcase` and `ignorecase`.
    Right now, searching for `asdf` in cash register 1 will match `Asdf`,
    `ASDF`, etc, but then switching to cash register 2 will make the
    `matchadd()` require an exact case match.
-   Add `?+` and `?-` (or `?n` and `?p`, or `?h` and `?l`, or `?j` and `?k`, or
    `?/` and `??`) mappings to move laterally between cash registers.
-   Add argument to `:ClearSearches` command to clear a given cash register.
-   Make `:clc` into a function to users can map it how they want.
-   Rename basically everything in the code and the commands.
-   Handle global `matchadd`. Everything is mega-broken when you try to use more
    than 1 window : (
-   Make sure `:ClearSearches` can finish executing even if it hits an error
    during `matchdelete`. It should be sure to clear the match ID array too.
-   Centering of the screen should be a configurable option, as should many
    other behaviors

## 🪙 Other Tips

TODO add tips here about my custom + mapping and my nzz mappings

💴💷🏦
