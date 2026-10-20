defmodule Exhibit.PrBody do
  @moduledoc """
  Converts a notebook into GitHub-flavoured markdown fit for a pull request
  description.

  Every `<!-- livebook:... -->` comment is dropped, along with the blank
  line that followed it. Headings, prose and non-Elixir fences (Mermaid
  included) pass through unchanged. Each Elixir cell stays an `elixir`
  fence, and its persisted outputs are rendered as a single `text` fence
  directly after it.
  """

  alias Exhibit.Output
  alias Exhibit.Parser

  @livebook_comment ~r/^<!-- livebook:.* -->\s*$/

  @doc "Converts notebook source into PR-body markdown."
  @spec convert(String.t()) :: String.t()
  def convert(source) do
    source
    |> Parser.parse()
    |> Enum.flat_map(&block_lines/1)
    |> Enum.join("\n")
    |> String.trim_leading("\n")
  end

  defp block_lines(%{type: :markdown, lines: lines}), do: drop_comments(lines)

  defp block_lines(%{type: :cell} = cell) do
    [cell.fence <> "elixir"] ++ cell.source_lines ++ [cell.fence] ++ output_lines(cell.outputs)
  end

  defp output_lines([]), do: []

  defp output_lines(outputs) do
    text = Enum.join(outputs, "\n")
    fence = Output.code_block_delimiter(text)
    ["", fence <> "text"] ++ String.split(text, "\n") ++ [fence]
  end

  defp drop_comments([comment, "" | rest]) when is_binary(comment) do
    if Regex.match?(@livebook_comment, comment),
      do: drop_comments(rest),
      else: [comment | drop_comments(["" | rest])]
  end

  defp drop_comments([line | rest]) do
    if Regex.match?(@livebook_comment, line),
      do: drop_comments(rest),
      else: [line | drop_comments(rest)]
  end

  defp drop_comments([]), do: []
end
