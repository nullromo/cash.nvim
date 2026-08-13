Issues, comments, discussions, feature requests, and pull requests are welcome.
At this point, I will be happy if anyone other than me ever sees this.

## Running the tests

```sh
nvim --headless -u NONE -l tests/run.lua
```

The tests run inside a real Neovim and assert on what vim actually did, so
there is nothing to install. The command exits non-zero if anything fails.

Checks marked `known` are behaviour that is currently wrong and not yet fixed.
They do not fail the run, but they do fail if they start passing, so that they
get promoted to normal checks once the bug is dealt with.

See [CONTEXT.md](./CONTEXT.md) for the words this project uses for its own
concepts.
