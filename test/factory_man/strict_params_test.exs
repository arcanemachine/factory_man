defmodule FactoryMan.StrictParamsTest.User do
  defstruct [:username, :email]
end

defmodule FactoryMan.StrictParamsTest.Prefs do
  defstruct [:color, :size]
end

defmodule FactoryMan.StrictParamsTest.Account do
  defstruct [:name, :settings, :prefs]
end

defmodule FactoryMan.StrictParamsTest.Factory do
  use FactoryMan, strict: true

  alias FactoryMan.StrictParamsTest.{Account, Prefs, User}

  deffactory user(params \\ %{}), struct: User do
    base_params = %{username: "user"}

    Map.merge(base_params, params)
  end

  defvariant admin(params \\ %{}), for: :user do
    base_params = %{email: "admin@example.com"}

    Map.merge(base_params, params)
  end

  # strict: false override — body: :struct so unknown keys are silently ignored
  deffactory lax_user(params \\ %{}), struct: User, body: :struct, strict: false do
    %User{username: Map.get(params, :username, "lax")}
  end

  # extra non-field key permitted via allow:
  deffactory derived_user(params \\ %{}),
    struct: User,
    body: :struct,
    strict: [allow: [:domain]] do
    domain = Map.get(params, :domain, "example.com")

    %User{username: "derived", email: "derived@#{domain}"}
  end

  # A body that forgot to merge params
  deffactory forgetful_user(params \\ %{}), struct: User do
    %{username: "forgetful"}
  end

  # A body: :struct body that never reads :email
  deffactory selective_user(params \\ %{}), struct: User, body: :struct do
    %User{username: Map.get(params, :username, "selective")}
  end

  deffactory shouting_user(params \\ %{}), struct: User do
    %{username: "shout"} |> Map.merge(params) |> Map.update!(:username, &String.upcase/1)
  end

  # A field in allow: may be changed by the body
  deffactory normalized_user(params \\ %{}), struct: User, strict: [allow: [:username]] do
    %{username: "shout"} |> Map.merge(params) |> Map.update!(:username, &String.upcase/1)
  end

  # Returns a keyword list, which `struct!/2` accepts, and drops the caller's params
  deffactory keyword_user(params \\ %{}), struct: User do
    _ = params

    [username: "keyword"]
  end

  def put_helper(params), do: Map.put(params, :helper, "helped")

  # A hook adds a key that is not a field, and the body uses it up
  deffactory helped_user(params \\ %{}),
    struct: User,
    hooks: [before_build_params: &__MODULE__.put_helper/1] do
    {helper, params} = Map.pop(params, :helper)

    Map.merge(%{username: helper}, params)
  end

  # Fills in the missing keys of a map field, and builds a struct from another
  deffactory account(params \\ %{}), struct: Account, body: :struct do
    settings = Map.merge(%{"theme" => "light", "lang" => "en"}, Map.get(params, :settings, %{}))

    %Account{
      name: Map.get(params, :name, "account"),
      settings: settings,
      prefs: struct!(Prefs, Map.merge(%{size: "m"}, Map.get(params, :prefs, %{})))
    }
  end

  # Replaces the caller's map field
  deffactory reset_account(params \\ %{}), struct: Account, body: :struct do
    %Account{name: Map.get(params, :name, "reset"), settings: %{"theme" => "light"}}
  end

  # non-struct factory — module-level strict: true is ignored
  deffactory greeting(params \\ %{}) do
    Map.merge(%{hello: "world"}, params)
  end
end

defmodule FactoryMan.StrictParamsTest.EctoFactory do
  use FactoryMan, strict: true

  alias FactoryManDemo.Authors.Author
  alias FactoryManDemo.Users.User

  deffactory user(params \\ %{}), struct: User do
    Map.merge(%{username: "user"}, params)
  end

  # Resolves the association imperatively, replacing the caller's params map with a struct
  deffactory author(params \\ %{}), struct: Author do
    user = FactoryMan.assoc(params, :user, &build_user_struct/1)

    Map.merge(%{name: "author"}, Map.put(params, :user, user))
  end
end

