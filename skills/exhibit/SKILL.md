---
name: exhibit
description: >
  Explain a branch or pull request of an Elixir project by writing a short Livebook
  notebook (.livemd) that says what changed, why, where it lives, and demonstrates the
  new behaviour with live cells whose outputs are filled in by `exhibit run`. The same
  notebook converts into the PR description. Use whenever the user asks to "explain this
  branch", "explain this PR", "walk me through this PR", "exhibit this", "write the PR
  description", "help me understand what this branch does", or pastes a GitHub PR URL
  for an Elixir repo and asks what it does. Requires the `exhibit` escript
  (`mix escript.install github thomaspmurphy/exhibit`).
metadata:
  version: "0.1.0"
---

# Exhibit a branch

Exhibit turns a diff into something a developer can read and run: a Livebook
with a few paragraphs, one diagram and two to four cells that show the changed
behaviour with their outputs already in the file. You write the notebook from
the diff; `exhibit run` evaluates the cells inside the target project and
writes the outputs back. The notebook is disposable and never committed.

Budgets, which are not negotiable: **at most 8 cells, under 300 words of
prose, one diagram.** A reader should finish it in five minutes.

## 1. Gather context

Find the project root (the nearest ancestor with `mix.exs`) and read the
change, not the whole repo:

```bash
git log --oneline main..HEAD
git diff main...HEAD --stat
git diff main...HEAD
```

Given a PR number or URL instead, use `gh pr view N` and `gh pr diff N`, and
take the title and body from the PR. If the branch name carries a Linear
ticket key (for example `abc-123-fix-thing`), note the key so the title and
prose can refer to it.

If `<project>/.fathom/program.db` exists, the `fathom-query` skill can list
the callers of the changed functions; use it when it helps the diagram or the
review pointers. Do not require it.

## 2. Decide what the reader cares about

Pick the behaviour, not the implementation: the public functions, endpoints,
consumers, workers or Mix tasks the diff changes, and what a caller sees
differently. Private helpers, renames and formatting changes are not worth a
cell. For a bugfix, the thing to show is the input that used to break.

## 3. Write the notebook

Path: `<project>/.exhibit/<branch-slug>.livemd`, where the slug is the branch
name with `/` replaced by `-`. Keep the target repo untouched: add the
directory to the local exclude file, never to `.gitignore`:

```bash
mkdir -p <project>/.exhibit
grep -qxF '.exhibit/' <project>/.git/info/exclude || echo '.exhibit/' >> <project>/.git/info/exclude
```

Fixed structure, in this order:

1. `# <PR or branch title>`
2. One paragraph, three to five sentences: what changed and why. Lead with
   the behaviour, name the motivating problem, mention the ticket if any.
3. `## Where it lives`: one Mermaid diagram (a ```` ```mermaid ```` fence) of
   the flow, entry point -> changed function -> effect, at most eight nodes,
   each labelled with a module or function name a reader can grep for.
4. `## See it work`: cells, each preceded by one sentence saying what it
   demonstrates. For a bugfix the sentence says what the input did before.
   - If the project uses Ecto, the first cell puts the repo in sandbox mode
     and checks out a connection, guarded so it is a no-op when the pool is
     not the sandbox (then the same notebook works in Livebook attached to
     a dev `iex -S mix`):

     ```elixir
     repo = MyApp.Repo

     if repo.config()[:pool] == Ecto.Adapters.SQL.Sandbox do
       Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)
       Ecto.Adapters.SQL.Sandbox.checkout(repo)
       :sandbox
     else
       :shared_db
     end
     ```

   - Then two to four cells showing the change. Every cell ends with a
     stable projection: a map of the fields that matter, a list of names,
     a boolean. Never a raw struct with ids or timestamps, never a PID.
   - A cell may `alias` and `import`; later cells see it, exactly as in
     Livebook. Variables carry over too.
5. `## Review pointers`: three to five bullets: what to read carefully,
   migrations, config changes, what the tests do not cover.

The file must begin with the Livebook header; write it yourself:

```
<!-- livebook:{"persist_outputs":true} -->

# Title
```

### How to write it

The notebook is also the PR description, read by a reviewer who has the diff
open next to it. Write as the author of the change explaining it to a
colleague, in plain declarative sentences. Concretely:

- Every sentence carries something the diff cannot show: the motivating
  problem, a constraint, a behaviour before and after, a decision and its
  reason. If deleting a sentence loses nothing, delete it.
- No preamble and no summary of what the document is about to say. Start
  with the change itself, never with "This PR" or "In this change, we".
- No quality adjectives: not robust, comprehensive, seamless, elegant,
  powerful, clean, enhanced, improved. Say what it does.
- No file-by-file restatement of the diff, no "Key changes" lists, no
  bold-label bullets such as "**Impact:**", no emoji, no closing summary.
- For a bugfix, the shape is "Before, X. Now, Y." with the input that broke.
- Review pointers are specific: a function and what to check in it, a
  migration and what it does to existing rows, a config key and its default.
  Never "ensure tests pass" or "verify the logic is correct".
- The title is a commit subject: short, imperative, no trailing period.

When in doubt, shorter. The outputs do much of the explaining; a cell with
a one-sentence lead-in says more than a paragraph about it.

## 4. Run it

```bash
exhibit run <project>/.exhibit/<branch-slug>.livemd --open
```

`--open` opens the notebook in Livebook once every cell has succeeded, so
the user sees it without being asked to run anything. On a failing run
nothing opens.

The runner executes the cells in the project under `MIX_ENV=test` and
rewrites the file with the outputs. It prints each cell's outputs as it goes
and exits 1 if a cell fails, leaving the error as that cell's output.

Before the first cell the runner compares the test database with the
branch's migrations and prints one line if they differ. If that line
appears, or a cell fails on a missing column or table, suspect the shared
test database before the notebook: in a worktree or on an old branch, give
the checkout its own database (`DB_DATABASE=<name> MIX_ENV=test mix
ecto.setup`, or whatever variable the project's test config reads) and rerun
`exhibit run` with the same variable set.

If a cell fails, read the error, fix the notebook and rerun. At most three
rounds. A cell that still cannot be made to work is replaced by a sentence
saying what could not be demonstrated and why. Never hand over a notebook
with a failing cell.

Read the outputs once more before handing over: they are part of the
explanation and should be short, stable and free of noise.

## 5. Hand over

The successful `--open` run has already opened the notebook in Livebook
(the macOS desktop app if installed, otherwise a `livebook server`). Tell
the user the path, and that `exhibit open <path>` reopens it later. If
`--open` reported that no Livebook was found, say so and give the path.

In Livebook they can attach the runtime to their own node started with
`iex --sname <name> -S mix` from the project to re-run the cells live; the
outputs are already in the file, so reading it without a runtime works too.

Then offer the PR description, and run it only if they say yes:

```bash
exhibit pr-body <project>/.exhibit/<branch-slug>.livemd | gh pr edit <N> --body-file -
```

`exhibit pr-body` drops the Livebook comments and turns each cell's outputs
into a `text` fence under the cell; everything else is passed through.
