defmodule FactoryMan.InsertTargetsTest.Item do
  defstruct [:name, :stored_in]
end

defmodule FactoryMan.InsertTargetsTest.Store do
  @moduledoc "Insert functions that report each call to the calling process."

  for store <- [:store, :search, :search_v2, :cache] do
    def unquote(:"#{store}!")(struct, opts) do
      send(self(), {:inserted, unquote(store), struct, opts})

      if Map.has_key?(struct, :stored_in), do: %{struct | stored_in: unquote(store)}, else: struct
    end
  end

  def one_arity(struct), do: struct

  def local_capture, do: &local/2

  defp local(struct, _opts), do: struct
end

defmodule FactoryMan.InsertTargetsTest.Tracer do
  @moduledoc "Hook functions that report their hook name to the calling process."

  for hook <- [:before_insert, :after_insert] do
    def unquote(hook)(value) do
      send(self(), {:hook, unquote(hook)})
      value
    end
  end
end

defmodule FactoryMan.InsertTargetsTest.BaseFactory do
  alias FactoryMan.InsertTargetsTest.Store

  use FactoryMan, repo: FactoryManDemo.Repo, insert_via: [search: &Store.search!/2]
end

defmodule FactoryMan.InsertTargetsTest.Factory do
  alias FactoryMan.InsertTargetsTest.{Item, Store, Tracer}
  alias FactoryManDemo.EmbeddedSchema
  alias FactoryManDemo.Users.User

  use FactoryMan,
    extends: FactoryMan.InsertTargetsTest.BaseFactory,
    hooks: [before_insert: &Tracer.before_insert/1, after_insert: &Tracer.after_insert/1]

  # A plain struct with a capture as its default target
  deffactory item(params \\ %{}), struct: Item, insert: &Store.store!/2 do
    Map.merge(%{name: "item"}, params)
  end

  # A plain struct with the inherited `:ecto` default, which cannot insert it
  deffactory cached_item(params \\ %{}), struct: Item, insert_via: [cache: &Store.cache!/2] do
    Map.merge(%{name: "cached item"}, params)
  end

  deffactory matched_item(%{name: _} = params),
    struct: Item,
    insert_via: [cache: &Store.cache!/2] do
    params
  end

  defvariant special(%{name: _} = params), for: :matched_item do
    Map.merge(%{stored_in: :nowhere}, params)
  end

  deffactory user(params \\ %{}), struct: User, insert_via: [search: &Store.search_v2!/2] do
    Map.merge(%{username: FactoryMan.sequence("insert-targets-user")}, params)
  end

  defvariant admin(params \\ %{}), for: :user do
    Map.merge(%{first_name: "Admin"}, params)
  end

  deffactory captured_user(params \\ %{}), struct: User, insert: &Store.store!/2 do
    Map.merge(%{username: FactoryMan.sequence("insert-targets-user")}, params)
  end

  deffactory offline_user(params \\ %{}), struct: User, insert: false do
    Map.merge(%{username: FactoryMan.sequence("insert-targets-user")}, params)
  end

  defvariant admin(params \\ %{}), for: :offline_user do
    Map.merge(%{first_name: "Admin"}, params)
  end

  deffactory hidden_user(params \\ %{}),
    struct: User,
    insert: false,
    insert_via: [search: false] do
    Map.merge(%{username: FactoryMan.sequence("insert-targets-user")}, params)
  end

  deffactory settings(params \\ %{}), struct: EmbeddedSchema, insert: &Store.store!/2 do
    Map.merge(%{some_field: "value"}, params)
  end

  deffactory payload(params \\ %{}) do
    params
  end
end

defmodule FactoryMan.InsertTargetsTest.CaptureFactory do
  alias FactoryMan.InsertTargetsTest.{Item, Store}
  alias FactoryManDemo.Users.User

  use FactoryMan, repo: FactoryManDemo.Repo, insert: &Store.store!/2

  deffactory item(params \\ %{}), struct: Item do
    Map.merge(%{name: "item"}, params)
  end

  deffactory user(params \\ %{}), struct: User, insert: :ecto do
    Map.merge(%{username: FactoryMan.sequence("insert-targets-user")}, params)
  end
end

