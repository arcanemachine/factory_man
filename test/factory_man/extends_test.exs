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

defmodule FactoryMan.ExtendsTest.HookParentFactory do
  use FactoryMan, hooks: [before_build_params: &__MODULE__.tag_before/1]

  def tag_before(params), do: Map.put(params, :before_hook, true)
end

defmodule FactoryMan.ExtendsTest.HookChildFactory do
  use FactoryMan,
    extends: FactoryMan.ExtendsTest.HookParentFactory,
    hooks: [after_build_params: &__MODULE__.tag_after/1]

  def tag_after(params), do: Map.put(params, :after_hook, true)

  deffactory event(params \\ %{}) do
    base_params = %{name: "event"}

    Map.merge(base_params, params)
  end
end

defmodule FactoryMan.ExtendsTest do
  use ExUnit.Case, async: true

  alias FactoryMan.ExtendsTest.ChildFactory
  alias FactoryMan.ExtendsTest.HookChildFactory

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

  describe "module-level hook inheritance" do
    test "hooks merge per hook key, so a child hook does not discard parent hooks" do
      assert HookChildFactory.build_event() == %{
               name: "event",
               before_hook: true,
               after_hook: true
             }
    end
  end
end
