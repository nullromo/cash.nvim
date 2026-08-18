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

## Releasing

Cash.nvim follows [semantic versioning](https://semver.org). A patch release
fixes things, a minor release adds them, and a major release is where anything a
user has configured or mapped can change. An option that gets renamed keeps
working through `options.renamedOptions`, which warns with `vim.deprecate` and
specifies the version the old name stops being read in.

A release is a tag and nothing else. There is no version bump commit and no
release branch:

1. Bump `CashModule.version` in [lua/cash/cash.lua](./lua/cash/cash.lua) to the
   number being released.
2. Tag it: `git tag -a v0.3.0 -m 'v0.3.0'`
3. Push the tag: `git push origin v0.3.0`

[.github/workflows/release.yml](./.github/workflows/release.yml) takes it from
there. It checks that the tag and the constant agree, publishes to luarocks.org,
and creates the GitHub release with notes generated from the commits since the
last tag. That last part is why there is no changelog file to keep up to date.

Publishing needs a `LUAROCKS_API_KEY` repository secret, from the API keys
section of a luarocks.org account's settings. Without it the publish step fails
and no release is created, which is recoverable: fix the secret and re-run the
workflow. Everything that has already succeeded is skipped on a re-run.

See [CONTEXT.md](./CONTEXT.md) for the words this project uses for its own
concepts.
