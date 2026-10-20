defmodule Exhibit.OutputTest do
  use ExUnit.Case, async: true

  alias Exhibit.Output

  test "renders a text output exactly like Livebook" do
    assert Output.text_block("hello\n") == """
           <!-- livebook:{"output":true} -->

           ```
           hello
           ```\
           """
  end

  test "removes exactly one trailing newline" do
    assert Output.text_block("a\n\n") =~ "```\na\n\n```"
    assert Output.text_block("a") =~ "```\na\n```"
  end

  test "strips ANSI escapes" do
    assert Output.strip_ansi("\e[32m:ok\e[0m and \e[1;31mred\e[0m") == ":ok and red"
    assert Output.text_block("\e[33m%{a: 1}\e[0m") =~ "```\n%{a: 1}\n```"
  end

  test "uses a fence longer than any run of backticks in the body" do
    assert Output.code_block_delimiter("plain") == "```"
    assert Output.code_block_delimiter("has ``` inside") == "````"
    assert Output.code_block_delimiter("has ````` inside") == "``````"

    block = Output.text_block("x = \"```\"")
    assert block =~ "\n````\nx = \"```\"\n````"
  end

  test "separates several outputs with a blank line" do
    assert Output.text_blocks(["a", "b"]) ==
             Output.text_block("a") <> "\n\n" <> Output.text_block("b")
  end

  describe "ensure_persist_outputs/1" do
    test "prepends the header when missing" do
      assert Output.ensure_persist_outputs("# T\n") ==
               ~s(<!-- livebook:{"persist_outputs":true} -->\n\n# T\n)
    end

    test "leaves a correct header alone" do
      doc = ~s(<!-- livebook:{"persist_outputs":true} -->\n\n# T\n)
      assert Output.ensure_persist_outputs(doc) == doc
    end

    test "adds the key to existing notebook metadata" do
      doc = ~s(<!-- livebook:{"autosave_interval_s":30} -->\n\n# T\n)

      assert Output.ensure_persist_outputs(doc) ==
               ~s(<!-- livebook:{"persist_outputs":true,"autosave_interval_s":30} -->\n\n# T\n)
    end

    test "flips persist_outputs false to true" do
      doc = ~s(<!-- livebook:{"persist_outputs":false} -->\n\n# T\n)

      assert Output.ensure_persist_outputs(doc) ==
               ~s(<!-- livebook:{"persist_outputs":true} -->\n\n# T\n)
    end
  end
end
