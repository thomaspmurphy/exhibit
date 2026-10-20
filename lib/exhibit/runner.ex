defmodule Exhibit.Runner do
  @moduledoc """
  Evaluates the Elixir cells of a notebook in order, inside the current VM,
  and writes Livebook-format outputs back into the file.

  This module is the heart of `priv/runner.exs`, which `mix
  exhibit.build_runner` assembles from `lib/` so a target project can run
  it with `MIX_ENV=test mix run priv/runner.exs NOTEBOOK` and no extra
  dependency.

  Cells share one binding and one evaluation environment, so `alias`,
  `import`, `require` and variables carry over, as in Livebook. Standard
  output is captured per cell by pointing the group leader at a `StringIO`.
  A cell that raises, throws or exits gets the formatted error as its
  output; later cells are left without outputs and the run fails.
  """

  alias Exhibit.Output
  alias Exhibit.Parser

  @max_frames 8

  @doc "Entry point of the generated script: `mix run runner.exs NOTEBOOK`."
  @spec main([String.t()]) :: :ok | no_return()
  def main([path]) do
    case run(path) do
      :ok -> :ok
      {:error, _reason} -> System.halt(1)
    end
  end

  def main(_args) do
    IO.puts(:stderr, "usage: mix run runner.exs NOTEBOOK")
    System.halt(2)
  end

  @doc """
  Runs every cell of the notebook at `path` and rewrites the file with
  outputs. Returns `:ok`, or `{:error, message}` if a cell failed; the
  file is written in both cases.

  Options:

    * `:project` - the root of the project the cells run in, used to trim
      stacktraces. Defaults to the current directory.
  """
  @spec run(Path.t(), keyword()) :: :ok | {:error, String.t()}
  def run(path, opts \\ []) do
    project = Keyword.get(opts, :project, File.cwd!())
    path = Path.expand(path)
    blocks = path |> File.read!() |> Parser.parse()

    {blocks, status} = evaluate(blocks, path, project)

    doc = blocks |> Parser.render() |> Output.ensure_persist_outputs()
    write_atomically(path, doc)
    status
  end

  defp evaluate(blocks, path, project) do
    env = Code.env_for_eval(file: path)

    {blocks, {_index, state}} =
      Enum.map_reduce(blocks, {1, {:ok, [], env}}, fn
        %{type: :cell} = cell, {index, {:ok, binding, env}} ->
          {outputs, state} = eval_cell(cell, index, binding, env, path, project)
          {%{cell | outputs: outputs}, {index + 1, state}}

        %{type: :cell} = cell, {index, {:halted, _} = state} ->
          {%{cell | outputs: []}, {index + 1, state}}

        block, acc ->
          {block, acc}
      end)

    case state do
      {:ok, _binding, _env} -> {blocks, :ok}
      {:halted, message} -> {blocks, {:error, message}}
    end
  end

  defp eval_cell(cell, index, binding, env, path, project) do
    IO.puts("== cell #{index} (line #{cell.line})")

    {result, stdout} =
      capture_stdout(fn ->
        try do
          quoted = Code.string_to_quoted!(cell.source, file: path, line: cell.line)
          {:ok, Code.eval_quoted_with_env(quoted, binding, env)}
        catch
          kind, payload -> {:error, kind, payload, __STACKTRACE__}
        end
      end)

    stdout_outputs = if stdout == "", do: [], else: [stdout]

    case result do
      {:ok, {value, binding, env}} ->
        outputs = stdout_outputs ++ [inspect(value, pretty: true, width: 80)]
        print_outputs(outputs)
        {outputs, {:ok, binding, env}}

      {:error, kind, payload, stacktrace} ->
        message = Exception.format(kind, payload, trim_stacktrace(stacktrace, path, project))
        outputs = stdout_outputs ++ [message]
        print_outputs(outputs)
        IO.puts(:stderr, "exhibit: cell #{index} (line #{cell.line}) failed\n#{message}")
        {outputs, {:halted, message}}
    end
  end

  defp capture_stdout(fun) do
    {:ok, io} = StringIO.open("")
    leader = Process.group_leader()
    Process.group_leader(self(), io)

    result =
      try do
        fun.()
      after
        Process.group_leader(self(), leader)
      end

    {_input, output} = StringIO.contents(io)
    StringIO.close(io)
    {result, output}
  end

  defp print_outputs(outputs) do
    Enum.each(outputs, fn text ->
      IO.puts(text |> Output.strip_ansi() |> String.replace_suffix("\n", ""))
    end)
  end

  # Keep the frame that raised plus frames in the notebook or the project,
  # drop our own frames and everything in Elixir, OTP or dependencies.
  defp trim_stacktrace(stacktrace, path, project) do
    stacktrace
    |> Enum.reject(&runner_frame?/1)
    |> Enum.with_index()
    |> Enum.filter(fn {frame, i} -> i == 0 or project_frame?(frame, path, project) end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.take(@max_frames)
  end

  defp runner_frame?({module, _fun, _arity, _info}) when is_atom(module) do
    module |> Atom.to_string() |> String.starts_with?("Elixir.Exhibit.Runner")
  end

  defp runner_frame?(_frame), do: false

  defp project_frame?({_module, _fun, _arity, info}, path, project) do
    case Keyword.get(info, :file) do
      nil ->
        false

      file ->
        file = to_string(file)
        file == path or File.exists?(Path.expand(file, project))
    end
  end

  defp project_frame?(_frame, _path, _project), do: false

  defp write_atomically(path, content) do
    tmp =
      Path.join(
        Path.dirname(path),
        ".#{Path.basename(path)}.#{System.unique_integer([:positive])}.tmp"
      )

    File.write!(tmp, content)
    File.rename!(tmp, path)
  end
end
