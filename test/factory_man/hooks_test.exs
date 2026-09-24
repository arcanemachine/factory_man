defmodule FactoryMan.HooksTest.Tracer do
  @moduledoc "Hook functions that report their tag to the calling process, then pass the value on."

  for tag <- [:grandparent, :parent, :child, :factory, :variant] do
    def unquote(tag)(value) do
      send(self(), {:hook, unquote(tag)})
      value
    end
  end

  def local_capture_hook, do: &trace/1

  defp trace(value), do: value
end

defmodule FactoryMan.HooksTest.Traced do
  defstruct [:name]
end

defmodule FactoryMan.HooksTest.GrandparentFactory do
  alias FactoryMan.HooksTest.Tracer

  use FactoryMan,
    repo: FactoryManDemo.Repo,
    hooks: [
      before_build_params: &Tracer.grandparent/1,
      after_build_params: &Tracer.grandparent/1,
      before_build_struct: &Tracer.grandparent/1,
      after_build_struct: &Tracer.grandparent/1,
      before_insert: &Tracer.grandparent/1,
      after_insert: &Tracer.grandparent/1
    ]
end

defmodule FactoryMan.HooksTest.ParentFactory do
  alias FactoryMan.HooksTest.Tracer

  use FactoryMan,
    extends: FactoryMan.HooksTest.GrandparentFactory,
    hooks: [
      before_build_params: &Tracer.parent/1,
      after_build_params: &Tracer.parent/1,
      before_build_struct: {&Tracer.parent/1, :before_parent},
      after_build_struct: {&Tracer.parent/1, :after_parent}
    ]
end

defmodule FactoryMan.HooksTest.ChildFactory do
  alias FactoryMan.HooksTest.{Traced, Tracer}
  alias FactoryManDemo.Users.User

  use FactoryMan,
    extends: FactoryMan.HooksTest.ParentFactory,
    hooks: [
      before_build_params: &Tracer.child/1,
      after_build_params: &Tracer.child/1
    ]

  deffactory plain(params \\ %{}),
    struct: Traced,
    hooks: [
      before_build_params: &Tracer.factory/1,
      after_build_params: &Tracer.factory/1,
      before_build_struct: &Tracer.factory/1,
      after_build_struct: &Tracer.factory/1
    ] do
    Map.merge(%{name: "plain"}, params)
  end

  deffactory event(params \\ %{}),
    hooks: [before_build_params: &Tracer.factory/1, after_build_params: &Tracer.factory/1] do
    Map.merge(%{name: "event"}, params)
  end

  deffactory placed(params \\ %{}),
    struct: Traced,
    hooks: [
      before_build_params: {&Tracer.factory/1, :before_parent},
      after_build_params: {&Tracer.factory/1, :after_parent}
    ] do
    Map.merge(%{name: "placed"}, params)
  end

  deffactory replaced(params \\ %{}),
    struct: Traced,
    hooks: [
      before_build_params: {&Tracer.factory/1, :replace_parent},
      after_build_params: {&Function.identity/1, :replace_parent}
    ] do
    Map.merge(%{name: "replaced"}, params)
  end

  deffactory whole_struct(params \\ %{}),
    struct: Traced,
    body: :struct,
    hooks: [after_build_struct: &Tracer.factory/1] do
    struct!(Traced, Map.merge(%{name: "whole"}, params))
  end

  deffactory user(params \\ %{}),
    struct: User,
    hooks: [before_insert: &Tracer.factory/1, after_insert: &Tracer.factory/1] do
    Map.merge(%{username: FactoryMan.sequence("hooks-user")}, params)
  end

  defvariant traced(params \\ %{}), for: :user do
    Map.merge(%{first_name: "Traced"}, params)
  end
end

defmodule FactoryMan.HooksTest.RootFactory do
  alias FactoryMan.HooksTest.Tracer

  use FactoryMan,
    hooks: [
      before_build_params: {&Tracer.grandparent/1, :replace_parent},
      after_build_params: {&Tracer.grandparent/1, :before_parent}
    ]
end

