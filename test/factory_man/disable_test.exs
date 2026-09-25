defmodule FactoryMan.DisableTest.Item do
  defstruct [:name]
end

defmodule FactoryMan.DisableTest.Store do
  @moduledoc "Insert functions for the insert-list tests."

  def store!(struct, _opts), do: struct
  def search!(struct, _opts), do: struct
end

defmodule FactoryMan.DisableTest.BaseFactory do
  use FactoryMan, disable: [string_params: true, non_struct_list: true]
end

defmodule FactoryMan.DisableTest.Factory do
  alias FactoryMan.DisableTest.{Item, Store}

  use FactoryMan,
    extends: FactoryMan.DisableTest.BaseFactory,
    insert: &Store.store!/2,
    insert_via: [search: &Store.search!/2]

  # Inherits the module's disabled families
  deffactory item(params \\ %{}), struct: Item do
    Map.merge(%{name: "item"}, params)
  end

  defvariant special(params \\ %{}), for: :item do
    Map.merge(%{name: "special"}, params)
  end

  # Enables the inherited string params again, and disables the atom-keyed params
  deffactory reverse_item(params \\ %{}),
    struct: Item,
    disable: [string_params: false, params: true] do
    Map.merge(%{name: "reverse"}, params)
  end

  deffactory listless_item(params \\ %{}),
    struct: Item,
    disable: [struct_list: true, params_list: true, insert_list: true] do
    Map.merge(%{name: "listless"}, params)
  end

  defvariant special(params \\ %{}), for: :listless_item do
    Map.merge(%{name: "special"}, params)
  end

  deffactory string_list_item(params \\ %{}),
    struct: Item,
    disable: [string_params: false, string_params_list: true] do
    Map.merge(%{name: "string list"}, params)
  end

  # Inherits `non_struct_list: true`
  deffactory payload(params \\ %{}) do
    params
  end

  defvariant loud(params \\ %{}), for: :payload do
    Map.put(params, :loud, true)
  end

  deffactory listed_payload(params \\ %{}), disable: [non_struct_list: false] do
    params
  end
end

