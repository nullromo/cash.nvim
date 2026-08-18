Issues, comments, discussions, feature requests, and pull requests are welcome.
At this point, I will be happy if anyone other than me ever sees this.

## Running the tests

```sh
nvim --headless -u NONE -l tests/run.lua
```

The tests run inside a real Neovim and assert on what vim actually did, so there
is nothing to install. The command exits non-zero if anything fails.

Checks marked `known` are behaviour that is currently wrong and not yet fixed.
They do not fail the run, but they do fail if they start passing, so that they
get promoted to normal checks once the bug is dealt with.

## Type checking

```sh
nvim --headless -u NONE -l scripts/typecheck.lua
```

Needs [lua-language-server](https://luals.github.io) on your PATH. What it knows
about Neovim's own API it gets from `.luarc.json`, which points at
`$VIMRUNTIME`. This runs through Neovim, which knows where that is.

The types themselves are [LuaCATS](https://luals.github.io/wiki/annotations/)
annotations in the source, and `cash.Options` is the one worth knowing about
outside it. Annotate your own config with it and your editor will offer you the
option names and the values each one takes:

```lua
---@type cash.Options
local opts = { chooser = { style = 'strip' } }
require('cash').setup(opts)
```

## Formatting

```sh
stylua lua tests scripts
```

## CI

All three tests run on every pull request, in
[.github/workflows/ci.yml](./.github/workflows/ci.yml). Both tools are pinned
there (lua-language-server at 3.19.1, stylua at 2.5.2) so that a release of
either cannot fail a pull request that changed nothing.

See [CONTEXT.md](./CONTEXT.md) for the words this project uses for its own
concepts.
