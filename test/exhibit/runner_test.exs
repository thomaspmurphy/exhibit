defmodule Exhibit.RunnerTest do
  # Each test compiles and runs the sample app in a separate OS process, so
  # keep them sequential to avoid two `mix` invocations racing on `_build`.
  use ExUnit.Case, async: false

  alias Exhibit.Fixtures
  alias Exhibit.Parser

  @moduletag timeout: 120_000

  describe "a notebook whose cells all succeed" do
    setup do
      notebook = Fixtures.tmp_notebook("basic")
      {output, status} = Fixtures.run_notebook(notebook)
      %{notebook: notebook, written: File.read!(notebook), output: output, status: status}
    end

    test "exits 0 and reports progress per cell", ctx do
      assert ctx.status == 0, ctx.output
      assert ctx.output =~ "== cell 1 (line 27)\nhello from the notebook\n40\n"
      assert ctx.output =~ "== cell 2 (line 48)\n\"Hello, exhibit!\"\n"
      assert ctx.output =~ "== cell 3 (line 55)\n%{sum: 42, ticks: \"``` inside a result\"}\n"
    end

    test "writes stdout and result outputs in Livebook format", ctx do
      assert ctx.written =~ """
             ```elixir
             IO.puts("hello from the notebook")
             x = 40
             ```

             <!-- livebook:{"output":true} -->

             ```
             hello from the notebook
             ```

             <!-- livebook:{"output":true} -->

             ```
             40
             ```

             This cell sets an alias used by the next one.
             """
    end

    test "carries alias and binding across cells and lengthens the fence when needed", ctx do
      assert ctx.written =~ ~s(```\n"Hello, exhibit!"\n```)
      assert ctx.written =~ ~s(````\n%{sum: 42, ticks: "``` inside a result"}\n````)
    end

    test "drops stale outputs and keeps everything else byte for byte", ctx do
      refute ctx.written =~ "stale"
      original = File.read!(Fixtures.notebook("basic"))
      assert strip_outputs(ctx.written) == strip_outputs(original)

      assert String.starts_with?(
               ctx.written,
               ~s(<!-- livebook:{"persist_outputs":true} -->\n\n# )
             )
    end
  end

  describe "a notebook with a failing cell" do
    setup do
      notebook = Fixtures.tmp_notebook("failing")
      {output, status} = Fixtures.run_notebook(notebook)
      %{notebook: notebook, written: File.read!(notebook), output: output, status: status}
    end

    test "exits 1 and names the failing cell on stderr", ctx do
      assert ctx.status == 1
      assert ctx.output =~ "exhibit: cell 2 (line 9) failed"
      assert ctx.output =~ "** (KeyError) key :missing not found"
    end

    test "writes outputs up to the failure, the error, and nothing after", ctx do
      assert ctx.written =~ "```\nstill captured\n```"
      assert ctx.written =~ "```\n:first\n```"
      assert ctx.written =~ "** (KeyError) key :missing not found"
      assert ctx.written =~ "lib/sample_app.ex:8: SampleApp.explode/1"
      assert ctx.written =~ "failing.livemd:9:"

      [_, _, last] = ctx.written |> Parser.parse() |> Parser.cells()
      assert last.source == ":never_evaluated"
      assert last.outputs == []
    end

    test "adds the persist_outputs header when the notebook lacked one", ctx do
      assert String.starts_with?(
               ctx.written,
               ~s(<!-- livebook:{"persist_outputs":true} -->\n\n# Failing notebook)
             )
    end
  end

  defp strip_outputs(source) do
    source
    |> Parser.parse()
    |> Enum.map(fn
      %{type: :cell} = cell -> %{cell | outputs: []}
      block -> block
    end)
    |> Parser.render()
    |> String.replace_prefix(~s(<!-- livebook:{"persist_outputs":true} -->\n\n), "")
  end
end
