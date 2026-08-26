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

## Persistence

Carrying the cash registers from one Neovim to the next, in `lua/cash/persist.lua`.

> The nine patterns, their `includeInSearch` switches and the working cash
> register go into `g:CASH_NVIM`, and shada does the rest.

Shada carries a global variable only when its name is written in capitals with
no lowercase letter in it — that is what the `!` flag in `'shada'` selects, and
`!` is in Neovim's default. Everything else about the design falls out of two
facts about **when** shada happens, both of which have been checked rather than
assumed:

- **The shada file is read after `init.lua` has run**, and that read overwrites
  whatever the variable held. So `setup` cannot restore anything: at setup time
  the value is either missing or about to be replaced. `VimEnter` is the first
  moment it is really there. Setup can also run *after* `VimEnter`, under a
  plugin manager that loads this plugin on an event, so which of the two is
  used is decided by asking `v:vim_did_enter` rather than by assuming.
- **Shada collects the globals it is going to write before `VimLeave` runs.** A
  value set from `VimLeave` is dropped without a word, which looks exactly like
  the feature not existing. `VimLeavePre` is the last moment that works.

Saving only on the way out is deliberate, not a limitation left in by accident:
it is the same promise vim makes for `@/` and the search history, so a clean
quit keeps them and a crash does not.

Because those two moments are different moments, **a save must never outrun the
restore.** A Neovim that quits during startup never reaches `VimEnter`, so it
never reads the drawer — but it does reach `VimLeavePre`, and it would happily
write its own empty one over the drawer the user left behind. This is not a rare
shape: `nvim --headless "+Lazy! sync" +qa` is exactly it, and so is every other
scripted Neovim that loads the user's config and exits before startup finishes.
`CashModule.restoreHasRun` is what stops it, and it is never cleared once set —
not even by `initializeData`, so that emptying the drawer with `:Cash reset` and
quitting still saves the empty drawer the user asked for.

Two things about the restore are easy to get wrong:

- **`initializeData` clears the search register**, because a fresh set of cash
  registers is empty and the search register mirrors the working one. That
  destroys the evidence the restore reads, which is why the value is recorded
  in `searchRegisterBeforeSetup` first. It only bites on the after-`VimEnter`
  path, where shada has already put the search register back and setup is about
  to write over it — and there it is not subtle, it empties the working cash
  register on every startup.
- **A search made during startup has to win.** `nvim +/pattern` and `nvim -c
  /pattern` both run after the shada read and before `VimEnter`, and both have
  already moved the cursor. Putting the stored pattern back over that would
  leave the cursor on one match while vim highlighted another. Telling that
  case apart from an ordinary restore is the entire reason the search register
  is stored alongside the cash registers: shada puts `@/` back as it was, so a
  difference means something set it in between. The stored value is compared
  against, never installed.

  That test only holds while the stored search register is not empty.
  **Shada does not record an empty search pattern** — it leaves the last
  non-empty one sitting in the file — so a session that ended with nothing
  being searched for, which is exactly what `:Cash reset` and `:Cash clear`
  leave behind, is met on the way back by a stale pattern from some earlier
  session. A difference proves nothing there. Read as a startup search, it puts
  that stale pattern straight into the cash register the user had just emptied,
  and `:Cash reset` stops surviving a restart. So the stored cash registers win
  the ambiguous case and the stale pattern goes.

  The cost is the one case both rules cannot have: `nvim +/pattern` in the
  session after a `:Cash reset` loses its search, because there is no way to
  tell it from the stale pattern. It is preferred over the alternative, which
  is leaving `@/` holding something no cash register knows about — the drawer
  would then be lying about what is on screen, and that invariant is worth more
  than an uncommon startup search that one keypress brings back.

Nothing here touches `v:hlsearch`, so a restored cash register lights up when
the next search or `n` turns highlighting on, and not before. That is what vim
does with the pattern it restores, and it is a consequence of `updateHighlights`
following `v:hlsearch` rather than a case anyone handled.

