defmodule Mix.Tasks.Exhibit.BuildRunnerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @committed Path.expand("../../../priv/runner.exs", __DIR__)

  test "priv/runner.exs is current with lib/" do
    out = Path.join(System.tmp_dir!(), "exhibit-runner-#{System.unique_integer([:positive])}.exs")
    capture_io(fn -> Mix.Tasks.Exhibit.BuildRunner.run(["--out", out]) end)

    assert File.read!(out) == File.read!(@committed),
           "priv/runner.exs is stale: run `mix exhibit.build_runner` and commit the result"
  end

  test "the generated script only defines Exhibit.Runner modules and depends on nothing" do
    source = File.read!(@committed)

    modules =
      ~r/^defmodule ([\w.]+) do/m
      |> Regex.scan(source)
      |> Enum.map(fn [_, name] -> name end)

    assert modules == ["Exhibit.Runner.Parser", "Exhibit.Runner.Output", "Exhibit.Runner"]
    refute source =~ ~r/\bExhibit\.(Parser|Output|CLI|PrBody)\b/
    assert String.ends_with?(source, "Exhibit.Runner.main(System.argv())\n")
  end
end
