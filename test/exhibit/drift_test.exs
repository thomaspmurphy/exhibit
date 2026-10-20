defmodule Exhibit.DriftTest do
  use ExUnit.Case, async: true

  alias Exhibit.Runner

  @missing "** FILE NOT FOUND **"

  test "says nothing when the database matches the branch" do
    assert Runner.drift_message("app_test", [{:up, 1, "create_users"}]) == nil
    assert Runner.drift_message("app_test", []) == nil
  end

  test "names a database behind the branch and the migrate fix" do
    message = Runner.drift_message("app_test", [{:up, 1, "a"}, {:down, 2, "b"}, {:down, 3, "c"}])
    assert message =~ "app_test is behind this branch by 2 migration(s)"
    assert message =~ "mix ecto.migrate"
  end

  test "names a database migrated by another branch and the own-database fix" do
    message = Runner.drift_message("app_test", [{:up, 1, "a"}, {:up, 2, @missing}])
    assert message =~ "app_test is ahead of this branch by 1 migration(s)"
    assert message =~ "DB_DATABASE=<name> MIX_ENV=test mix ecto.setup"
  end

  test "reports both directions at once" do
    message = Runner.drift_message(nil, [{:down, 1, "a"}, {:up, 2, @missing}])
    assert message =~ "the database is behind this branch by 1 migration(s) and ahead by 1"
  end
end
