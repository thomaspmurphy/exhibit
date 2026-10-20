defmodule SampleApp do
  @moduledoc "A tiny module for exhibit's end-to-end tests."

  def greet(name), do: "Hello, #{name}!"

  def add(a, b), do: a + b

  def explode(value), do: Map.fetch!(%{}, value)
end
