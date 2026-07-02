defmodule FactoryMan.ExtendsTest.GrandparentFactory do
  use FactoryMan

  def grandparent_helper, do: "from grandparent"
end

defmodule FactoryMan.ExtendsTest.ParentFactory do
  use FactoryMan, extends: FactoryMan.ExtendsTest.GrandparentFactory

  def parent_helper, do: "from parent"
end

defmodule FactoryMan.ExtendsTest.ChildFactory do
  use FactoryMan, extends: FactoryMan.ExtendsTest.ParentFactory

  deffactory greeting(params \\ %{}) do
    base_params = %{parent: parent_helper(), grandparent: grandparent_helper()}

    Map.merge(base_params, params)
  end
end

defmodule FactoryMan.ExtendsTest do
  use ExUnit.Case, async: true

  alias FactoryMan.ExtendsTest.ChildFactory

  describe "helper function inheritance" do
    test "helpers are callable unqualified across the whole extends chain" do
      assert ChildFactory.build_greeting() == %{
               parent: "from parent",
               grandparent: "from grandparent"
             }
    end

    test "inherited helpers are importable but not re-exported" do
      refute function_exported?(ChildFactory, :parent_helper, 0)
    end
  end
end
