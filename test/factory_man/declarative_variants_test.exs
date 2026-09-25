defmodule FactoryMan.DeclarativeVariantsTest.Person do
  defstruct [:name, :role, :title, :banned]
end

defmodule FactoryMan.DeclarativeVariantsTest.Factory do
  use FactoryMan, strict: true

  alias FactoryMan.DeclarativeVariantsTest.Person
  alias FactoryManDemo.Authors.Author
  alias FactoryManDemo.Users.User

  deffactory person(params \\ %{}), struct: Person do
    Map.merge(%{name: "person", role: "member"}, params)
  end

  defvariant admin, for: :person, defaults: %{role: "admin", title: "Administrator"}

  defvariant banned(), for: :person, force: %{banned: true}

  # A key in all three places: `defaults:`, the caller's params, and `force:`
  defvariant layered, for: :person, defaults: %{role: "default"}, force: %{title: "forced"}

  defvariant banned_admin, for: :person, extends: [:admin, :banned]

  defvariant boss, for: :person, as: :chief, defaults: %{title: "Boss"}

  # Body variant, for chains that mix both forms
  defvariant senior(params \\ %{}), for: :person do
    Map.merge(%{title: "Senior"}, params)
  end

  # `defaults:` is code: a function call, evaluated on every build
  defvariant numbered, for: :person, defaults: numbered_defaults()

  def numbered_defaults, do: %{name: FactoryMan.sequence("numbered")}

  # A typo in `defaults:`, caught by the strict base factory
  defvariant typo, for: :person, defaults: %{rol: "admin"}

  defvariant lazy, for: :person, defaults: %{title: fn person -> "Title of #{person.name}" end}

  deffactory user(params \\ %{}), struct: User do
    Map.merge(%{username: FactoryMan.sequence("declarative-user")}, params)
  end

  deffactory author(params \\ %{}), struct: Author, assocs: [user: &build_user_struct/1] do
    Map.merge(%{name: "author"}, params)
  end

  # `defaults:` for a declared key is what the variant's builder builds from
  defvariant guest,
    for: :author,
    assocs: [user: &build_user_struct/1],
    defaults: %{user: %{username: "guest"}}

  deffactory payload(params \\ %{}) do
    Map.merge(%{action: "create"}, params)
  end

  defvariant deletion, for: :payload, defaults: %{action: "delete"}

  deffactory greeting(name \\ "world") do
    "Hello, #{name}!"
  end

  defvariant polite, for: :greeting, defaults: %{please: true}
end

