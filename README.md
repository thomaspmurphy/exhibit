# Exhibit

## The problem

Code generation has changed what gets pushed. A developer can now open a pull
request for a change they have read but do not hold a theory of: they know
what the diff says, not why it is shaped that way, what it assumes, or what
it would take to break it. Call that debt cognitive debt. It accrues quietly,
one merged branch at a time, and it is paid later by whoever has to change the
code without the understanding that should have come with it.

Peter Naur's "Programming as Theory Building" (1985) argued that a program is
not its source text. The program is the understanding in the heads of the
people who built it: what the code is for, how it maps onto the problem, and
which modifications fit. The text alone cannot carry that theory, which is why
a team that inherits a codebase without its authors struggles even when the
code is clean. Generated code arrives with no such theory anywhere. Nobody
built one, and reading a raw diff does not build one either; it shows what
changed, not how the change behaves.

Exhibit exists to close that theory gap for one change at a time. It turns a
branch into a short, runnable explanation: a Livebook notebook with a
paragraph on what changed and why, a diagram of where it lives, a few cells
that exercise the new behaviour with their outputs filled in, and pointers
for the reviewer. Writing it forces the author to form the theory before
pushing. Reading it gives the reviewer the theory before approving. The same
notebook becomes the PR description, so the explanation ships with the change.

## What it is

Three parts:

1. **A runner** that evaluates a notebook's Elixir cells inside the target
   project and writes Livebook-format outputs back into the file. Livebook
   has no headless runner, which is the reason this exists.
2. **An escript**, `exhibit`, wrapping the runner, plus a conversion of the
   notebook into a PR description.
3. **A Claude Code skill** that reads a diff and writes the notebook.

Target projects need no dependency on exhibit. The runner is one
self-contained script that `mix run` executes in the project's own VM, so the
cells see the project's modules, config and started applications.

## Install

The escript, built with the Elixir and OTP active in the directory you run
this from, so run it from a project you will use it on:

```
mix escript.install github thomaspmurphy/exhibit
```

The skill does this itself on first use when `exhibit` is missing, and
runs it by absolute path from the directory `Mix.path_for(:escripts)`
reports when that is not on the PATH. Under mise or asdf that directory is
per Elixir version, so each toolchain keeps its own build. An escript must
run on the same OTP major it was built with; for a project on another OTP,
run the install again from that project.

The skill, either through the escript or as a Claude Code plugin:

```
exhibit install-skill        # copies into ~/.claude/skills/exhibit
```

or as a Claude Code plugin; the repo is its own marketplace:

```
/plugin install exhibit --marketplace thomaspmurphy/exhibit
```

On older Claude Code versions, add the marketplace first with
`claude plugin marketplace add thomaspmurphy/exhibit`, then
`claude plugin install exhibit@exhibit`.

Elixir 1.15 or later. The escript must be built and run with the same OTP
major as the target project, as any escript must.

## Commands

```
exhibit run NOTEBOOK [--project DIR] [--env ENV]
```

Evaluates every Elixir cell in document order, in one process, carrying the
binding and the evaluation environment across cells so `alias`, `import` and
`require` persist as they do in Livebook. Each cell's standard output and its
result become persisted outputs. A cell that raises gets the formatted error
as its output, later cells get none, and the command exits 1. The project is
the nearest ancestor of the notebook containing `mix.exs`; the environment
defaults to `test`. Under the hood:

```
cd DIR && MIX_ENV=test mix run <runner.exs> NOTEBOOK
```

Before the first cell, the runner compares each Ecto repo's database with
the branch's migrations and prints one line if the database is behind or
was migrated by a branch this one lacks. It does not migrate anything. The
usual cause is several worktrees sharing one test database; the fix is a
database per checkout, which the project's own config already allows when
it reads the database name from the environment:

```
DB_DATABASE=myapp_test_mybranch MIX_ENV=test mix ecto.setup
DB_DATABASE=myapp_test_mybranch exhibit run .exhibit/mybranch.livemd
```

```
exhibit open NOTEBOOK
```

Opens the notebook in Livebook: the macOS desktop app when it is installed
(the `.dmg` install provides no `livebook` command), otherwise a detached
`livebook server --open`. `exhibit run --open` does the same after a
successful run, which is how the skill hands the notebook over.

```
exhibit pr-body NOTEBOOK
```

Prints the notebook as GitHub-flavoured markdown: Livebook comments dropped,
headings, prose and Mermaid kept, each Elixir cell followed by a `text` fence
holding its outputs. Pipe it into `gh pr edit N --body-file -`.

```
exhibit install-skill [--dir DIR]
```

Copies the skill into `~/.claude/skills/exhibit` or `DIR`.

## The notebook

The skill writes `<project>/.exhibit/<branch-slug>.livemd` and adds
`.exhibit/` to `.git/info/exclude`, so the target repository is untouched.
The notebook is disposable and never committed. Its structure is fixed:

```
# Title
One paragraph: what changed and why.

## Where it lives
One Mermaid diagram: entry point -> changed function -> effect.

## See it work
A sandbox cell if the project uses Ecto, then two to four cells,
each introduced by one sentence, each ending in a stable projection.

## Review pointers
Three to five bullets.
```

Budgets: at most eight cells, under three hundred words of prose, one
diagram. The skill opens it in Livebook when the run succeeds; `exhibit
open <path>` reopens it. The outputs are already in the file, and attaching
the runtime to the project's own `iex --sname name -S mix` makes the cells
live again.

Only terminal text is persisted, matching what Livebook itself writes when
`persist_outputs` is on. Notebooks stay text-only, diff cleanly, and read
without a runtime.

## Development

```
mix test                       # includes an end-to-end run against test/fixtures/sample_app
mix exhibit.build_runner       # regenerates priv/runner.exs from lib/
mix escript.build              # regenerates the runner, then builds ./exhibit
```

`priv/runner.exs` is generated from `lib/exhibit/{parser,output,runner}.ex`
and committed; a test fails if it drifts.

## License

MIT, see [LICENSE](LICENSE).
