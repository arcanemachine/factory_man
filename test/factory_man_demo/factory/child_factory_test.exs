defmodule FactoryManDemo.Factory.ChildFactoryTest do
  use FactoryManDemo.DataCase

  alias FactoryManDemo.Factory.ChildFactory
  alias FactoryManDemo.Authors.Author
  alias FactoryManDemo.Users.User

  # ── build_*_params ───────────────────────────────────────────────

  describe "build_*_params" do
    test "returns a plain map with default values" do
      params = ChildFactory.build_user_params()

      assert is_map(params)
      refute Map.has_key?(params, :__struct__)
      assert is_binary(params.username)
    end

    test "caller params override defaults" do
      params = ChildFactory.build_user_params(%{username: "alice"})

      assert params.username == "alice"
    end

    test "non-struct factory returns a plain map" do
      params = ChildFactory.build_non_struct()

      assert is_map(params)
      refute Map.has_key?(params, :__struct__)
      assert is_binary(params.name)
      assert is_integer(params.age)
    end
  end

  # ── build_*_struct ───────────────────────────────────────────────

  describe "build_*_struct" do
    test "returns an unpersisted struct with defaults" do
      user = ChildFactory.build_user_struct()

      assert %User{id: nil} = user
      assert is_binary(user.username)
    end

    test "caller params override defaults" do
      user = ChildFactory.build_user_struct(%{username: "bob"})

      assert user.username == "bob"
    end

    test "embedded schema builds struct without insert functions" do
      embedded = ChildFactory.build_embedded_schema_struct()

      assert %FactoryManDemo.EmbeddedSchema{} = embedded
      assert embedded.some_field == "some value"
      refute function_exported?(ChildFactory, :insert_embedded_schema, 0)
    end
  end

  # ── insert_* ────────────────────────────────────────────────────

  describe "insert_*" do
    test "inserts with defaults and returns a persisted struct" do
      user = ChildFactory.insert_user()

      assert %User{} = user
      assert is_integer(user.id)
    end

    test "caller params override defaults" do
      user = ChildFactory.insert_user(%{username: "charlie-#{System.os_time()}"})

      assert is_integer(user.id)
      assert String.starts_with?(user.username, "charlie-")
    end

    test "accepts repo options as second argument" do
      user =
        ChildFactory.insert_user(%{username: "repo-opts-#{System.os_time()}"}, returning: true)

      assert is_integer(user.id)
    end

    test "repo options can handle conflicts" do
      username = "conflict-#{System.os_time()}"
      ChildFactory.insert_user(%{username: username})

      # Duplicate insert with on_conflict: :nothing should not raise
      ChildFactory.insert_user(%{username: username}, on_conflict: :nothing)
    end

    test "multiple inserts produce unique records" do
      user1 = ChildFactory.insert_user()
      user2 = ChildFactory.insert_user()

      assert user1.id != user2.id
    end
  end

  # ── Associations ─────────────────────────────────────────────────

  describe "associations" do
    test "factory auto-builds associated records" do
      author = ChildFactory.build_author_struct()

      assert %Author{} = author
      assert %User{} = author.user
    end

    test "caller can provide a pre-built association" do
      user = ChildFactory.build_user_struct(%{username: "provided-user"})
      author = ChildFactory.build_author_struct(%{user: user})

      assert author.user.username == "provided-user"
    end

    test "inserted association is persisted and preloadable" do
      user = ChildFactory.insert_user(%{username: "assoc-user-#{System.os_time()}"})
      author = ChildFactory.insert_author(%{user: user})

      assert is_integer(author.user_id)
      loaded_author = Repo.preload(author, :user)
      assert loaded_author.user.id == user.id
    end

    test "inserting a factory auto-inserts its associations" do
      author = ChildFactory.insert_author()

      assert is_integer(author.user_id)
      loaded_author = Repo.preload(author, :user)
      assert %User{} = loaded_author.user
    end
  end

  # ── Factory composition ──────────────────────────────────────────

  describe "factory composition" do
    test "extended factory builds on another factory's params" do
      user = ChildFactory.build_extended_user_struct()

      assert %User{} = user
      assert String.starts_with?(user.username, "extended-user-")
    end

    test "extended factory accepts custom params" do
      user = ChildFactory.build_extended_user_struct(%{username: "custom"})

      assert user.username == "custom"
    end

    test "extended factory can be inserted" do
      user = ChildFactory.insert_extended_user()

      assert is_integer(user.id)
      assert String.starts_with?(user.username, "extended-user-")
    end
  end

  # ── List functions ───────────────────────────────────────────────

  describe "list functions" do
    test "build_*_params_list returns unique params for each item" do
      params_list = ChildFactory.build_user_params_list(3)

      assert length(params_list) == 3
      usernames = Enum.map(params_list, & &1.username)
      assert length(Enum.uniq(usernames)) == 3
    end

    test "build_*_params_list applies custom params to each item" do
      params_list = ChildFactory.build_user_params_list(2, %{username: "same"})

      assert Enum.all?(params_list, &(&1.username == "same"))
    end

    test "build_*_struct_list returns unpersisted structs" do
      structs = ChildFactory.build_user_struct_list(3)

      assert length(structs) == 3
      assert Enum.all?(structs, &match?(%User{id: nil}, &1))
      usernames = Enum.map(structs, & &1.username)
      assert length(Enum.uniq(usernames)) == 3
    end

    test "insert_*_list returns persisted records" do
      users = ChildFactory.insert_user_list(3)

      assert length(users) == 3
      assert Enum.all?(users, &is_integer(&1.id))
      usernames = Enum.map(users, & &1.username)
      assert length(Enum.uniq(usernames)) == 3
    end

    test "insert_*_list accepts params" do
      users =
        ChildFactory.insert_user_list(2, %{
          username: fn -> "list-#{System.os_time()}" end
        })

      assert length(users) == 2
      assert Enum.all?(users, &String.starts_with?(&1.username, "list-"))
    end

    test "insert_*_list accepts repo opts as keyword list" do
      users = ChildFactory.insert_user_list(2, returning: true)

      assert length(users) == 2
      assert Enum.all?(users, &is_integer(&1.id))
    end

    test "insert_*_list accepts both params and repo opts" do
      users = ChildFactory.insert_user_list(2, %{}, returning: true)

      assert length(users) == 2
      assert Enum.all?(users, &is_integer(&1.id))
    end

    test "count 0 returns an empty list" do
      assert [] = ChildFactory.build_user_params_list(0)
      assert [] = ChildFactory.build_user_struct_list(0)
      assert [] = ChildFactory.insert_user_list(0)
    end

    test "list works with non-struct factories" do
      result = ChildFactory.build_non_struct_list(3)

      assert length(result) == 3
      assert Enum.all?(result, &(is_map(&1) and not Map.has_key?(&1, :__struct__)))
    end

    test "list inserts with associations create unique associated records" do
      authors = ChildFactory.insert_author_list(2)

      assert length(authors) == 2
      loaded = Enum.map(authors, &Repo.preload(&1, :user))
      user_ids = Enum.map(loaded, & &1.user.id)
      assert length(Enum.uniq(user_ids)) == 2
    end

    test "params_list preserves all caller-provided keys" do
      result =
        ChildFactory.build_user_params_list(1, %{
          username: "test",
          first_name: "John",
          extra: "value"
        })

      assert [%{username: "test", first_name: "John", extra: "value"}] = result
    end
  end

  # ── Lazy evaluation ──────────────────────────────────────────────

  describe "lazy evaluation" do
    test "0-arity lazy functions are evaluated at build time" do
      params = ChildFactory.build_lazy_user_params()

      assert %DateTime{} = params.created_at
      refute is_function(params.created_at)
    end

    test "0-arity lazy functions produce fresh values on each call" do
      params1 = ChildFactory.build_lazy_user_params()
      :timer.sleep(10)
      params2 = ChildFactory.build_lazy_user_params()

      refute params1.created_at == params2.created_at
    end

    test "1-arity lazy functions receive the parent map" do
      params = ChildFactory.build_lazy_user_params(%{first_name: "John"})

      assert params.full_name == "John Userson"
    end

    test "lazy values can be overridden with regular values" do
      fixed_time = DateTime.utc_now() |> DateTime.truncate(:second)
      params = ChildFactory.build_lazy_user_params(%{created_at: fixed_time})

      assert params.created_at == fixed_time
    end

    test "lazy associations are built as structs, not functions" do
      author = ChildFactory.build_lazy_author_struct()

      assert %User{} = author.user
      refute is_function(author.user)
    end

    test "lazy associations are unique per call" do
      author1 = ChildFactory.build_lazy_author_struct()
      author2 = ChildFactory.build_lazy_author_struct()

      refute author1.user.username == author2.user.username
    end

    test "lazy evaluation works through insert" do
      author = ChildFactory.insert_lazy_author()

      assert is_integer(author.id)
      loaded = Repo.preload(author, :user)
      assert %User{} = loaded.user
      assert is_integer(loaded.user.id)
    end

    test "list functions evaluate lazy values independently per item" do
      params_list = ChildFactory.build_lazy_user_params_list(3)

      timestamps = Enum.map(params_list, & &1.created_at)
      assert length(Enum.uniq(timestamps)) == 3
    end
  end

  # ── Sequences ────────────────────────────────────────────────────

  describe "sequences" do
    test "generates unique sequential values" do
      user1 = ChildFactory.build_user_sequence_struct()
      user2 = ChildFactory.build_user_sequence_struct()

      assert user1.username != user2.username
      assert String.starts_with?(user1.username, "user-")
      assert String.starts_with?(user2.username, "user-")
    end

    test "circular sequence cycles through values" do
      FactoryMan.Sequence.reset()
      user1 = ChildFactory.build_user_with_role_struct()
      user2 = ChildFactory.build_user_with_role_struct()
      user3 = ChildFactory.build_user_with_role_struct()
      user4 = ChildFactory.build_user_with_role_struct()

      assert String.ends_with?(user1.username, "-admin")
      assert String.ends_with?(user2.username, "-user")
      assert String.ends_with?(user3.username, "-guest")
      assert String.ends_with?(user4.username, "-admin")
    end

    test "reset restarts sequence counters" do
      ChildFactory.build_user_with_role_struct()
      ChildFactory.build_user_with_role_struct()

      FactoryMan.Sequence.reset()

      user = ChildFactory.build_user_with_role_struct()
      assert String.ends_with?(user.username, "-admin")
    end
  end

  # ── Factory options ──────────────────────────────────────────────

  describe "factory options" do
    test "insert?: false prevents insert function generation" do
      assert function_exported?(ChildFactory, :build_non_insertable_params, 0)
      assert function_exported?(ChildFactory, :build_non_insertable_struct, 0)
      refute function_exported?(ChildFactory, :insert_non_insertable, 0)
    end

    test "build_params?: false skips params builder generation" do
      assert function_exported?(ChildFactory, :build_raw_user_struct, 0)
      assert function_exported?(ChildFactory, :build_raw_user_struct, 1)
      refute function_exported?(ChildFactory, :build_raw_user_params, 0)
      refute function_exported?(ChildFactory, :build_raw_user_params, 1)
      refute function_exported?(ChildFactory, :build_raw_user_params_list, 1)
      refute function_exported?(ChildFactory, :build_raw_user_params_list, 2)
    end

    test "build_params?: false factory body returns struct directly" do
      user = ChildFactory.build_raw_user_struct()
      assert %User{} = user
      assert String.starts_with?(user.username, "raw-user-")
    end

    test "build_params?: false factory accepts caller overrides" do
      user = ChildFactory.build_raw_user_struct(%{username: "custom"})
      assert user.username == "custom"
    end

    test "build_params?: false is a no-op for non-struct factories" do
      [{mod, _}] =
        Code.compile_string("""
        defmodule TestBuildParamsFalseNoStruct do
          use FactoryMan

          deffactory thing(params \\\\ %{}), build_params?: false do
            Map.merge(%{name: "hello"}, params)
          end
        end
        """)

      assert mod.build_thing() == %{name: "hello"}
      assert mod.build_thing(%{name: "world"}) == %{name: "world"}
    end

    test "module-level build_params?: false works with mixed struct and non-struct factories" do
      [{mod, _}] =
        Code.compile_string("""
        defmodule TestMixedBuildParamsFalse do
          use FactoryMan, build_params?: false

          deffactory plain(params \\\\ %{}) do
            Map.merge(%{name: "plain"}, params)
          end

          deffactory raw(params \\\\ %{}), struct: FactoryManDemo.Users.User do
            username = Map.get(params, :username, "raw")
            %FactoryManDemo.Users.User{username: username}
          end
        end
        """)

      # Non-struct factory generates build_* as normal
      assert mod.build_plain() == %{name: "plain"}

      # Struct factory with build_params?: false has no params builder
      refute function_exported?(mod, :build_raw_params, 0)

      # But does have struct builder
      assert %FactoryManDemo.Users.User{username: "raw"} = mod.build_raw_struct()
    end

    test "hooks transform factory output" do
      params = ChildFactory.build_hooked()

      assert params.hook_applied == true
      assert is_binary(params.name)
    end
  end

  # ── Parameter patterns ───────────────────────────────────────────

  describe "parameter patterns" do
    test "required params — no 0-arity function exists" do
      assert_raise UndefinedFunctionError, fn ->
        apply(ChildFactory, :build_simple_required_params, [])
      end

      params = ChildFactory.build_simple_required_params(%{username: "test"})
      assert params.username == "test"
    end

    test "pattern match without default — requires specific keys" do
      assert_raise UndefinedFunctionError, fn ->
        apply(ChildFactory, :build_no_default_fallback_params, [])
      end

      assert_raise FunctionClauseError, fn ->
        apply(ChildFactory, :build_no_default_fallback_params, [%{other: "data"}])
      end

      params = ChildFactory.build_no_default_fallback_params(%{username: "test"})
      assert params.username == "test"
    end

    test "pattern match with default — works with and without params" do
      user = ChildFactory.build_combined_pattern_struct()
      assert user.full_name == "Default User"

      user = ChildFactory.build_combined_pattern_struct(%{first_name: "Alice"})
      assert user.full_name == "Alice User"
    end

    test "pattern match with default can be inserted" do
      user = ChildFactory.insert_combined_pattern(%{first_name: "Bob"})

      assert is_integer(user.id)
      assert user.full_name == "Bob User"
    end

    test "nested pattern match extracts deeply nested values" do
      params = ChildFactory.build_nested_pattern_params(%{author: %{name: "John"}})
      assert params.username == "author-john"
    end

    test "nested pattern raises on non-matching input" do
      assert_raise FunctionClauseError, fn ->
        apply(ChildFactory, :build_nested_pattern_params, [%{other: "data"}])
      end
    end

    test "deep nested pattern match works with multiple levels" do
      params = ChildFactory.build_deep_nested_params(%{config: %{nested: %{value: "test123"}}})
      assert params.username == "deep-test123"
    end
  end

  # ── Variants ────────────────────────────────────────────────────

  describe "defvariant" do
    test "variant generates params that delegate to base factory" do
      params = ChildFactory.build_admin_user_params()
      assert is_map(params)
      assert String.starts_with?(params.username, "admin-")
    end

    test "variant generates struct that delegate to base factory" do
      user = ChildFactory.build_admin_user_struct()
      assert %User{} = user
      assert String.starts_with?(user.username, "admin-")
    end

    test "variant caller params are passed through" do
      user = ChildFactory.build_guest_user_struct(%{first_name: "Custom"})
      assert user.username == "guest"
      assert user.first_name == "Custom"
    end

    test "variant insert delegates to base factory insert pipeline" do
      user = ChildFactory.insert_admin_user()
      assert %User{} = user
      assert user.id != nil
      assert String.starts_with?(user.username, "admin-")
    end

    test "variant list functions work" do
      users = ChildFactory.build_admin_user_struct_list(3)
      assert length(users) == 3
      assert Enum.all?(users, &match?(%User{}, &1))
    end

    test "variant with :as option customizes the generated function name" do
      # The moderator variant uses `as: :mod`, so functions are named `*_mod_*` not `*_moderator_user_*`
      mod = ChildFactory.build_mod_struct()
      assert %User{} = mod
      assert String.starts_with?(mod.username, "mod-")

      # The default name should not exist
      refute function_exported?(ChildFactory, :build_moderator_user_struct, 0)
    end

    test "variant of a non-struct factory transforms the base factory's input" do
      assert ChildFactory.build_loud_greeting() == "Hello, WORLD!"
      assert ChildFactory.build_loud_greeting("alice") == "Hello, ALICE!"
    end

    test "variant list builder of a non-struct factory uses the actual default argument" do
      # Regression: previously the 1-arity list convenience passed %{} instead of
      # using the factory's default, crashing variants with non-map defaults.
      assert ChildFactory.build_loud_greeting_list(2) == [
               "Hello, WORLD!",
               "Hello, WORLD!"
             ]
    end

    test "variant without base factory raises at compile time" do
      assert_raise ArgumentError,
                   ~r/base factory :nonexistent not found/,
                   fn ->
                     Code.compile_string("""
                     defmodule TestVariantNoBase do
                       use FactoryMan

                       defvariant broken(params \\\\ %{}), for: :nonexistent do
                         params
                       end
                     end
                     """)
                   end
    end
  end

  # ── Error handling ───────────────────────────────────────────────

  describe "error handling" do
    test "factory with multiple arguments raises a helpful error" do
      assert_raise ArgumentError,
                   ~r/Invalid factory definition: expected exactly one argument/,
                   fn ->
                     Code.compile_string("""
                     defmodule TestMultiArg do
                       use FactoryMan

                       deffactory multi(a, b), struct: String do
                         %{}
                       end
                     end
                     """)
                   end
    end
  end

  # ── __using__/1 duplicate option warning ───────────────────────

  describe "__using__/1 duplicate option warning" do
    import ExUnit.CaptureLog

    test "warns when child module specifies the same option as parent" do
      log =
        capture_log(fn ->
          Code.compile_string("""
          defmodule DupModParent do
            use FactoryMan, repo: SomeRepo
          end

          defmodule DupModChild do
            use FactoryMan, extends: DupModParent, repo: SomeRepo
          end
          """)
        end)

      assert log =~ "FactoryMan: duplicate option"
      assert log =~ ":repo"
      assert log =~ "suppress_duplicate_option_warning"
    end

    test "does not warn when child overrides with a different value" do
      log =
        capture_log(fn ->
          Code.compile_string("""
          defmodule DiffValParent do
            use FactoryMan, repo: RepoA
          end

          defmodule DiffValChild do
            use FactoryMan, extends: DiffValParent, repo: RepoB
          end
          """)
        end)

      refute log =~ "FactoryMan: duplicate option"
    end

    test "does not warn when child specifies a new option not in parent" do
      log =
        capture_log(fn ->
          Code.compile_string("""
          defmodule NewOptParent do
            use FactoryMan, repo: SomeRepo
          end

          defmodule NewOptChild do
            use FactoryMan, extends: NewOptParent, build_params?: false
          end
          """)
        end)

      refute log =~ "FactoryMan: duplicate option"
    end

    test "suppresses warning with suppress_duplicate_option_warning: true" do
      log =
        capture_log(fn ->
          Code.compile_string("""
          defmodule SuppParent do
            use FactoryMan, repo: SomeRepo
          end

          defmodule SuppChild do
            use FactoryMan,
              extends: SuppParent,
              repo: SomeRepo,
              suppress_duplicate_option_warning: true
          end
          """)
        end)

      refute log =~ "FactoryMan: duplicate option"
    end

    test "suppress_duplicate_option_warning does not propagate to grandchildren" do
      log =
        capture_log(fn ->
          Code.compile_string("""
          defmodule PropParent do
            use FactoryMan, repo: SomeRepo
          end

          defmodule PropChild do
            use FactoryMan,
              extends: PropParent,
              repo: SomeRepo,
              suppress_duplicate_option_warning: true
          end

          defmodule PropGrandchild do
            use FactoryMan, extends: PropChild, repo: SomeRepo
          end
          """)
        end)

      assert log =~ "FactoryMan: duplicate option"
      assert log =~ "PropGrandchild"
    end
  end

  # ── Value factories (arbitrary return types) ─────────────────────

  describe "value factories" do
    test "returns a string" do
      assert ChildFactory.build_greeting() == "Hello, world!"
    end

    test "accepts a custom argument" do
      assert ChildFactory.build_greeting("Alice") == "Hello, Alice!"
    end

    test "returns nil" do
      assert ChildFactory.build_nothing() == nil
    end

    test "returns a tuple" do
      assert ChildFactory.build_pair() == {:a, :b}
      assert ChildFactory.build_pair({:x, :y}) == {:x, :y}
    end

    test "returns a list" do
      assert ChildFactory.build_tag_list() == ["tag-1", "tag-2", "tag-3"]
      assert ChildFactory.build_tag_list("item") == ["item-1", "item-2", "item-3"]
    end

    test "returns a keyword list" do
      assert ChildFactory.build_options() == [timeout: 5000, retries: 3]
      assert ChildFactory.build_options(retries: 10) == [timeout: 5000, retries: 10]
    end

    test "works with sequences" do
      email1 = ChildFactory.build_unique_email()
      email2 = ChildFactory.build_unique_email()

      assert email1 =~ ~r/user\d+@example\.com/
      assert email2 =~ ~r/user\d+@example\.com/
      assert email1 != email2
    end

    test "list builder works with default" do
      results = ChildFactory.build_greeting_list(3)

      assert length(results) == 3
      assert Enum.all?(results, &(&1 == "Hello, world!"))
    end

    test "list builder works with custom argument" do
      results = ChildFactory.build_greeting_list(2, "Bob")

      assert results == ["Hello, Bob!", "Hello, Bob!"]
    end

    test "list builder with non-map argument" do
      results = ChildFactory.build_pair_list(2, {:x, :y})

      assert results == [{:x, :y}, {:x, :y}]
    end

    test "list builder with keyword list argument" do
      results = ChildFactory.build_options_list(2, retries: 1)

      assert Enum.all?(results, &(&1 == [timeout: 5000, retries: 1]))
    end

    test "list builder with count 0 returns empty list" do
      assert ChildFactory.build_greeting_list(0) == []
    end

    test "keyword list with lazy 0-arity attrs" do
      result = ChildFactory.build_lazy_options()

      assert result[:timeout] == 5000
      assert %DateTime{} = result[:created_at]
    end

    test "keyword list with lazy 1-arity attrs" do
      result = ChildFactory.build_lazy_options()

      assert result[:label] == "timeout-5000"
    end

    test "keyword list lazy attrs with overrides" do
      result = ChildFactory.build_lazy_options(timeout: 9000)

      assert result[:timeout] == 9000
      # 1-arity receives the keyword list before lazy eval, so sees the raw fn for :label
      # but :timeout is already resolved since it was overridden with a plain value
      assert result[:label] == "timeout-9000"
    end
  end

  # ── params_for / string_params_for ───────────────────────────────

  describe "params_for" do
    test "returns a plain map without __struct__ or __meta__" do
      params = ChildFactory.params_for_user()

      assert is_map(params)
      refute Map.has_key?(params, :__struct__)
      refute Map.has_key?(params, :__meta__)
    end

    test "removes autogenerated :id" do
      params = ChildFactory.params_for_user()

      refute Map.has_key?(params, :id)
    end

    test "keeps regular fields" do
      params = ChildFactory.params_for_user(%{username: "alice"})

      assert params.username == "alice"
    end

    test "keeps nil fields" do
      params = ChildFactory.params_for_user()

      assert Map.has_key?(params, :first_name)
    end

    test "removes belongs_to association structs" do
      params = ChildFactory.params_for_author()

      refute Map.has_key?(params, :user)
    end

    test "removes NotLoaded associations" do
      params = ChildFactory.params_for_user()

      refute Map.has_key?(params, :author)
    end

    test "sets FK for persisted belongs_to" do
      user = ChildFactory.insert_user()
      params = ChildFactory.params_for_author(%{user: user})

      assert params.user_id == user.id
    end

    test "works with variants" do
      params = ChildFactory.params_for_admin_user()

      assert is_map(params)
      refute Map.has_key?(params, :__struct__)
      assert is_binary(params.username)
    end

    test "not generated for non-Ecto factories" do
      refute function_exported?(ChildFactory, :params_for_non_struct, 0)
    end

    test "non-struct factories use build_* (no _params suffix)" do
      assert function_exported?(ChildFactory, :build_non_struct, 0)
      refute function_exported?(ChildFactory, :build_non_struct_params, 0)
    end
  end

  describe "string_params_for" do
    test "returns string keys" do
      params = ChildFactory.string_params_for_user()

      assert is_binary(Map.keys(params) |> hd())
      assert Map.has_key?(params, "username")
    end

    test "accepts overrides" do
      params = ChildFactory.string_params_for_user(%{username: "bob"})

      assert params["username"] == "bob"
    end

    test "leaves struct values untouched" do
      params = ChildFactory.string_params_for_user(%{created_at: ~U[2026-01-01 00:00:00Z]})

      assert params["created_at"] == ~U[2026-01-01 00:00:00Z]
    end

    test "works with variants" do
      params = ChildFactory.string_params_for_admin_user()

      assert Map.has_key?(params, "username")
    end
  end

  # ── deffactory/2,3 duplicate option warning ────────────────────

  describe "deffactory/2,3 duplicate option warning" do
    import ExUnit.CaptureLog

    test "warns when deffactory specifies the same option as its module" do
      log =
        capture_log(fn ->
          Code.compile_string("""
          defmodule FactDupMod do
            use FactoryMan, build_params?: false

            deffactory thing(params \\\\ %{}), struct: SomeStruct, build_params?: false do
              params
            end
          end
          """)
        end)

      assert log =~ "FactoryMan: duplicate option"
      assert log =~ "factory :thing"
      assert log =~ ":build_params?"
    end

    test "does not warn when deffactory overrides with a different value" do
      log =
        capture_log(fn ->
          Code.compile_string("""
          defmodule FactDiffMod do
            use FactoryMan, build_params?: false

            deffactory thing(params \\\\ %{}), struct: SomeStruct, build_params?: true do
              params
            end
          end
          """)
        end)

      refute log =~ "FactoryMan: duplicate option"
    end

    test "suppresses warning at factory level" do
      log =
        capture_log(fn ->
          Code.compile_string("""
          defmodule FactSuppMod do
            use FactoryMan, build_params?: false

            deffactory thing(params \\\\ %{}),
              struct: SomeStruct,
              build_params?: false,
              suppress_duplicate_option_warning: true do
              params
            end
          end
          """)
        end)

      refute log =~ "FactoryMan: duplicate option"
    end
  end
end
