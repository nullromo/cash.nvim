<!-- For AI agents -->

# Domain language

The words Cash.nvim's code, docs, and design discussions should use. If a term
here has a name in the code, that name is the one to use.

## Cash register

One of the 9 slots that hold a search pattern. Numbered 1–9; there are never
more or fewer. In code: `state.cashRegisters`, indexed 1–9.

A cash register is a record, not a bare string:

```lua
state.cashRegisters[3] = { pattern = 'baz', includeInSearch = false }
```

It is a record because `includeInSearch` belongs to the register and has to
survive everything that rewrites the pattern. Its **color** is deliberately not
in here: that belongs to the slot, and lives in
`opts.colors.highlightColors[i]`. Moving a pattern from one register to another
is therefore how you recolor a search.

A cash register index is always a whole number from 1 to 9. Nothing else is a
cash register, and anything taking an index rejects the rest rather than
trusting its caller. In code: `util.isCashRegisterIndex`.

## Working cash register

The cash register the user is currently searching in. Searching overwrites its
pattern; <kbd>n</kbd>/<kbd>N</kbd> jump between its matches. In code:
`state.currentIndex`.

The working cash register is **not** highlighted by a match. It is highlighted
by Vim's own `Search` highlight, which is recolored to that register's color.
This is deliberate: it keeps `hlsearch` and `:nohlsearch` behaving normally for
the register the user is actually working in.

## Search set

The cash registers whose matches <kbd>n</kbd> and <kbd>N</kbd> move between.
In code: `jump.searchSet`.

> The search set is the working cash register, plus every cash register with
> `includeInSearch` switched on.

The working cash register is in it whatever its own switch says. Searching for
something and then not being able to jump to it is indefensible, so that switch
only starts to matter once the register stops being the working one.

The search set decides **where <kbd>n</kbd> goes and nothing else**. It has no
effect on what is highlighted — an included cash register and an excluded one
look exactly alike out in the buffer.

The patterns in the search set are never joined into one pattern with `\|`.
Two separate reasons, either one sufficient:

- `@/` drives `hlsearch`, so a union pattern would paint every register in the
  set the same color.
- `\c` and `\C` apply to a whole pattern wherever they are written, group or
  no group. One register with an explicit `\C` would decide the case
  sensitivity of all of them.

So each register is asked separately where its next match is, with
`searchpos()`, and the closest answer wins. When the search set comes down to
the working cash register on its own — which is every search that never touches
`includeInSearch` — the mapping hands straight back to Vim, and counts, search
offsets, folds, the wrap message and the jumplist all come from Vim itself.

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

> Window _W_ has a highlight for cash register _i_ exactly when `v:hlsearch` is
> on, _i_ is not the working cash register, and cash register _i_'s pattern is
> not empty.

The `v:hlsearch` clause is what makes `:nohlsearch` mean all nine. Vim only
ever applied it to the working cash register, since the other eight are matches
rather than `hlsearch`; following the same flag puts them back under the one
switch the user already reaches for. Nothing announces a change to
`v:hlsearch`, so a `SafeState` autocmd compares it against the last value that
was acted on. There is no separate "hidden" state — `v:hlsearch` **is** the
state, which is why turning the highlights back on is not a thing anything has
to remember to do: searching does it.

It works out what should be on screen, compares it against the ledger, and
fixes the difference. It is idempotent: calling it twice does nothing the
second time, so callers never have to know whether something has already been
updated. Anything that can invalidate the highlights just calls it.

In code: `highlights.update(cashRegisters, currentIndex)`, wrapped as
`CashModule.updateHighlights()`.

## Highlight group

The Vim highlight group carrying a cash register's colors, named
`CashRegister1` through `CashRegister9`. Created once during setup.
