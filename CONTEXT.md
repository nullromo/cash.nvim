<!-- For AI agents -->

# Domain language

The words Cash.nvim's code, docs, and design discussions should use. If a term
here has a name in the code, that name is the one to use.

## Cash register

One of the 9 slots that hold a search pattern. Numbered 1–9; there are never
more or fewer. In code: `state.cashRegisters`, indexed 1–9.

A cash register index is always a whole number from 1 to 9. Nothing else is a
cash register, and `setCashRegister` rejects anything else rather than trusting
its caller.

## Working cash register

The cash register the user is currently searching in. Searching overwrites its
pattern; <kbd>n</kbd>/<kbd>N</kbd> jump between its matches. In code:
`state.currentIndex`.

The working cash register is **not** highlighted by a match. It is highlighted
by Vim's own `Search` highlight, which is recolored to that register's color.
This is deliberate: it keeps `hlsearch` and `:nohlsearch` behaving normally for
the register the user is actually working in.

## Search pattern

The string a cash register holds, exactly as the user typed it — before any
case flag is applied. An empty pattern means the register highlights nothing.

## Match pattern

What Vim is actually asked to match: the search pattern with a case flag
resolved onto the front of it. An explicit `\c` or `\C` in the search pattern
wins and makes `ignorecase` irrelevant to that register; otherwise the current
value of `ignorecase` decides the flag.

Match patterns are what the ledger stores, because two search patterns that are
textually identical can need different highlights, and comparing the resolved
form catches that.

## Ledger

The record of which matches this plugin has added to which windows:
`ledger[windowID][index] = { id, matchPattern }`. Private to the highlights
module.

An index with **no entry** has no match. That is the only way absence is
spelled — there are no sentinel values, and no entry ever means "we tried and
failed".

The ledger records what the plugin *did*. It is never the source of truth for
which windows exist — that question is always put to Vim.

## updateHighlights

The one operation that makes this true, in every window:

> Window _W_ has a highlight for cash register _i_ exactly when _i_ is not the
> working cash register and cash register _i_'s pattern is not empty.

It works out what should be on screen, compares it against the ledger, and
fixes the difference. It is idempotent: calling it twice does nothing the
second time, so callers never have to know whether something has already been
updated. Anything that can invalidate the highlights just calls it.

In code: `highlights.update(cashRegisters, currentIndex)`, wrapped as
`CashModule.updateHighlights()`.

## Highlight group

The Vim highlight group carrying a cash register's colors, named
`CashRegister1` through `CashRegister9`. Created once during setup.