defmodule FactoryMan.DisableTest do
  use ExUnit.Case, async: true

  alias FactoryMan.DisableTest.{Factory, Item}

  defp compile_module!(source) do
    Code.compile_string("""
    defmodule FactoryMan.DisableTest.Compiled#{System.unique_integer([:positive])} do
      alias FactoryMan.DisableTest.Item, warn: false

    #{source}
    end
    """)
  end

  defp exported?(module, name, arity) do
    Code.ensure_loaded!(module)
    function_exported?(module, name, arity)
  end

  defp exported_names(module, prefix) do
    Code.ensure_loaded!(module)

    for {name, arity} <- module.__info__(:functions),
        String.starts_with?(Atom.to_string(name), prefix),
        do: {name, arity}
  end

  describe "disable: string_params" do
    test "removes the string params family and its list" do
      assert exported_names(Factory, "build_item_string_params") == []
    end

    test "keeps the atom-keyed params family" do
      assert %{name: "item"} = Factory.build_item_params()
      assert [%{name: "item"}] = Factory.build_item_params_list(1)
    end

    test "applies to variants of the factory" do
      assert exported_names(Factory, "build_special_item_string_params") == []
      assert %{name: "special"} = Factory.build_special_item_params()
    end
  end

  describe "disable: params" do
    test "removes the atom-keyed family and keeps string params, which do not depend on it" do
      assert exported_names(Factory, "build_reverse_item_params") == []

      assert %{"name" => "reverse"} = Factory.build_reverse_item_string_params()
      assert %{"name" => "given"} = Factory.build_reverse_item_string_params(%{name: "given"})
      assert [%{"name" => "reverse"}] = Factory.build_reverse_item_string_params_list(1)
    end
  end

  describe "disable: with false" do
    test "enables an inherited family again" do
      assert %{"name" => "string list"} = Factory.build_string_list_item_string_params()
    end

    test "is a no-op for a family that is not disabled" do
      [{module, _binary}] =
        compile_module!("""
        use FactoryMan

        deffactory item(params \\\\ %{}), struct: Item, disable: [params: false] do
          params
        end
        """)

      assert module.__factory_man__(:opts, :item)[:disable] == []
      assert exported?(module, :build_item_params, 1)
    end
  end

  describe "disable: list keys" do
    test "struct_list, params_list, and insert_list remove their lists only" do
      refute exported?(Factory, :build_listless_item_struct_list, 1)
      refute exported?(Factory, :build_listless_item_params_list, 1)
      refute exported?(Factory, :insert_listless_item_list, 1)

      assert %Item{} = Factory.build_listless_item_struct()
      assert %{name: "listless"} = Factory.build_listless_item_params()
      assert %Item{} = Factory.insert_listless_item()
    end

    test "insert_list also removes the insert_via: target lists" do
      refute exported?(Factory, :insert_listless_item_via_search_list, 1)

      assert %Item{} = Factory.insert_listless_item_via_search()
    end

    test "apply to variants of the factory" do
      refute exported?(Factory, :build_special_listless_item_struct_list, 1)
      refute exported?(Factory, :insert_special_listless_item_list, 1)
      refute exported?(Factory, :insert_special_listless_item_via_search_list, 1)

      assert %Item{name: "special"} = Factory.insert_special_listless_item()
    end

    test "string_params_list removes the string params list only" do
      refute exported?(Factory, :build_string_list_item_string_params_list, 2)

      assert exported?(Factory, :build_string_list_item_string_params, 1)
    end

    test "non_struct_list removes a non-struct factory's list and its variants' lists" do
      refute exported?(Factory, :build_payload_list, 1)
      refute exported?(Factory, :build_loud_payload_list, 1)

      assert %{loud: true} = Factory.build_loud_payload()
    end

    test "non_struct_list: false enables an inherited non-struct list again" do
      assert [%{}, %{}] = Factory.build_listed_payload_list(2)
    end

    test "an inherited key for the other kind of factory is ignored" do
      # Sanity check: the module disables `string_params` and `non_struct_list`
      assert Factory.__factory_man__(:opts)[:disable] == [
               string_params: true,
               non_struct_list: true
             ]

      assert exported?(Factory, :build_item_struct_list, 1)
      assert exported?(Factory, :build_payload, 1)
    end
  end

  describe "reflection" do
    test "shows only the disabled families, in a fixed order" do
      assert Factory.__factory_man__(:opts, :item)[:disable] == [
               string_params: true,
               non_struct_list: true
             ]

      assert Factory.__factory_man__(:opts, :reverse_item)[:disable] == [
               params: true,
               non_struct_list: true
             ]

      assert Factory.__factory_man__(:opts, :special_item)[:disable] ==
               Factory.__factory_man__(:opts, :item)[:disable]
    end

    test "is an empty list by default" do
      [{module, _binary}] = compile_module!("use FactoryMan")

      assert module.__factory_man__(:opts)[:disable] == []
    end
  end

  describe "generated-name collisions" do
    test "a disabled function's name is free for a hand-written function" do
      [{module, _binary}] =
        compile_module!("""
        use FactoryMan

        def build_item_string_params(params), do: {:hand_written, params}

        deffactory item(params \\\\ %{}), struct: Item, disable: [string_params: true] do
          params
        end
        """)

      assert module.build_item_string_params(%{}) == {:hand_written, %{}}
    end

    test "the enabled families still claim their names" do
      assert_raise ArgumentError,
                   ~r/factory :item in .* generates build_item_params\/1, which is already defined/,
                   fn ->
                     compile_module!("""
                     use FactoryMan

                     def build_item_params(params), do: params

                     deffactory item(params \\\\ %{}), struct: Item, disable: [string_params: true] do
                       params
                     end
                     """)
                   end
    end
  end

  describe "validation" do
    test "raises on an unknown key" do
      assert_raise ArgumentError, ~r/unknown disable: key :strng_params for use FactoryMan/, fn ->
        compile_module!("use FactoryMan, disable: [strng_params: true]")
      end
    end

    test "raises on a value that is not a boolean" do
      assert_raise ArgumentError, ~r/invalid disable: value for :params for factory :item/, fn ->
        compile_module!("""
        use FactoryMan

        deffactory item(params \\\\ %{}), struct: Item, disable: [params: :yes] do
          params
        end
        """)
      end
    end

    test "raises on a value that is not a keyword list" do
      assert_raise ArgumentError, ~r/expected :disable for use FactoryMan .* keyword list/, fn ->
        compile_module!("use FactoryMan, disable: [:params]")
      end
    end

    test "raises on the struct family, which every other family builds on" do
      assert_raise ArgumentError,
                   ~r/invalid disable: key :struct .* builds on build_\*_struct/,
                   fn ->
                     compile_module!("use FactoryMan, disable: [struct: true]")
                   end
    end

    test "raises on inserts, which insert: switches off" do
      assert_raise ArgumentError, ~r/invalid disable: key :insert .* insert: false/, fn ->
        compile_module!("use FactoryMan, disable: [insert: true]")
      end
    end

    for value <- [true, false] do
      test "raises on a struct key written on a non-struct factory (#{value})" do
        assert_raise ArgumentError,
                     ~r/factory :payload in .* sets disable: \[:params\], which only struct factories have/,
                     fn ->
                       compile_module!("""
                       use FactoryMan

                       deffactory payload(params \\\\ %{}), disable: [params: #{unquote(value)}] do
                         params
                       end
                       """)
                     end
      end

      test "raises on non_struct_list written on a struct factory (#{value})" do
        assert_raise ArgumentError,
                     ~r/factory :item in .* sets disable: \[:non_struct_list\], which only non-struct factories have/,
                     fn ->
                       compile_module!("""
                       use FactoryMan

                       deffactory item(params \\\\ %{}), struct: Item,
                         disable: [non_struct_list: #{unquote(value)}] do
                         params
                       end
                       """)
                     end
      end
    end

    test "is an unknown option on defvariant" do
      assert_raise ArgumentError, ~r/unknown options \[:disable\] for defvariant special/, fn ->
        compile_module!("""
        use FactoryMan

        deffactory item(params \\\\ %{}), struct: Item do
          params
        end

        defvariant special(params \\\\ %{}), for: :item, disable: [params: true] do
          params
        end
        """)
      end
    end
  end
end