Everything read back out is checked. The shada file outlives any one version of
this plugin, it can be hand-edited, and `g:CASH_NVIM` is a name anything can
write to, so `persist.deserialize` returns nil for a shape it does not
recognise — including a `version` from a newer Cash.nvim, which is refused
rather than guessed at — and one malformed cash register becomes an empty one
rather than taking the other eight with it.

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
`drawer.position` still positions what the user is looking at rather than
positioning the drawer and letting the pane hang off the side.

## The chooser

The popup <kbd>?</kbd> brings up, in `ui.openChooser`. A different tool from
the drawer, and deliberately so: it appears, you press a digit, it is gone.

Its whole job is to answer _which number is the green one_ on screen rather
than from memory. That is why an empty cash register still shows its number,
in its own color — knowing which colors are free is part of the answer.

The cash register a second <kbd>?</kbd> would switch to is marked with a `?`
after its number. It takes the space the number already had after it, so a
marked cell is the same width as an unmarked one and nothing shifts. Working
the answer out belongs to `chooserRows` rather than to `ui.openChooser`,
because it is a question about where the cursor is and that has to be asked
while the user's own window is still the current one.

`ui.openChooser` draws it and hands back the window; `ui.chooseRegister` is
what waits for the keypress. They are separate because `getchar()` blocks the
event loop, so anything that wants to look at what was drawn — a test, a
screenshot — cannot also be the thing that dismisses it.

Both the chooser and the drawer are placed by `placement`, which takes one of
the nine names in `constants.positions` and turns it into a row and column. The
command line and the status line are not free to be covered, so neither counts
as space to place into.

## The picker

What `:Telescope cash_registers` opens, in `lua/cash/picker.lua` and
`lua/telescope/_extensions/cash_registers.lua`.

> The picker lists the nine cash registers, filters them by what they hold, and
> switches to the one that is chosen. That is all it does.

It answers a question the chooser cannot: which cash register holds the
pattern I am after, when there are more of them than fit in my head. Everything
else about a cash register still belongs to the drawer.

Telescope is optional, and nothing in the extension is loaded until the
extension is asked for. Telescope finds the file by looking under
`lua/telescope/_extensions/` for an extension of that name, which means
cash.nvim has to be on the runtimepath before the command works at all. A
lazy-loaded cash.nvim gives `:Telescope cash_registers` reporting an unknown
command, and so does any error raised while the extension is loading, because
telescope wraps that require in a `pcall`.

The split between the two files is the split between the two plugins.
`picker.rows` says what each row holds, `picker.select` is what choosing one
does, and `picker.excludeFromHighlighting` keeps telescope's windows out of the
highlighting. The extension is telescope plumbing and nothing else. The tests
stop at the same line, since the suite runs with no plugins installed.

Three of the picker's decisions are the drawer's decisions, made for the
drawer's reasons:

- **The match counts and the search are asked of the window the picker was
  opened from.** Asked of telescope's prompt, `searchcount` would count matches
  in the list of patterns, and selecting would jump about inside that list.
- **Every cash register gets a row**, empty ones included, because which colors
  are free is part of what the list answers. This is the chooser's reasoning.
- **Telescope's own windows are kept out of the highlighting.** They hold the
  patterns as literal text.

Keeping them out is not the same job as keeping the drawer out. The drawer marks
its buffer before its window exists. Telescope's windows are open and already
carrying matches by the time the extension can name them, so the mark goes on,
the matches that arrived with the window are cleared by hand, and the update
that follows drops the window from the ledger rather than deleting anything
through it. The borders are windows of their own and get the same treatment,
since a pattern like `.` matches what is in them too.

## The indicator

The always-on answer to which cash register is the working one, in
`lua/cash/indicator.lua`. Issue #2.

> The label is the answer as data. Everything that gets drawn is built from it,
> and so is anything a user builds for a statusline of their own.

The chooser answers the same question when it is asked. This answers it
continuously, which is a different job and a different amount of screen.

