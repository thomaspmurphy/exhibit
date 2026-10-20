defmodule Exhibit.ParserTest do
  use ExUnit.Case, async: true

  alias Exhibit.Parser

  @source File.read!(Exhibit.Fixtures.notebook("basic"))

  test "finds the cells with their lines, metadata and stale outputs" do
    cells = @source |> Parser.parse() |> Parser.cells()

    assert [first, second, third] = cells

    assert first.line == 27
    assert first.source == "IO.puts(\"hello from the notebook\")\nx = 40"
    assert first.metadata == []
    assert first.outputs == ["stale output that must be regenerated", "another stale output"]

    assert second.line == 48
    assert second.metadata == [~s|<!-- livebook:{"reevaluate_automatically":true} -->|, ""]
    assert second.outputs == []

    assert third.fence == "```"
    assert third.source =~ "S.add(x, 2)"
  end

  test "keeps a force_markdown elixir fence as markdown" do
    blocks = Parser.parse(@source)
    [first_markdown | _] = blocks

    assert first_markdown.type == :markdown
    assert "not_a_cell = :kept_as_markdown" in first_markdown.lines
    assert length(Parser.cells(blocks)) == 3
  end

  test "round-trips the notebook byte for byte" do
    assert @source |> Parser.parse() |> Parser.render() == @source
  end

  test "round-trips everything but the outputs once they are dropped" do
    without_outputs =
      @source
      |> Parser.parse()
      |> Enum.map(fn
        %{type: :cell} = cell -> %{cell | outputs: []}
        block -> block
      end)
      |> Parser.render()

    expected =
      @source
      |> String.replace(
        ~s(\n\n<!-- livebook:{"output":true} -->\n\n```\nstale output that must be regenerated\n```),
        ""
      )
      |> String.replace(
        ~s(\n\n<!-- livebook:{"output":true} -->\n\n```\nanother stale output\n```),
        ""
      )

    assert without_outputs == expected
    refute without_outputs =~ "stale"
  end

  test "renders new outputs separated by blank lines, like Livebook" do
    source = "# T\n\n```elixir\n1 + 1\n```\n\n## Next\n"

    rendered =
      source
      |> Parser.parse()
      |> Enum.map(fn
        %{type: :cell} = cell -> %{cell | outputs: ["out\n", "2"]}
        block -> block
      end)
      |> Parser.render()

    assert rendered == """
           # T

           ```elixir
           1 + 1
           ```

           <!-- livebook:{"output":true} -->

           ```
           out
           ```

           <!-- livebook:{"output":true} -->

           ```
           2
           ```

           ## Next
           """
  end

  test "handles longer fences on cells and an empty cell" do
    source = "````elixir\n\"```\"\n````\n\n```elixir\n```\n"
    assert [a, b] = source |> Parser.parse() |> Parser.cells()
    assert a.fence == "````"
    assert a.source == ~s("```")
    assert b.source == ""
    assert source |> Parser.parse() |> Parser.render() == source
  end

  test "raises on an unterminated cell" do
    assert_raise ArgumentError, ~r/unterminated elixir cell opened on line 1/, fn ->
      Parser.parse("```elixir\n1\n")
    end
  end
end
