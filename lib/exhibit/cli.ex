defmodule Exhibit.CLI do
  @moduledoc """
  The `exhibit` escript.

      exhibit run NOTEBOOK [--project DIR] [--env ENV] [--open]
      exhibit open NOTEBOOK
      exhibit pr-body NOTEBOOK
      exhibit install-skill [--dir DIR]
      exhibit --help | --version

  The runner script and the skill files are embedded at compile time, since
  an escript carries no `priv/` directory.
  """

  @version Mix.Project.config()[:version]

  @runner_path Path.expand("../../priv/runner.exs", __DIR__)
  @external_resource @runner_path
  @runner File.read!(@runner_path)

  @skill_dir Path.expand("../../skills/exhibit", __DIR__)
  @skill_files (for path <- Path.wildcard(Path.join(@skill_dir, "**/*")), File.regular?(path) do
                  {Path.relative_to(path, @skill_dir), File.read!(path)}
                end)
  for {relative, _content} <- @skill_files do
    @external_resource Path.join(@skill_dir, relative)
  end

  @help """
  exhibit #{@version}

  Usage:
    exhibit run NOTEBOOK [--project DIR] [--env ENV] [--open]
        Evaluate the notebook's Elixir cells inside the project and write
        Livebook-format outputs back into the file. DIR defaults to the
        nearest ancestor of NOTEBOOK containing mix.exs; ENV defaults to test.
        Exits with the runner's status (1 if a cell failed). With --open,
        open the notebook in Livebook after a successful run.

    exhibit open NOTEBOOK
        Open the notebook in Livebook: the macOS desktop app if installed
        (open -a Livebook), otherwise a detached `livebook server --open`.

    exhibit pr-body NOTEBOOK
        Print the notebook as GitHub-flavoured markdown for a PR description.

    exhibit install-skill [--dir DIR]
        Copy the Claude Code skill into ~/.claude/skills/exhibit (or DIR).

    exhibit --help
    exhibit --version
  """

  @doc "Escript entry point."
  @spec main([String.t()]) :: no_return() | :ok
  def main(args) do
    case run(args) do
      0 -> :ok
      status -> System.halt(status)
    end
  end

  @doc "Runs the CLI and returns the exit status instead of halting."
  @spec run([String.t()]) :: non_neg_integer()
  def run(["run" | args]), do: run_notebook(args)
  def run(["open", path]), do: open_notebook(Path.expand(path))
  def run(["open" | _]), do: usage_error("open takes exactly one NOTEBOOK")
  def run(["pr-body", path]), do: pr_body(path)
  def run(["pr-body" | _]), do: usage_error("pr-body takes exactly one NOTEBOOK")
  def run(["install-skill" | args]), do: install_skill(args)
  def run([flag]) when flag in ["--help", "-h", "help"], do: print_help(0)
  def run([flag]) when flag in ["--version", "-v", "version"], do: print_version()
  def run([]), do: print_help(0)
  def run([command | _]), do: usage_error("unknown command #{inspect(command)}")

  # -- run -----------------------------------------------------------------

  defp run_notebook(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [project: :string, env: :string, open: :boolean])

    with [] <- invalid,
         [notebook] <- rest,
         {:ok, project} <- project_for(notebook, opts[:project]) do
      env = Keyword.get(opts, :env, "test")
      notebook = Path.expand(notebook)

      case exec_runner(notebook, project, env) do
        0 -> if opts[:open], do: open_notebook(notebook), else: 0
        status -> status
      end
    else
      [{flag, _} | _] -> usage_error("unknown option #{flag}")
      [] -> usage_error("run needs a NOTEBOOK")
      [_ | _] -> usage_error("run takes exactly one NOTEBOOK")
      {:error, message} -> error(message)
    end
  end

  defp project_for(_notebook, dir) when is_binary(dir) do
    project = Path.expand(dir)

    if File.exists?(Path.join(project, "mix.exs")),
      do: {:ok, project},
      else: {:error, "no mix.exs in #{project}"}
  end

  defp project_for(notebook, nil) do
    case find_project(Path.dirname(Path.expand(notebook))) do
      nil -> {:error, "no mix.exs found in any ancestor of #{notebook}; pass --project DIR"}
      project -> {:ok, project}
    end
  end

  @doc "The nearest directory at or above `dir` containing a `mix.exs`, or nil."
  @spec find_project(Path.t()) :: Path.t() | nil
  def find_project(dir) do
    cond do
      File.exists?(Path.join(dir, "mix.exs")) -> dir
      Path.dirname(dir) == dir -> nil
      true -> find_project(Path.dirname(dir))
    end
  end

  defp exec_runner(notebook, project, env) do
    if File.exists?(notebook) do
      runner =
        Path.join(System.tmp_dir!(), "exhibit-runner-#{System.unique_integer([:positive])}.exs")

      File.write!(runner, @runner)

      try do
        {_, status} =
          System.cmd("mix", ["run", runner, notebook],
            cd: project,
            env: [{"MIX_ENV", env}],
            into: IO.binstream(:stdio, :line)
          )

        status
      after
        File.rm(runner)
      end
    else
      error("notebook not found: #{notebook}")
    end
  end

  # -- open ----------------------------------------------------------------

  defp open_notebook(notebook) do
    cond do
      not File.exists?(notebook) ->
        error("notebook not found: #{notebook}")

      desktop_app() ->
        {_, status} = System.cmd("open", ["-a", "Livebook", notebook], stderr_to_stdout: true)
        if status == 0, do: IO.puts("exhibit: opened #{notebook} in Livebook")
        status

      System.find_executable("livebook") ->
        # The server keeps running in the background after we exit.
        {_, status} =
          System.cmd("sh", [
            "-c",
            ~s(nohup livebook server --open "$0" >/dev/null 2>&1 &),
            notebook
          ])

        if status == 0, do: IO.puts("exhibit: started livebook server for #{notebook}")
        status

      true ->
        error(
          "no Livebook found: install the desktop app from https://livebook.dev " <>
            "or the escript (mix escript.install hex livebook), then open #{notebook}"
        )
    end
  end

  defp desktop_app do
    :os.type() == {:unix, :darwin} and
      Enum.any?(
        [
          "/Applications/Livebook.app",
          Path.join(System.user_home!(), "Applications/Livebook.app")
        ],
        &File.dir?/1
      )
  end

  # -- pr-body -------------------------------------------------------------

  defp pr_body(path) do
    case File.read(path) do
      {:ok, source} ->
        IO.write(Exhibit.PrBody.convert(source))
        0

      {:error, reason} ->
        error("cannot read #{path}: #{:file.format_error(reason)}")
    end
  end

  # -- install-skill -------------------------------------------------------

  defp install_skill(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [dir: :string])

    case {invalid, rest} do
      {[], []} ->
        dir = opts[:dir] || Path.join(System.user_home!(), ".claude/skills/exhibit")
        dir = Path.expand(dir)

        for {relative, content} <- @skill_files do
          target = Path.join(dir, relative)
          File.mkdir_p!(Path.dirname(target))
          File.write!(target, content)
        end

        IO.puts(dir)
        0

      {[{flag, _} | _], _} ->
        usage_error("unknown option #{flag}")

      _ ->
        usage_error("install-skill takes no positional arguments")
    end
  end

  # -- helpers -------------------------------------------------------------

  defp print_version do
    IO.puts(@version)
    0
  end

  defp print_help(status) do
    IO.write(@help)
    status
  end

  defp usage_error(message) do
    IO.puts(:stderr, "exhibit: #{message}\n")
    IO.write(:stderr, @help)
    2
  end

  defp error(message) do
    IO.puts(:stderr, "exhibit: #{message}")
    1
  end
end
