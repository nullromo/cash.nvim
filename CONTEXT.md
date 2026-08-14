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

One trap worth knowing: **`v:hlsearch` is saved and restored around autocmd
execution**. Assigning it from inside a callback holds for the rest of that
callback and is then thrown away — long enough to add matches, which then sit
on screen looking correct, until the next update finds it back at 0 and takes
them all away. Anything turning highlighting on goes through
`cash.showHighlighting`, which assigns it once for the caller's benefit and
again from a `vim.schedule`, where it sticks. `autoNoHighlight` turns it off
the same way, from a schedule.

It works out what should be on screen, compares it against the ledger, and
fixes the difference. It is idempotent: calling it twice does nothing the
second time, so callers never have to know whether something has already been
updated. Anything that can invalidate the highlights just calls it.

In code: `highlights.update(cashRegisters, currentIndex)`, wrapped as
`CashModule.updateHighlights()`.

## The drawer

The popup `:Cash` opens. In code: `lua/cash/ui.lua`.

> The drawer's buffer holds nothing but the nine search patterns, one per line.

Everything else on screen is an extmark: the marker, the register number, the
include dot and the match count are inline `virt_text`; the legend, the rules,
the search set line and the key hints are `virt_lines` below cash register 9.
The column headings are a **winbar**, not a virtual line — virtual lines above
the first line of a buffer are never drawn, and a winbar belongs to the window
rather than the buffer, so the cursor cannot reach it either.

This is what makes editing safe: there is no chrome for an edit to damage,
because the chrome is not text. <kbd>G</kbd> lands on cash register 9 rather
than on a key hint, and no motion needs a special case.

While the drawer is open, **the buffer is the truth**. A `TextChanged` autocmd
reads the nine lines back into the cash registers on every keystroke and
updates the highlights, so the buffers behind the drawer follow along as a
pattern is typed. Closing with <kbd>q</kbd> only has the search register left
to put in step; <kbd>Ctrl-c</kbd> puts back a snapshot taken when the drawer
opened.

Things the drawer has to do that are easy to get wrong:

- Its buffer is left out of `updateHighlights`. It holds the search patterns as
  literal text, so matching them there would paint the drawer in the very
  colors it is explaining. The mark is on the **buffer**, and the window is
  opened with `noautocmd`, because `nvim_open_win` fires `WinNew` while the new
  window is still showing the buffer the user came from.
- Match counts are worked out with `nvim_win_call` against the window the user
  came from. Run in the drawer, `searchcount()` would count matches in the list
  of patterns rather than in their buffer. The same goes for selecting a cash
  register, which searches for its pattern: run with the drawer focused, that
  jump lands in the list of patterns.
- Writes the plugin makes itself — opening, swapping, repairing the row count —
  are made with `undolevels` dropped, so they never enter the undo history.
  <kbd>u</kbd> should undo what the user typed and nothing else. Without it,
  <kbd>u</kbd> can restore the empty buffer the drawer started as, which the
  row-count guard then reads back as nine empty cash registers.

## The detail pane

What <kbd>?</kbd> opens beside the drawer, in `ui.openPane`. Everything in it
is about one cash register and does not fit on its row: the **match pattern**
Vim is really given, whether it is included and whether it is selected, and the
ledger entries for it — which windows are carrying a match.

It labels the match pattern **match pattern**, exactly as it is named below.
Its one departure is **contents** for the search pattern as typed, which is the
word the drawer's own column heading already uses for it.

It sits **beside** the drawer rather than under it because the drawer is
already 23 rows tall, which is most of a small terminal. Height is the scarce
direction; width is not. The cost is that the two together need 102 columns, and
below that `openPane` says so rather than drawing something clipped.

The selected cash register has no match of its own — it is drawn by Vim's
`hlsearch` — so its **matching window IDs** cannot come from the ledger. The **selected** line
is what accounts for that, rather than a sentence explaining it.

With the pane open the drawer and the pane are placed as one block, so that
`ui.position` still positions what the user is looking at rather than
positioning the drawer and letting the pane hang off the side.

## The chooser

The popup <kbd>?</kbd> brings up, in `ui.openChooser`. A different tool from
the drawer, and deliberately so: it appears, you press a digit, it is gone.

Its whole job is to answer _which number is the green one_ on screen rather
than from memory. That is why an empty cash register still shows its number,
in its own color — knowing which colors are free is part of the answer.

`ui.openChooser` draws it and hands back the window; `ui.chooseRegister` is
what waits for the keypress. They are separate because `getchar()` blocks the
event loop, so anything that wants to look at what was drawn — a test, a
screenshot — cannot also be the thing that dismisses it.

Both the chooser and the drawer are placed by `placement`, which takes one of
the nine names in `constants.positions` and turns it into a row and column. The
command line and the status line are not free to be covered, so neither counts
as space to place into.

## Highlight group

The Vim highlight group carrying a cash register's colors, named
`CashRegister1` through `CashRegister9`. Created once during setup.