defmodule FactoryMan.DeclarativeVariantsTest do
  use ExUnit.Case, async: true

  alias FactoryMan.DeclarativeVariantsTest.{Factory, Person}
  alias FactoryManDemo.Users.User

  defp compile_module!(source) do
    Code.compile_string("""
    defmodule FactoryMan.DeclarativeVariantsTest.Compiled#{System.unique_integer([:positive])} do
      use FactoryMan

      alias FactoryMan.DeclarativeVariantsTest.Person, warn: false

      deffactory person(params \\\\ %{}), struct: FactoryMan.DeclarativeVariantsTest.Person do
        Map.merge(%{name: "person"}, params)
      end

    #{source}
    end
    """)
  end

  describe "defaults:" do
    test "sets values the caller's params override" do
      assert %Person{role: "admin", title: "Administrator"} = Factory.build_admin_person_struct()
      assert %Person{role: "owner"} = Factory.build_admin_person_struct(%{role: "owner"})
    end

    test "generates the base factory's full family" do
      assert %{role: "admin"} = Factory.build_admin_person_params()
      assert [%Person{role: "admin"}] = Factory.build_admin_person_struct_list(1)
    end

    test "accepts an expression, evaluated on every build" do
      first = Factory.build_numbered_person_struct()
      second = Factory.build_numbered_person_struct()

      assert first.name != second.name
    end

    test "passes lazy values on to the base factory, which resolves them" do
      assert %Person{title: "Title of person"} = Factory.build_lazy_person_struct()
    end

    test "raises at build time when it is not a map" do
      [{module, _binary}] =
        compile_module!("""
        defvariant listed, for: :person, defaults: [role: "admin"]
        """)

      assert_raise ArgumentError, ~r/defvariant listed: defaults: must be a map/, fn ->
        module.build_listed_person_struct()
      end
    end
  end

  describe "force:" do
    test "sets values that win over the caller's params" do
      assert %Person{banned: true} = Factory.build_banned_person_struct(%{banned: false})
    end

    test "wins over defaults: and the caller for a key in all three" do
      assert %Person{role: "caller", title: "forced"} =
               Factory.build_layered_person_struct(%{role: "caller", title: "caller"})

      assert %Person{role: "default"} = Factory.build_layered_person_struct()
    end
  end

  describe "extends: without a body" do
    test "names a combination of variants" do
      assert %Person{role: "admin", banned: true} = Factory.build_banned_admin_person_struct()
    end
  end

  describe "as:" do
    test "renames the generated functions" do
      assert %Person{title: "Boss"} = Factory.build_chief_struct()
      assert Factory.__factory_man__(:variants, :person) |> Enum.member?(:boss)
    end
  end

  describe "variants:" do
    test "combines declarative and body variants" do
      assert %Person{role: "admin", title: "Senior", banned: true} =
               Factory.build_person_struct(%{}, variants: [:admin, :senior, :banned])
    end
  end

  describe "assocs:" do
    test "builds a declared key from its defaults: value" do
      assert %{user: %User{username: "guest"}} = Factory.build_guest_author_struct()
    end

    test "keeps a caller's value for the declared key" do
      user = Factory.build_user_struct(%{username: "given"})

      assert %{user: ^user} = Factory.build_guest_author_struct(%{user: user})
    end
  end

  describe "strict base factories" do
    test "catch a key in defaults: that is not a field" do
      assert_raise ArgumentError, ~r/unknown params \[:rol\]/, fn ->
        Factory.build_typo_person_struct()
      end
    end
  end

  describe "non-struct base factories" do
    test "merge into map params" do
      assert %{action: "delete"} = Factory.build_deletion_payload()
      assert %{action: "archive"} = Factory.build_deletion_payload(%{action: "archive"})
    end

    test "raise when the params are not a map" do
      assert_raise ArgumentError,
                   ~r/defvariant polite merges defaults: and force: into its params, so its params must be a map, got: "world"/,
                   fn -> Factory.build_polite_greeting("world") end
    end
  end

  describe "compile-time validation" do
    test "raises on a head with an argument and no body" do
      assert_raise ArgumentError,
                   ~r/defvariant admin: the declarative form .* takes no argument/,
                   fn ->
                     compile_module!("defvariant admin(params), for: :person, defaults: %{}")
                   end
    end

    test "raises on a head without an argument and a do block" do
      assert_raise ArgumentError,
                   ~r/defvariant admin: a variant with a do block takes one argument/,
                   fn ->
                     compile_module!("""
                     defvariant admin, for: :person do
                       %{}
                     end
                     """)
                   end
    end

    test "raises without defaults:, force:, extends:, or assocs:" do
      assert_raise ArgumentError,
                   ~r/defvariant empty: a variant without a body needs defaults:, force:, extends:, or assocs:/,
                   fn -> compile_module!("defvariant empty, for: :person") end
    end

    test "raises on defaults: or force: with a do block" do
      for option <- ["defaults: %{}", "force: %{}"] do
        assert_raise ArgumentError,
                     ~r/defvariant admin: defaults: and force: .* Use one form/,
                     fn ->
                       compile_module!("""
                       defvariant admin(params \\\\ %{}), for: :person, #{option} do
                         params
                       end
                       """)
                     end
      end
    end

    test "raises on an unknown option" do
      assert_raise ArgumentError, ~r/unknown options \[:default\] for defvariant admin/, fn ->
        compile_module!("defvariant admin, for: :person, default: %{}")
      end
    end
  end
end
