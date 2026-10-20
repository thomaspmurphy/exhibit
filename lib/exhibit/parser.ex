defmodule Exhibit.Parser do
  @moduledoc """
  Splits a Livebook `.livemd` file into an ordered list of blocks and
  renders a list of blocks back into a file.

  Two kinds of block:

    * `%{type: :markdown, lines: [String.t()]}`: anything that is not an
      Elixir cell or a persisted output. Kept byte for byte.
    * `%{type: :cell, metadata: [String.t()], fence: String.t(),
      source_lines: [String.t()], source: String.t(), line: pos_integer(),
      outputs: [String.t()]}`: an Elixir code cell. `metadata` holds any
      `<!-- livebook:{...} -->` comment (and the blank lines after it) that
      sat directly before the fence. `line` is the 1-based line of the
      first line of source. `outputs` are the persisted text outputs that
      followed the cell, already in the form Livebook stores them.

  Output blocks are attached to the cell they follow, so a caller that
  regenerates outputs replaces `outputs` and the blank lines that separated
  them from the cell are reproduced by `render/1`.

  An Elixir fence preceded by `<!-- livebook:{"force_markdown":true} -->`
  is a code sample inside a markdown cell, not a cell, and is kept as
  markdown.
  """

  @type markdown :: %{type: :markdown, lines: [String.t()]}
  @type cell :: %{
          type: :cell,
          metadata: [String.t()],
          fence: String.t(),
          source_lines: [String.t()],
          source: String.t(),
          line: pos_integer(),
          outputs: [String.t()]
        }
  @type block :: markdown | cell

  @output_comment ~s(<!-- livebook:{"output":true} -->)
  @force_markdown ~s(<!-- livebook:{"force_markdown":true} -->)
  @elixir_fence ~r/^(`{3,})elixir\s*$/
  @plain_fence ~r/^(`{3,})\s*$/
  @any_fence ~r/^(`{3,})/
  @metadata_comment ~r/^<!-- livebook:\{.*\} -->\s*$/

  @doc "Parses a notebook into blocks."
  @spec parse(String.t()) :: [block]
  def parse(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> tokens([])
    |> group([])
  end

  @doc "Renders blocks back into a notebook."
  @spec render([block]) :: String.t()
  def render(blocks) do
    blocks
    |> Enum.flat_map(&block_lines/1)
    |> Enum.join("\n")
  end

  @doc "The Elixir cells of a parsed notebook, in order."
  @spec cells([block]) :: [cell]
  def cells(blocks), do: Enum.filter(blocks, &(&1.type == :cell))

  # -- tokenising --------------------------------------------------------

  defp tokens([], acc), do: Enum.reverse(acc)

  defp tokens([{@output_comment, _} | rest] = all, acc) do
    case take_output(rest) do
      {:ok, text, rest} -> tokens(rest, [{:output, text} | acc])
      :error -> markdown_line(all, acc)
    end
  end

  # A code sample inside a markdown cell. The comment and the blank lines
  # after it are markdown, and so is the fence that follows.
  defp tokens([{@force_markdown, _} | _] = all, acc) do
    {rest, acc} = markdown_through_blanks(all, acc)

    case rest do
      [{line, _} | _] ->
        if Regex.match?(@any_fence, line), do: fenced_markdown(rest, acc), else: tokens(rest, acc)

      [] ->
        tokens([], acc)
    end
  end

  defp tokens([{line, _} | rest] = all, acc) do
    cond do
      Regex.match?(@metadata_comment, line) and elixir_fence_after_blanks?(rest) ->
        {blanks, rest} = Enum.split_while(rest, fn {l, _} -> l == "" end)
        metadata = [line | Enum.map(blanks, &elem(&1, 0))]
        tokens_cell(rest, metadata, acc)

      Regex.match?(@elixir_fence, line) ->
        tokens_cell(all, [], acc)

      Regex.match?(@any_fence, line) ->
        fenced_markdown(all, acc)

      true ->
        markdown_line(all, acc)
    end
  end

  defp markdown_line([{line, _} | rest], acc), do: tokens(rest, [{:md, line} | acc])

  defp markdown_through_blanks([{line, _} | rest], acc) do
    {blanks, rest} = Enum.split_while(rest, fn {l, _} -> l == "" end)
    acc = Enum.reduce(blanks, [{:md, line} | acc], fn {l, _}, acc -> [{:md, l} | acc] end)
    {rest, acc}
  end

  defp elixir_fence_after_blanks?(lines) do
    case Enum.drop_while(lines, fn {l, _} -> l == "" end) do
      [{line, _} | _] -> Regex.match?(@elixir_fence, line)
      [] -> false
    end
  end

  defp tokens_cell([{open, n} | rest], metadata, acc) do
    [_, fence] = Regex.run(@elixir_fence, open)
    {body, rest} = take_until_fence(rest, fence)

    rest =
      case rest do
        [{_close, _} | rest] -> rest
        [] -> raise ArgumentError, "unterminated elixir cell opened on line #{n}"
      end

    cell = %{
      type: :cell,
      metadata: metadata,
      fence: fence,
      source_lines: body,
      source: Enum.join(body, "\n"),
      line: n + 1,
      outputs: []
    }

    tokens(rest, [{:cell, cell} | acc])
  end

  # A fenced block that is not a cell (mermaid, text, a bare fence, ...).
  # Everything through the closing fence is markdown.
  defp fenced_markdown([{open, _} | rest], acc) do
    [_, fence] = Regex.run(@any_fence, open)
    {body, rest} = take_until_fence(rest, fence)
    acc = Enum.reduce(body, [{:md, open} | acc], fn l, acc -> [{:md, l} | acc] end)

    case rest do
      [] -> tokens([], acc)
      [{close, _} | rest] -> tokens(rest, [{:md, close} | acc])
    end
  end

  defp take_output(lines) do
    {_blanks, rest} = Enum.split_while(lines, fn {l, _} -> l == "" end)

    with [{open, _} | rest] <- rest,
         [_, fence] <- Regex.run(@plain_fence, open),
         {body, [{_close, _} | rest]} <- take_until_fence(rest, fence) do
      {:ok, Enum.join(body, "\n"), rest}
    else
      _ -> :error
    end
  end

  # Returns `{body_lines, rest}` where `rest` starts with the closing
  # fence line, or is `[]` when the fence is never closed.
  defp take_until_fence(lines, fence) do
    {body, rest} = Enum.split_while(lines, fn {l, _} -> String.trim_trailing(l) != fence end)
    {Enum.map(body, &elem(&1, 0)), rest}
  end

  # -- grouping ------------------------------------------------------------

  defp group([], acc), do: Enum.reverse(acc)

  defp group([{:md, line} | rest], [%{type: :markdown, lines: lines} = md | acc]) do
    group(rest, [%{md | lines: lines ++ [line]} | acc])
  end

  defp group([{:md, line} | rest], acc) do
    group(rest, [%{type: :markdown, lines: [line]} | acc])
  end

  defp group([{:cell, cell} | rest], acc), do: group(rest, [cell | acc])

  defp group([{:output, text} | rest], acc) do
    case attach_output(acc, text) do
      {:ok, acc} -> group(rest, acc)
      :error -> group(rest, acc)
    end
  end

  # Attach to the preceding cell when only blank lines separate them. The
  # blank lines are dropped: `render/1` puts them back.
  defp attach_output([%{type: :markdown, lines: lines} | [%{type: :cell} | _] = acc], text) do
    if Enum.all?(lines, &(&1 == "")), do: attach_output(acc, text), else: :error
  end

  defp attach_output([%{type: :cell} = cell | acc], text) do
    {:ok, [%{cell | outputs: cell.outputs ++ [text]} | acc]}
  end

  defp attach_output(_acc, _text), do: :error

  # -- rendering -----------------------------------------------------------

  defp block_lines(%{type: :markdown, lines: lines}), do: lines

  defp block_lines(%{type: :cell} = cell) do
    cell.metadata ++
      [cell.fence <> "elixir"] ++
      cell.source_lines ++
      [cell.fence] ++
      output_lines(cell.outputs)
  end

  defp output_lines([]), do: []

  defp output_lines(outputs) do
    ["" | outputs |> Exhibit.Output.text_blocks() |> String.split("\n")]
  end
end