defmodule FactoryMan.StrictParamsTest do
  use ExUnit.Case, async: true

  alias FactoryMan.StrictParamsTest.Factory
  alias FactoryMan.StrictParamsTest.User

  describe "strict: true" do
    test "known keys build normally" do
      assert %User{username: "alice"} = Factory.build_user_struct(%{username: "alice"})
    end

    test "an unknown key raises with the factory, struct, and allowed keys" do
      assert_raise ArgumentError,
                   ~r/unknown params \[:usernme\] for strict factory :user \(struct FactoryMan.StrictParamsTest.User\)/,
                   fn -> Factory.build_user_struct(%{usernme: "typo"}) end
    end

    test "the check covers derived params functions" do
      assert_raise ArgumentError, ~r/unknown params \[:usernme\]/, fn ->
        Factory.build_user_params(%{usernme: "typo"})
      end
    end

    test "the check covers variants of the factory" do
      assert %User{email: "admin@example.com"} = Factory.build_admin_user_struct()

      assert_raise ArgumentError, ~r/unknown params \[:usernme\]/, fn ->
        Factory.build_admin_user_struct(%{usernme: "typo"})
      end
    end

    test "module-level strict is ignored for non-struct factories" do
      assert %{hello: "world", unknown: 1} = Factory.build_greeting(%{unknown: 1})
    end
  end

  describe "strict: true, ignored or changed params" do
    test "a body that forgot to merge params raises" do
      error =
        assert_raise ArgumentError, fn ->
          Factory.build_forgetful_user_struct(%{username: "alice"})
        end

      assert error.message =~
               "strict factory :forgetful_user in FactoryMan.StrictParamsTest.Factory ignored " <>
                 "or changed params it was given"

      assert error.message =~ ~s[:username - given "alice", built "forgetful"]
    end

    test "a body that drops a key raises, naming the missing key" do
      assert_raise ArgumentError, ~r/:email - given "a@b.c", missing from the result/, fn ->
        Factory.build_forgetful_user_struct(%{email: "a@b.c"})
      end
    end

    test "a body: :struct body that never reads a key raises" do
      assert_raise ArgumentError, ~r/:email - given "a@b.c", built nil/, fn ->
        Factory.build_selective_user_struct(%{email: "a@b.c"})
      end
    end

    test "a body that changes a value raises, and the error names the fix" do
      error =
        assert_raise ArgumentError, fn ->
          Factory.build_shouting_user_struct(%{username: "alice"})
        end

      assert error.message =~ ~s[:username - given "alice", built "ALICE"]
      assert error.message =~ "strict: [allow: [...]]"
    end

    test "a field in allow: may be changed by the body" do
      assert %User{username: "ALICE"} = Factory.build_normalized_user_struct(%{username: "alice"})
    end

    test "a body that keeps its params builds normally" do
      assert %User{username: "alice", email: "a@b.c"} =
               Factory.build_user_struct(%{username: "alice", email: "a@b.c"})
    end

    test "function values are not checked" do
      assert %User{username: "lazy"} = Factory.build_user_struct(%{username: fn -> "lazy" end})
    end

    test "a body that returns a keyword list is checked too" do
      assert_raise ArgumentError, ~r/:username - given "alice", built "keyword"/, fn ->
        Factory.build_keyword_user_struct(%{username: "alice"})
      end
    end

    test "a key that is not a field is not checked" do
      assert %User{username: "helped"} = Factory.build_helped_user_struct()
    end

    test "a map field has been kept when each key the caller gave has been kept" do
      account =
        Factory.build_account_struct(%{settings: %{"theme" => "dark"}, prefs: %{color: "red"}})

      assert account.settings == %{"theme" => "dark", "lang" => "en"}
      assert account.prefs.color == "red"
    end

    test "a map field that loses a key the caller gave raises" do
      assert_raise ArgumentError, ~r/:settings - given %\{"theme" => "dark"\}, built/, fn ->
        Factory.build_reset_account_struct(%{settings: %{"theme" => "dark"}})
      end
    end

    test "association keys are not checked" do
      alias FactoryMan.StrictParamsTest.EctoFactory

      author = EctoFactory.build_author_struct(%{user: %{username: "bob"}})

      assert author.user.username == "bob"
    end
  end

  describe "strict: false override" do
    test "unknown keys are silently ignored again" do
      assert %User{username: "lax"} = Factory.build_lax_user_struct(%{usernme: "typo"})
    end
  end

  describe "strict: [allow: keys]" do
    test "allowed extra keys are accepted" do
      assert %User{email: "derived@perx.test"} =
               Factory.build_derived_user_struct(%{domain: "perx.test"})
    end

    test "keys outside the struct fields and allow list still raise" do
      assert_raise ArgumentError, ~r/unknown params \[:domian\]/, fn ->
        Factory.build_derived_user_struct(%{domian: "typo"})
      end
    end
  end

  describe "compile-time option validation" do
    test "an invalid :strict value raises" do
      assert_raise ArgumentError, ~r/invalid :strict option: :yes/, fn ->
        Code.compile_string("""
        defmodule FactoryMan.StrictParamsTest.InvalidOption do
          use FactoryMan

          deffactory user(params \\\\ %{}), struct: FactoryMan.StrictParamsTest.User, strict: :yes do
            params
          end
        end
        """)
      end
    end

    test "a non-atom allow key raises" do
      assert_raise ArgumentError, ~r/Allowed keys must be atoms/, fn ->
        Code.compile_string("""
        defmodule FactoryMan.StrictParamsTest.InvalidAllow do
          use FactoryMan

          deffactory user(params \\\\ %{}),
            struct: FactoryMan.StrictParamsTest.User,
            strict: [allow: ["domain"]] do
            params
          end
        end
        """)
      end
    end
  end

  describe "params container" do
    alias FactoryMan.StrictParamsTest.Factory

    test "a non-map argument raises at the factory boundary" do
      for params <- [[username: "kw"], "string", 1] do
        assert_raise ArgumentError, ~r/expected a params map for factory :user/, fn ->
          Factory.build_user_struct(params)
        end
      end
    end

    test "options passed in place of params name the second argument" do
      assert_raise ArgumentError, ~r/Options go in the second argument/, fn ->
        Factory.build_user_struct(variants: [:admin])
      end
    end

    test "the check applies to factories with strict disabled" do
      assert_raise ArgumentError, ~r/expected a params map for factory :lax_user/, fn ->
        Factory.build_lax_user_struct(role: "admin")
      end
    end

    test "non-struct factories still accept any value" do
      assert Factory.build_greeting(%{hello: "there"}) == %{hello: "there"}
    end
  end
end
