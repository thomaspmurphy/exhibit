defmodule Exhibit.Fixtures do
  @moduledoc false

  @root Path.expand("../..", __DIR__)

  def root, do: @root
  def sample_app, do: Path.join(@root, "test/fixtures/sample_app")
  def notebook(name), do: Path.join(@root, "test/fixtures/notebooks/#{name}.livemd")
  def runner, do: Path.join(@root, "priv/runner.exs")

  @doc "Copies a fixture notebook into a fresh temporary directory and returns its path."
  def tmp_notebook(name) do
    dir = Path.join(System.tmp_dir!(), "exhibit-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    target = Path.join(dir, "#{name}.livemd")
    File.cp!(notebook(name), target)
    target
  end

  @doc "Runs the generated runner on `notebook` inside the sample app."
  def run_notebook(notebook) do
    System.cmd("mix", ["run", runner(), notebook],
      cd: sample_app(),
      env: [{"MIX_ENV", "test"}],
      stderr_to_stdout: true
    )
  end
end