defmodule FactoryMan.HooksTest do
  use FactoryManDemo.DataCase

  alias FactoryMan.HooksTest.{ChildFactory, GrandparentFactory, RootFactory, Tracer}

  # Collects the hook tags reported so far, in the order the hooks ran
  defp flush_trace(trace \\ []) do
    receive do
      {:hook, tag} -> flush_trace([tag | trace])
    after
      0 -> Enum.reverse(trace)
    end
  end

  defp stage_trace(build_fun) do
    # Sanity check: no hook has run yet
    assert flush_trace() == []

    build_fun.()
    flush_trace()
  end

  describe "hook resolution" do
    test "plain before_* hooks run the parent's first, and plain after_* hooks run it last" do
      trace = stage_trace(&ChildFactory.build_plain_struct/0)

      assert trace == [
               # before_build_params
               :grandparent,
               :parent,
               :child,
               :factory,
               # after_build_params
               :factory,
               :child,
               :parent,
               :grandparent,
               # before_build_struct (the parent placed its hook :before_parent)
               :parent,
               :grandparent,
               :factory,
               # after_build_struct (the parent placed its hook :after_parent)
               :factory,
               :grandparent,
               :parent
             ]
    end

    test "a factory without struct: chains its params-stage hooks the same way" do
      assert stage_trace(&ChildFactory.build_event/0) == [
               # before_build_params
               :grandparent,
               :parent,
               :child,
               :factory,
               # after_build_params
               :factory,
               :child,
               :parent,
               :grandparent
             ]
    end

    test "explicit placements override the default for the hook name" do
      trace = stage_trace(&ChildFactory.build_placed_params/0)

      assert Enum.take(trace, 8) == [
               # before_build_params
               :factory,
               :grandparent,
               :parent,
               :child,
               # after_build_params
               :child,
               :parent,
               :grandparent,
               :factory
             ]
    end

    test ":replace_parent drops every inherited hook for that hook name" do
      assert stage_trace(&ChildFactory.build_replaced_struct/0) == [
               # before_build_params (replaced by the factory's hook)
               :factory,
               # after_build_params has been replaced by `Function.identity/1`
               # before_build_struct and after_build_struct (inherited)
               :parent,
               :grandparent,
               :grandparent,
               :parent
             ]
    end

    test "placements on a root module behave like a plain hook" do
      assert RootFactory.__factory_man__(:opts)[:hooks] == [
               before_build_params: [&Tracer.grandparent/1],
               after_build_params: [&Tracer.grandparent/1]
             ]
    end

    test "reflection shows each hook name's resolved list in run order" do
      hooks = ChildFactory.__factory_man__(:opts, :plain)[:hooks]

      assert hooks[:before_build_params] == [
               &Tracer.grandparent/1,
               &Tracer.parent/1,
               &Tracer.child/1,
               &Tracer.factory/1
             ]

      assert hooks[:after_build_params] == [
               &Tracer.factory/1,
               &Tracer.child/1,
               &Tracer.parent/1,
               &Tracer.grandparent/1
             ]
    end

    test "module-level reflection holds the module's resolved lists" do
      assert GrandparentFactory.__factory_man__(:opts)[:hooks][:after_insert] == [
               &Tracer.grandparent/1
             ]

      assert ChildFactory.__factory_man__(:opts)[:hooks][:before_build_params] == [
               &Tracer.grandparent/1,
               &Tracer.parent/1,
               &Tracer.child/1
             ]
    end
  end

  describe "generated functions" do
    test "body: :struct runs the whole after_build_struct list" do
      assert stage_trace(&ChildFactory.build_whole_struct_struct/0) == [
               :factory,
               :grandparent,
               :parent
             ]
    end

    test "insert_* runs the resolved insert hooks around the repo insert" do
      trace = stage_trace(&ChildFactory.insert_user/0)

      # The build stages run first, then before_insert and after_insert
      assert Enum.take(trace, -4) == [:grandparent, :factory, :factory, :grandparent]
    end

    test "insert_*_struct runs the same insert hooks" do
      user = ChildFactory.build_user_struct()
      flush_trace()

      assert stage_trace(fn -> ChildFactory.insert_user_struct(user) end) == [
               :grandparent,
               :factory,
               :factory,
               :grandparent
             ]
    end

    test "a variant runs its base factory's resolved hooks" do
      assert stage_trace(&ChildFactory.insert_traced_user/0) ==
               stage_trace(&ChildFactory.insert_user/0)
    end
  end

  describe "validation" do
    test "rejects a hooks value that is not a keyword list" do
      assert_raise ArgumentError, ~r/expected :hooks for use FactoryMan in .* keyword list/, fn ->
        defmodule NonKeywordHooks do
          use FactoryMan, hooks: [&Tracer.parent/1]
        end
      end
    end

    test "rejects unknown hook names" do
      assert_raise ArgumentError, ~r/unknown hooks \[:after_insrt\] for use FactoryMan/, fn ->
        defmodule UnknownHookName do
          use FactoryMan, hooks: [after_insrt: &Tracer.parent/1]
        end
      end
    end

    test "rejects a hook name set twice at one level" do
      assert_raise ArgumentError, ~r/duplicate hooks \[:after_insert\] for factory :event/, fn ->
        defmodule DuplicateHookName do
          use FactoryMan

          deffactory event(params \\ %{}),
            hooks: [after_insert: &Tracer.parent/1, after_insert: &Tracer.child/1] do
            params
          end
        end
      end
    end

    test "rejects anonymous functions and local captures" do
      assert_raise ArgumentError, ~r/invalid hook :before_insert for use FactoryMan/, fn ->
        defmodule AnonymousHook do
          use FactoryMan, hooks: [before_insert: fn value -> value end]
        end
      end

      assert_raise ArgumentError, ~r/invalid hook :before_insert for factory :event/, fn ->
        defmodule LocalCaptureHook do
          use FactoryMan

          deffactory event(params \\ %{}),
            hooks: [before_insert: FactoryMan.HooksTest.Tracer.local_capture_hook()] do
            params
          end
        end
      end
    end

    test "rejects functions that do not take one argument" do
      assert_raise ArgumentError, ~r/invalid hook :after_insert/, fn ->
        defmodule WrongArityHook do
          use FactoryMan, hooks: [after_insert: {&Map.put/3, :after_parent}]
        end
      end
    end

    test "rejects unknown placements" do
      assert_raise ArgumentError, ~r/invalid placement :after for hook :after_insert/, fn ->
        defmodule UnknownPlacement do
          use FactoryMan, hooks: [after_insert: {&Tracer.parent/1, :after}]
        end
      end
    end
  end
end