Three things live here, in the order they carry weight: `indicator.label` is
the answer as data, `indicator.statusline` is the same answer in statusline
syntax, and `indicator.update` draws it in a window of this plugin's own.

`display` says which of the two parts are in the label and `style` shapes the
number, so `style` has nothing to say about `display = 'pattern'`. `maxWidth`
is the whole label rather than the pattern alone, which means what the pattern
may have is whatever the brackets and the number have not spent -- measured,
since a bracket is whatever the user asked for. The number never gives way to
make room: it is the answer the indicator exists to give, so a `maxWidth` too
small to hold it is one the label comes out wider than. That case is
the one with a hole in it: an empty cash register would leave a pair of
brackets around nothing, which reads as the indicator being broken rather than
as the drawer being empty, so it draws the `·` the chooser and the picker
already use for a cash register holding nothing.

**The built-in placement is a float rather than the statusline**, and that is
the design decision the rest follows from. `'statusline'` belongs to whatever
set it, and lualine and heirline both write it on every redraw, so a plugin
that assigned it would lose a race it never announced; at `laststatus=0` there
is nothing to assign at all. `'winbar'` and `'tabline'` are the same story with
nvim-navic and bufferline. A float is the only surface this plugin owns
outright, and it works underneath all of them. What it costs is being a window
that has to be kept in step, which is what `indicator.update` is for.

**A statusline needs an expression, not a string.** Two facts about vim, both
checked rather than assumed:

- `%{%` `%}` re-parses its result as statusline items, so a `%#CashRegister3#`
  inside it is a highlight. Inside a plain `%{` `%}` it is drawn as the text it
  is.
- A statusline built by concatenating a lua call holds what that call returned
  when the config was read, and holds it for the rest of the session.

So `statusline` returns statusline syntax rather than plain text, and the docs
write the `%{%` form out rather than leaving it to be found. Every `%` in the
label is doubled on the way out, because a cash register holds whatever was
typed and `%d` is a search for a digit.

`label` takes overrides so that a caller can have an answer other than the
configured one. `:Cash where` asks for the pattern whether or not the indicator
is showing it, since someone who has typed the question wants the whole answer.

**The strip reads a swatch differently from the chooser.** There, a swatch
means "holds a pattern" and `▸` marks the working one. Here the working one
wears the swatch, a filled one wears its color as text, and an empty one is
`Comment`: three states, one cell each, and no marker. A marker moving along
the strip would shift the other eight numbers about every time the answer
changed, and this is a thing read out of the corner of an eye.

**The brackets can be named or written out.** `indicator.brackets` takes
either the name of one of the pairs in `constants.brackets` or a
`{ left, right }` of the user's own, and `options.resolveBrackets` is where the
two become one, so that nothing downstream has to know which way it was
written. Every named pair is one cell on each side and free of CJK coverage,
which is the whole reason the list exists: the fullwidth `【】` this started
with is two cells and missing from most programming fonts. The four made of
box drawing and block characters are East Asian Ambiguous and take two cells a
side under `ambiwidth=double`, which nothing has to handle, because the
indicator measures what it is about to draw rather than counting on a width.

Naming the pairs costs a piece of drift that is worth knowing about.
lua-language-server checks a **list** annotated with an alias element by
element, which is what keeps `constants.bracketStyles` and `cash.BracketStyle`
in step, exactly as it does for the positions. It does **not** check a table's
**keys** against an alias, so `constants.brackets` can gain a name the list
does not have, or miss one it does. That second direction is the one that would
reach a user, since autocomplete would offer a name setup refuses, so the suite
resolves every name in the list rather than leaving it to the checker.

Both halves of a written-out pair are required. A deep merge would otherwise
hand back half of the user's pair and half of the default, which is a chip that
opens with one thing and closes with another.

**Every chunk names a highlight group, including the spaces between the
numbers.** The float draws an unpainted chunk in `NormalFloat` and a statusline
leaves it in whatever group came before it, so the two renderings would not be
the same thing.

