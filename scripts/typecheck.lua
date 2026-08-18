-- Type checks the plugin and the specs with lua-language-server.
--
--     nvim --headless -u NONE -l scripts/typecheck.lua
--
-- Run through neovim rather than by hand for two reasons. The settings in
-- .luarc.json name $VIMRUNTIME, which is where lua-language-server learns what
-- vim.api and the rest are, and a neovim knows where its own runtime is while a
-- shell does not. And the answer has to be sorted into what is this plugin's
-- and what is not.

local root = vim.fs.normalize(vim.fn.getcwd())
local logpath = vim.fn.tempname()

local checker = vim.fn.exepath('lua-language-server')
if checker == '' then
    io.stderr:write(
        'lua-language-server is not on PATH.\n'
            .. 'See https://luals.github.io/#other-install\n'
    )
    os.exit(1)
end

local result = vim.system({
    checker,
    '--check',
    root,
    '--configpath',
    root .. '/.luarc.json',
    -- below a warning is style rather than a mistake, and a shadowed local
    -- should not fail a pull request
    '--checklevel',
    'Warning',
    '--logpath',
    logpath,
}, { text = true }):wait()

-- Which shape the answer comes in depends on the version on PATH.
--
-- Older ones -- 3.6 is the one this was met on -- always exit 0 and write every
-- finding to check.json, the seventy-odd files of the neovim runtime they just
-- read included. Those are not ours to fix, so the report is read and sorted
-- through. Newer ones -- 3.19, which is what CI runs -- check the workspace on
-- its own, exit non-zero when they find something, and write no report at all,
-- so their own answer is the answer
local report = logpath .. '/check.json'
if vim.fn.filereadable(report) == 0 then
    io.write(result.stdout or '')
    io.stderr:write(result.stderr or '')
    if result.code ~= 0 then
        os.exit(1)
    end
    print('no problems found')
    os.exit(0)
end

local decoded = vim.json.decode(table.concat(vim.fn.readfile(report), '\n'))

local findings = 0
for uri, problems in pairs(decoded) do
    local path = vim.fs.normalize(vim.uri_to_fname(uri))
    if vim.startswith(path, root) then
        for _, problem in ipairs(problems) do
            findings = findings + 1
            print(string.format(
                '%s:%d:%d: %s (%s)',
                -- vim.fs.relpath is newer than the neovim this plugin
                -- supports, and root is where the path starts anyway
                path:sub(#root + 2),
                problem.range.start.line + 1,
                problem.range.start.character + 1,
                (problem.message:gsub('\n.*', '')),
                problem.code
            ))
        end
    end
end

if findings > 0 then
    print(string.format('\n%d problem(s) found', findings))
    os.exit(1)
end

print('no problems found')
