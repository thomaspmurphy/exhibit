defmodule Exhibit.PrBodyTest do
  use ExUnit.Case, async: true

  alias Exhibit.PrBody

  @source File.read!(Exhibit.Fixtures.notebook("basic"))

  test "drops livebook comments, keeps prose and mermaid, renders outputs as a text fence" do
    body = PrBody.convert(@source)

    refute body =~ "<!-- livebook"
    assert String.starts_with?(body, "# Sample notebook\n\nA paragraph of prose")

    assert body =~
             "```mermaid\ngraph LR\n  A[caller] --> B[SampleApp.greet/1]\n  B --> C[string]\n```"

    assert body =~ "## Review pointers\n\n* Nothing to see here.\n"

    assert body =~ """
           ```elixir
           IO.puts("hello from the notebook")
           x = 40
           ```

           ```text
           stale output that must be regenerated
           another stale output
           ```

           This cell sets an alias used by the next one.

           ```elixir
           alias SampleApp, as: S
           S.greet("exhibit")
           ```

           The alias and the binding carry over.
           """
  end

  test "keeps a force_markdown sample as a plain elixir fence" do
    body = PrBody.convert(@source)

    assert body =~
             "not a cell:\n\n```elixir\nnot_a_cell = :kept_as_markdown\n```\n\n## Where it lives"
  end

  test "lengthens the text fence when an output contains backticks" do
    source =
      "# T\n\n```elixir\n1\n```\n\n<!-- livebook:{\"output\":true} -->\n\n````\n\"```\"\n````\n"

    assert PrBody.convert(source) == "# T\n\n```elixir\n1\n```\n\n````text\n\"```\"\n````\n"
  end
end
