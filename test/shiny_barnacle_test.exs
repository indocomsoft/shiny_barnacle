defmodule ShinyBarnacleTest do
  use ExUnit.Case
  doctest ShinyBarnacle

  test "greets the world" do
    assert ShinyBarnacle.hello() == :world
  end
end
