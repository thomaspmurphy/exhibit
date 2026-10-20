defmodule Exhibit.Output do
  @moduledoc """
  Serialises cell outputs the way Livebook persists them.

  Mirrors `Livebook.LiveMarkdown.Export`: each text output is an
  `<!-- livebook:{"output":true} -->` comment, a blank line, and a code
  fence whose delimiter is longer than any run of backticks in the body.
  ANSI escapes are stripped and one trailing newline is removed.
  """

  @output_comment ~s(<!-- livebook:{"output":true} -->)
  @persist_header ~s(<!-- livebook:{"persist_outputs":true} -->)

  @ansi ~r/\e\[[\d;?]*[ -\/]*[@-~]/

  @doc "The notebook-level comment that tells Livebook to keep outputs in the file."
  @spec persist_outputs_header() :: String.t()
  def persist_outputs_header, do: @persist_header

  @doc "The comment that introduces a persisted output."
  @spec output_comment() :: String.t()
  def output_comment, do: @output_comment

  @doc "Removes ANSI escape sequences."
  @spec strip_ansi(String.t()) :: String.t()
  def strip_ansi(text), do: Regex.replace(@ansi, text, "")

  @doc """
  A fence delimiter one backtick longer than the longest run of three or
  more backticks in `code`, and never shorter than three.
  """
  @spec code_block_delimiter(String.t()) :: String.t()
  def code_block_delimiter(code) do
    max_streak =
      ~r/`{3,}/
      |> Regex.scan(code)
      |> Enum.map(fn [run] -> byte_size(run) end)
      |> Enum.max(&>=/2, fn -> 2 end)

    String.duplicate("`", max_streak + 1)
  end

  @doc """
  Renders one terminal-text output as Livebook persists it. The returned
  string has no trailing newline.
  """
  @spec text_block(String.t()) :: String.t()
  def text_block(text) do
    text = text |> strip_ansi() |> String.replace_suffix("\n", "")
    delimiter = code_block_delimiter(text)
    Enum.join([@output_comment, "", delimiter, text, delimiter], "\n")
  end

  @doc "Renders a cell's outputs, separated by blank lines."
  @spec text_blocks([String.t()]) :: String.t()
  def text_blocks(texts), do: Enum.map_join(texts, "\n\n", &text_block/1)

  @doc """
  Makes sure the document opens with notebook metadata that sets
  `persist_outputs` to true, so Livebook keeps the outputs we wrote.
  """
  @spec ensure_persist_outputs(String.t()) :: String.t()
  def ensure_persist_outputs(doc) do
    case String.split(doc, "\n", parts: 2) do
      [first, rest] when first != @persist_header ->
        if notebook_metadata?(first) do
          enable_persist(first) <> "\n" <> rest
        else
          @persist_header <> "\n\n" <> doc
        end

      [first] when first != @persist_header ->
        @persist_header <> "\n\n" <> doc

      _ ->
        doc
    end
  end

  defp notebook_metadata?(line) do
    String.starts_with?(line, "<!-- livebook:{") and String.ends_with?(line, "} -->")
  end

  defp enable_persist(line) do
    cond do
      String.contains?(line, ~s("persist_outputs":true)) ->
        line

      String.contains?(line, ~s("persist_outputs":false)) ->
        String.replace(line, ~s("persist_outputs":false), ~s("persist_outputs":true))

      line == "<!-- livebook:{} -->" ->
        @persist_header

      true ->
        String.replace(line, "<!-- livebook:{", ~s(<!-- livebook:{"persist_outputs":true,),
          global: false
        )
    end
  end
end
