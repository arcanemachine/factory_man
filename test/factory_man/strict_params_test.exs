defmodule FactoryMan.StrictParamsTest.User do
  defstruct [:username, :email]
end

defmodule FactoryMan.StrictParamsTest.Factory do
  use FactoryMan, strict: true

  alias FactoryMan.StrictParamsTest.User

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

  # non-struct factory — module-level strict: true is ignored
  deffactory greeting(params \\ %{}) do
    Map.merge(%{hello: "world"}, params)
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
      assert_raise ArgumentError, ~r/Allowed extra keys must be atoms/, fn ->
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
end