defmodule FactoryMan.InsertTargetsTest do
  use FactoryManDemo.DataCase

  alias FactoryMan.InsertTargetsTest.{CaptureFactory, Factory, Item, Store}
  alias FactoryManDemo.EmbeddedSchema
  alias FactoryManDemo.Users.User

  defp compile_module!(source) do
    Code.compile_string("""
    defmodule FactoryMan.InsertTargetsTest.Compiled#{System.unique_integer([:positive])} do
      alias FactoryMan.InsertTargetsTest.{Item, Store}, warn: false
      alias FactoryManDemo.EmbeddedSchema, warn: false
      alias FactoryManDemo.Users.User, warn: false

    #{source}
    end
    """)
  end

  defp exported?(module, name, arity) do
    Code.ensure_loaded!(module)
    function_exported?(module, name, arity)
  end

  describe "insert: unset" do
    test "inserts with the repo" do
      user = Factory.insert_user()

      # Sanity check: the struct has been inserted
      assert user.__meta__.state == :loaded

      assert Repo.get!(User, user.id).username == user.username
    end

    test "runs the insert hooks around the repo insert" do
      Factory.insert_user()

      assert_received {:hook, :before_insert}
      assert_received {:hook, :after_insert}
    end
  end

  describe "insert: false" do
    test "generates no default family and keeps the build functions" do
      refute exported?(Factory, :insert_offline_user, 1)
      refute exported?(Factory, :insert_offline_user_list, 2)
      refute exported?(Factory, :insert_offline_user_struct, 1)

      assert %User{} = Factory.build_offline_user_struct()
    end

    test "keeps the insert_via: targets" do
      %User{username: username} = Factory.insert_offline_user_via_search()

      assert_received {:inserted, :search, %User{username: ^username}, []}
    end
  end

  describe "insert: with a capture" do
    test "calls the capture with the built struct and the caller's options" do
      assert %Item{name: "item", stored_in: :store} = Factory.insert_item(%{}, returning: true)

      assert_received {:inserted, :store, %Item{name: "item"}, [returning: true]}
    end

    test "leaves out variants: from the options passed to the capture" do
      Factory.insert_captured_user(%{}, variants: [], prefix: "other")

      assert_received {:inserted, :store, %User{}, [prefix: "other"]}
    end

    test "runs the insert hooks around the capture" do
      Factory.insert_item()

      assert_received {:hook, :before_insert}
      assert_received {:inserted, :store, _struct, _opts}
      assert_received {:hook, :after_insert}
    end

    test "inserts a struct that has already been inserted" do
      user = Factory.insert_user()

      # Sanity check: the struct has been inserted
      assert user.__meta__.state == :loaded

      assert ^user = Factory.insert_captured_user_struct(user)
    end

    test "generates the default family for an embedded schema" do
      assert %EmbeddedSchema{some_field: "value"} = Factory.insert_settings()

      assert_received {:inserted, :store, %EmbeddedSchema{}, []}
    end

    test "generates the list and struct forms" do
      count = Enum.random(1..3)

      assert items = Factory.insert_item_list(count, %{name: "listed"})
      assert length(items) == count
      assert Enum.all?(items, &match?(%Item{name: "listed", stored_in: :store}, &1))

      assert %Item{stored_in: :store} = Factory.insert_item_struct(%Item{name: "built"})
    end

    test "cascades from the module, and a factory's insert: :ecto switches back" do
      assert %Item{stored_in: :store} = CaptureFactory.insert_item()

      user = CaptureFactory.insert_user()

      assert user.__meta__.state == :loaded
      refute_received {:inserted, :store, %User{}, _opts}
    end
  end

  describe "insert: :ecto" do
    test "inherited, generates nothing for a struct that is not a table-backed Ecto schema" do
      refute exported?(Factory, :insert_cached_item, 1)
      refute exported?(Factory, :insert_cached_item_struct, 1)
    end

    test "written on a factory without a repo raises" do
      assert_raise ArgumentError,
                   ~r/factory :user in .* sets insert: :ecto, .* \(no repo is configured\)/,
                   fn ->
                     compile_module!("""
                     use FactoryMan

                     deffactory user(params \\\\ %{}), struct: User, insert: :ecto do
                       params
                     end
                     """)
                   end
    end

    test "written on a plain struct factory raises" do
      assert_raise ArgumentError, ~r/sets insert: :ecto, .* \(it is not an Ecto schema\)/, fn ->
        compile_module!("""
        use FactoryMan, repo: FactoryManDemo.Repo

        deffactory item(params \\\\ %{}), struct: Item, insert: :ecto do
          params
        end
        """)
      end
    end

    test "written on an embedded schema factory raises" do
      assert_raise ArgumentError, ~r/sets insert: :ecto, .* \(it is an embedded schema\)/, fn ->
        compile_module!("""
        use FactoryMan, repo: FactoryManDemo.Repo

        deffactory settings(params \\\\ %{}), struct: EmbeddedSchema, insert: :ecto do
          params
        end
        """)
      end
    end

    test "written on a module without a repo does not raise" do
      assert [{module, _binary}] =
               compile_module!("""
               use FactoryMan, insert: :ecto

               deffactory user(params \\\\ %{}), struct: User do
                 params
               end
               """)

      refute exported?(module, :insert_user, 1)
    end
  end

  describe "insert: validation" do
    for {label, value} <- [
          {"a value that is not allowed", "true"},
          {"an anonymous function", "fn struct, _opts -> struct end"},
          {"a local capture", "Store.local_capture()"},
          {"a capture of the wrong arity", "&Store.one_arity/1"}
        ] do
      test "raises on #{label}" do
        assert_raise ArgumentError, ~r/invalid :insert option for factory :item/, fn ->
          compile_module!("""
          use FactoryMan

          deffactory item(params \\\\ %{}), struct: Item, insert: #{unquote(value)} do
            params
          end
          """)
        end
      end
    end

    test "raises on a module-level value" do
      assert_raise ArgumentError, ~r/invalid :insert option for use FactoryMan in/, fn ->
        compile_module!("use FactoryMan, insert: true")
      end
    end

    test "raises when written on a non-struct factory" do
      assert_raise ArgumentError,
                   ~r/factory :payload in .* sets insert:, but only struct factories/,
                   fn ->
                     compile_module!("""
                     use FactoryMan

                     deffactory payload(params \\\\ %{}), insert: false do
                       params
                     end
                     """)
                   end
    end
  end

  describe "insert_via:" do
    test "generates the three families with their arities" do
      for {name, arities} <- [
            insert_item_via_search: [0, 1, 2],
            insert_item_via_search_list: [1, 2, 3],
            insert_item_struct_via_search: [1, 2]
          ],
          arity <- arities do
        assert exported?(Factory, name, arity), "expected #{name}/#{arity}"
      end
    end

    test "calls the target with the built struct and the caller's options, minus variants:" do
      Factory.insert_user_via_search(%{first_name: "Ada"}, variants: [:admin], refresh: true)

      assert_received {:inserted, :search_v2, %User{first_name: "Ada"}, [refresh: true]}
    end

    test "applies variants: to the built struct" do
      Factory.insert_user_via_search(%{}, variants: [:admin])

      assert_received {:inserted, :search_v2, %User{first_name: "Admin"}, []}
    end

    test "applies variants: in the list form" do
      count = Enum.random(1..3)

      Factory.insert_user_via_search_list(count, %{}, variants: [:admin])

      for _ <- 1..count do
        assert_received {:inserted, :search_v2, %User{first_name: "Admin"}, []}
      end
    end

    test "runs no insert hooks" do
      Factory.insert_user_via_search()

      assert_received {:inserted, :search_v2, _struct, _opts}
      refute_received {:hook, _hook}
    end

    test "inserts a struct that has already been inserted" do
      user = Factory.insert_user()

      assert ^user = Factory.insert_user_struct_via_search(user)
      assert_received {:inserted, :search_v2, ^user, []}
    end

    test "the struct form rejects variants:" do
      assert_raise ArgumentError,
                   ~r/insert_user_struct_via_search\/2 .* Use insert_user_via_search\/2/,
                   fn ->
                     Factory.insert_user_struct_via_search(%User{}, variants: [:admin])
                   end
    end

    test "merges across levels: adds, replaces by name, and false removes" do
      # The module-level target is inherited, and a factory adds its own
      assert Factory.__factory_man__(:opts, :cached_item)[:insert_via] == [
               search: &Store.search!/2,
               cache: &Store.cache!/2
             ]

      # A factory replaces the inherited target of the same name
      assert Factory.__factory_man__(:opts, :user)[:insert_via] == [search: &Store.search_v2!/2]

      # A factory removes the inherited target with `false`
      assert Factory.__factory_man__(:opts, :hidden_user)[:insert_via] == []
      refute exported?(Factory, :insert_hidden_user_via_search, 1)
    end

    test "is ignored when inherited by a non-struct factory" do
      refute exported?(Factory, :insert_payload_via_search, 1)
    end

    test "gates the convenience arities on a pattern-matched head" do
      refute exported?(Factory, :insert_matched_item_via_cache, 0)
      refute exported?(Factory, :insert_matched_item_via_cache_list, 1)

      assert %Item{name: "matched", stored_in: :cache} =
               Factory.insert_matched_item_via_cache(%{name: "matched"})
    end

    test "raises on the reserved name ecto" do
      assert_raise ArgumentError, ~r/insert_via: target :ecto .* is reserved/, fn ->
        compile_module!("use FactoryMan, insert_via: [ecto: &Store.search!/2]")
      end
    end

    test "raises on duplicate names at one level" do
      assert_raise ArgumentError, ~r/duplicate insert_via: targets \[:search\]/, fn ->
        compile_module!(
          "use FactoryMan, insert_via: [search: &Store.search!/2, search: &Store.cache!/2]"
        )
      end
    end

    test "raises on an invalid capture" do
      assert_raise ArgumentError, ~r/invalid insert_via: target :search for use FactoryMan/, fn ->
        compile_module!("use FactoryMan, insert_via: [search: &Store.one_arity/1]")
      end
    end

    test "raises on a value that is not a keyword list" do
      assert_raise ArgumentError,
                   ~r/expected :insert_via for use FactoryMan .* keyword list/,
                   fn ->
                     compile_module!("use FactoryMan, insert_via: &Store.search!/2")
                   end
    end

    test "raises when removing a target that is not inherited" do
      assert_raise ArgumentError,
                   ~r/factory :item .* removes insert target :serach, which does not exist\. Inherited targets: \[:search\]/,
                   fn ->
                     compile_module!("""
                     use FactoryMan, insert_via: [search: &Store.search!/2]

                     deffactory item(params \\\\ %{}), struct: Item, insert_via: [serach: false] do
                       params
                     end
                     """)
                   end
    end

    test "raises when written on a non-struct factory" do
      assert_raise ArgumentError, ~r/factory :payload .* sets insert_via:/, fn ->
        compile_module!("""
        use FactoryMan

        deffactory payload(params \\\\ %{}), insert_via: [search: &Store.search!/2] do
          params
        end
        """)
      end
    end
  end

  describe "variants" do
    test "get the base factory's default family and target families" do
      admin = Factory.insert_admin_user()

      assert admin.__meta__.state == :loaded
      assert admin.first_name == "Admin"

      Factory.insert_admin_user_via_search()

      assert_received {:inserted, :search_v2, %User{first_name: "Admin"}, []}
    end

    test "of a base with insert: false get the target families only" do
      refute exported?(Factory, :insert_admin_offline_user, 1)
      refute exported?(Factory, :insert_admin_offline_user_struct, 1)

      Factory.insert_admin_offline_user_via_search()

      assert_received {:inserted, :search, %User{first_name: "Admin"}, []}
    end

    test "delegate the struct form of a target to the base factory's" do
      Factory.insert_admin_user_struct_via_search(%User{username: "built"})

      assert_received {:inserted, :search_v2, %User{username: "built"}, []}
    end

    test "gate the target convenience arities on a pattern-matched head" do
      refute exported?(Factory, :insert_special_matched_item_via_cache, 0)

      assert %Item{name: "special", stored_in: :cache} =
               Factory.insert_special_matched_item_via_cache(%{name: "special"})
    end
  end

  describe "generated-name collisions" do
    test "raise for a variant and a factory with the same function names" do
      assert_raise ArgumentError,
                   ~r/variant :admin of :item and factory :admin_item in .* both generate build_admin_item_struct\/\d\. Rename one, or use as: on the variant\./,
                   fn ->
                     compile_module!("""
                     use FactoryMan

                     deffactory item(params \\\\ %{}), struct: Item do
                       params
                     end

                     defvariant admin(params \\\\ %{}), for: :item do
                       params
                     end

                     deffactory admin_item(params \\\\ %{}), struct: Item do
                       params
                     end
                     """)
                   end
    end

    test "raise for a target and a factory with the same function names" do
      assert_raise ArgumentError,
                   ~r/factory :item and factory :item_via_search in .* both generate insert_item_via_search\/\d\. Rename one\./,
                   fn ->
                     compile_module!("""
                     use FactoryMan, insert: &Store.store!/2

                     deffactory item(params \\\\ %{}), struct: Item, insert_via: [search: &Store.search!/2] do
                       params
                     end

                     deffactory item_via_search(params \\\\ %{}), struct: Item do
                       params
                     end
                     """)
                   end
    end

    test "raise for a hand-written function with an arity that a default argument adds" do
      assert_raise ArgumentError,
                   ~r/factory :item in .* generates insert_item\/0, which is already defined in the module/,
                   fn ->
                     compile_module!("""
                     use FactoryMan, insert: &Store.store!/2

                     def insert_item, do: nil

                     deffactory item(params \\\\ %{}), struct: Item do
                       params
                     end
                     """)
                   end
    end

    test "raise for a hand-written function with a generated name" do
      assert_raise ArgumentError,
                   ~r/factory :item in .* generates build_item_struct\/1, which is already defined in the module/,
                   fn ->
                     compile_module!("""
                     use FactoryMan

                     def build_item_struct(params), do: params

                     deffactory item(params), struct: Item do
                       params
                     end
                     """)
                   end
    end
  end

  describe "reflection" do
    test "shows the resolved insert: and insert_via:" do
      assert Factory.__factory_man__(:opts, :user)[:insert] == :ecto
      assert Factory.__factory_man__(:opts, :item)[:insert] == (&Store.store!/2)
      assert Factory.__factory_man__(:opts, :offline_user)[:insert] == false

      assert Factory.__factory_man__(:opts)[:insert_via] == [search: &Store.search!/2]

      assert Factory.__factory_man__(:opts, :admin_user)[:insert_via] == [
               search: &Store.search_v2!/2
             ]
    end
  end
end