`indicator.update` has `updateHighlights`' shape, and for the same reason: work
out what should be on screen, compare it against what is, fix the difference.
It runs from `SafeState`, which is vim about to wait for the next key, so
everything that changes the working cash register redraws it without knowing
that it has to. That is also why the first thing it reads is `indicator.show`:
switched off, which is the default, the whole thing costs one table lookup per
keystroke.

Two things it does are the drawer's decisions over again:

- **Its buffer is kept out of the highlighting.** It holds a search pattern as
  literal text, so a match there would paint it in the color it is reporting.
  There is one buffer for every tab page's window, since there is only ever one
  thing to say.
- **It gets out of the way of the drawer.** The drawer says everything the
  indicator says and eight things besides, and `drawer.position` can put the
  two of them in the same corner.

## The cash register under the cursor

What <kbd>?</kbd><kbd>?</kbd> switches to, in `lua/cash/cursor.lua`.

> The cash register under the cursor is the first one after the working cash
> register with a match covering the cursor, wrapping round, with the working
> cash register itself considered last.

The user can see a color and cannot see a number, and nothing in vim can be
asked what color a piece of text came out. So the question is turned round:
every cash register's pattern is asked whether one of its matches covers the
cursor. One pattern at a time, for the same reason <kbd>n</kbd> asks one at a
time.

Starting after the working cash register is what makes asking again walk
through the registers that overlap here rather than landing on the same one
every time. Considering the working one last is what makes "nothing matches
here" and "you are already in the only one that does" different answers.
Nothing on screen changes in either case, so the message is the only thing that
tells them apart.

Whether a match covers the cursor takes three searches:

- **Backward, for a match start at or before the cursor.** A backward search
  can only answer with a position at or before the cursor, so half of the
  question is settled by asking it this way round.
- **Forward from that start, for the end of a match.** The cursor is moved to
  the start first, because vim's end-of-match search scans from the line the
  cursor is on: asked from where the user actually is, it never sees a
  multi-line match that began further up.
- **Backward from that end, for the start again.** This is what makes the first
  two answers describe one match rather than two. A pattern that matches
  without covering anything (`^`, `\<`, or `^\s*` on a line with no indent) has
  no end of its own, so the second search runs on to some later match's end and
  the round trip comes back somewhere other than where it set off. Vim paints
  nothing for those, and neither does this.

The cursor goes back where it was before anything else can see it, so no
`CursorMoved` comes of it and `autoNoHighlight` has nothing to react to.

This is the one way of choosing a cash register that does not search for its
pattern. The cursor is on one of its matches already.

## Highlight group

The Vim highlight group carrying a cash register's colors, named
`CashRegister1` through `CashRegister9`. Created once during setup.

## Ownership marker

The `Cash.nvim: ` prefix on the `desc` of every mapping this plugin makes, in
`keymaps.ownMapping`.

It is not decoration. Two things read it:

- `addKeyTrigger` uses it to tell its own earlier mapping apart from a foreign
  one, so that a second `setup` replaces its mapping instead of wrapping it and
  searching twice for one keypress.
- The health check uses it to answer "does Cash.nvim still own this key", which
  is how a plugin that loaded later and quietly replaced <kbd>n</kbd> gets
  named.

So every mapping needs the prefix, including ones nobody would think to
describe. The command-line <kbd>Enter</kbd> mapping went without one for a
while, and it was invisible to both of the above.

## Health check

`lua/cash/health.lua`, which `:checkhealth cash` runs.

> Everything in it is something that can be wrong without the plugin saying so
> at the time.

That is the whole admission criterion. Colors that do not render, highlight
groups a colorscheme cleared, a key something else took, cash registers that
did not come back: none of them raise an error, and all of them look from the
outside like the plugin being broken.

It reports and never repairs. A check that fixed what it found would describe a
working plugin and leave the user with one that only works after they run
`:checkhealth`.
