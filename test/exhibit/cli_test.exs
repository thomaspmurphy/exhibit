defmodule Exhibit.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Exhibit.CLI
  alias Exhibit.Fixtures

  test "finds the nearest ancestor with a mix.exs" do
    assert CLI.find_project(Path.join(Fixtures.sample_app(), "lib")) == Fixtures.sample_app()
    assert CLI.find_project(System.tmp_dir!()) == nil
  end

  test "prints help and version" do
    assert capture_io(fn -> assert CLI.run(["--help"]) == 0 end) =~ "exhibit run NOTEBOOK"
    assert capture_io(fn -> assert CLI.run(["--version"]) == 0 end) =~ ~r/^\d+\.\d+\.\d+/
  end

  test "open needs exactly one notebook and must find it" do
    assert capture_io(:stderr, fn -> assert CLI.run(["open"]) == 2 end) =~ "exactly one"

    assert capture_io(:stderr, fn -> assert CLI.run(["open", "/nope.livemd"]) == 1 end) =~
             "not found"
  end

  test "rejects unknown commands with status 2" do
    assert capture_io(:stderr, fn -> assert CLI.run(["frobnicate"]) == 2 end) =~ "unknown command"
  end

  test "pr-body converts the fixture notebook" do
    out = capture_io(fn -> assert CLI.run(["pr-body", Fixtures.notebook("basic")]) == 0 end)
    assert out =~ "```text\nstale output"
    refute out =~ "<!-- livebook"
  end

  test "install-skill writes SKILL.md into the given directory" do
    dir = Path.join(System.tmp_dir!(), "exhibit-skill-#{System.unique_integer([:positive])}")

    assert capture_io(fn -> assert CLI.run(["install-skill", "--dir", dir]) == 0 end) ==
             dir <> "\n"

    assert File.read!(Path.join(dir, "SKILL.md")) =~ "name: exhibit"
  end
end
