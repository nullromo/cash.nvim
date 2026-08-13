-- Entry point for the Cash.nvim test suite:
--
--     nvim --headless -u NONE -l tests/run.lua
--
-- Every tests/*_spec.lua file is expected to return a function taking the
-- harness. The whole suite shares one Neovim, so each spec is responsible for
-- putting the plugin back into a known state before it starts.

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

vim.opt.runtimepath:prepend(root)

local harness = dofile(root .. '/tests/harness.lua')

local specs = vim.fn.glob(root .. '/tests/*_spec.lua', false, true)
table.sort(specs)

for _, spec in ipairs(specs) do
    dofile(spec)(harness)
end

os.exit(harness.summary() == 0 and 0 or 1)
