defmodule FactoryMan.VariantsTest.Person do
  defstruct [:name, :role, :title, :confirmed]
end

defmodule FactoryMan.VariantsTest.Factory do
  use FactoryMan

  alias FactoryMan.VariantsTest.Person

  deffactory person(params \\ %{}), struct: Person do
    Map.merge(%{name: "person", role: "member"}, params)
  end

  defvariant admin(params \\ %{}), for: :person do
    send(self(), {:variant_ran, :admin})

    Map.merge(%{role: "admin", title: "Administrator"}, params)
  end

  defvariant moderator(params \\ %{}), for: :person do
    Map.merge(%{role: "moderator"}, params)
  end

  defvariant confirmed(params \\ %{}), for: :person do
    Map.merge(%{confirmed: true}, params)
  end

  defvariant senior(params \\ %{}), for: :person, extends: [:admin] do
    Map.merge(%{title: "Senior admin"}, params)
  end

  defvariant confirmed_admin(params \\ %{}), for: :person, extends: [:admin, :confirmed] do
    params
  end

  defvariant boss(params \\ %{}), for: :person, as: :chief do
    Map.merge(%{title: "Boss"}, params)
  end

  # Extends a variant that is renamed with `as:`
  defvariant big_boss(params \\ %{}), for: :person, extends: [:boss] do
    Map.merge(%{name: "big boss"}, params)
  end

  deffactory plain(params \\ %{}), struct: Person do
    Map.merge(%{name: "plain"}, params)
  end

  deffactory greeting(name \\ "world") do
    "Hello, #{name}!"
  end

  defvariant loud(name \\ "world"), for: :greeting do
    String.upcase(name)
  end

  defvariant excited(name \\ "world"), for: :greeting do
    name <> "!!"
  end
end

defmodule FactoryMan.VariantsTest do
  use ExUnit.Case, async: true

  alias FactoryMan.VariantsTest.{Factory, Person}

  defp compile_module!(source) do
    Code.compile_string("""
    defmodule FactoryMan.VariantsTest.Compiled#{System.unique_integer([:positive])} do
      use FactoryMan

      deffactory person(params \\\\ %{}), struct: FactoryMan.VariantsTest.Person do
        Map.merge(%{name: "person"}, params)
      end

      defvariant admin(params \\\\ %{}), for: :person do
        Map.merge(%{role: "admin"}, params)
      end

    #{source}
    end
    """)
  end

  describe "variants: option" do
    test "applies each listed variant" do
      assert %Person{role: "admin", confirmed: true} =
               Factory.build_person_struct(%{}, variants: [:admin, :confirmed])
    end

    test "a later variant wins over an earlier one" do
      assert %Person{role: "moderator", title: "Administrator"} =
               Factory.build_person_struct(%{}, variants: [:admin, :moderator])

      assert %Person{role: "admin", title: "Administrator"} =
               Factory.build_person_struct(%{}, variants: [:moderator, :admin])
    end

    test "the caller's params win over every variant" do
      assert %Person{role: "owner"} =
               Factory.build_person_struct(%{role: "owner"}, variants: [:admin, :moderator])
    end

    test "an empty list builds the base factory" do
      assert Factory.build_person_struct(%{name: "same"}, variants: []) ==
               Factory.build_person_struct(%{name: "same"})
    end

    test "each variant runs once, even when listed again or pulled in by extends:" do
      Factory.build_person_struct(%{}, variants: [:admin, :senior, :admin])

      assert_received {:variant_ran, :admin}
      refute_received {:variant_ran, :admin}
    end

    test "covers the params, string params, and list functions" do
      assert %{role: "admin"} = Factory.build_person_params(%{}, variants: [:admin])
      assert %{"role" => "admin"} = Factory.build_person_string_params(%{}, variants: [:admin])

      people = Factory.build_person_struct_list(2, %{}, variants: [:admin])
      assert length(people) == 2
      assert Enum.all?(people, &match?(%Person{role: "admin"}, &1))

      assert [%{role: "admin"}] = Factory.build_person_params_list(1, %{}, variants: [:admin])

      assert [%{"role" => "admin"}] =
               Factory.build_person_string_params_list(1, %{}, variants: [:admin])
    end

    test "a variant's functions accept it too, with the variant itself listed first" do
      assert Factory.build_admin_person_struct(%{}, variants: [:moderator]) ==
               Factory.build_person_struct(%{}, variants: [:admin, :moderator])

      assert %Person{role: "moderator", title: "Administrator"} =
               Factory.build_admin_person_struct(%{}, variants: [:moderator])
    end

    test "variants are listed by the name in defvariant, not the as: name" do
      assert %Person{title: "Boss"} = Factory.build_person_struct(%{}, variants: [:boss])
      assert %Person{title: "Boss"} = Factory.build_chief_struct()
    end

    test "an unknown variant raises with the known variants" do
      error =
        assert_raise ArgumentError, fn ->
          Factory.build_person_struct(%{}, variants: [:admn])
        end

      assert error.message =~ "unknown variant :admn for factory :person"
      assert error.message =~ "Known variants: [:admin, :moderator, :confirmed, :senior"
    end

    test "a variant of another factory raises" do
      assert_raise ArgumentError, ~r/unknown variant :loud for factory :person/, fn ->
        Factory.build_person_struct(%{}, variants: [:loud])
      end
    end

    test "unknown options and invalid variant lists raise" do
      assert_raise ArgumentError,
                   ~r/unknown options \[:varients\] for build_person_struct\/2/,
                   fn ->
                     Factory.build_person_struct(%{}, varients: [:admin])
                   end

      assert_raise ArgumentError,
                   ~r/expected variants: for .* to be a list of variant names/,
                   fn ->
                     Factory.build_person_struct(%{}, variants: :admin)
                   end
    end
  end

  describe "extends:" do
    test "a variant builds on the variants it extends" do
      assert %Person{role: "admin", title: "Senior admin"} = Factory.build_senior_person_struct()
    end

    test "a variant wins over the variants it extends, whatever the list order" do
      for variants <- [[:senior, :admin], [:admin, :senior]] do
        assert %Person{title: "Senior admin"} =
                 Factory.build_person_struct(%{}, variants: variants)
      end
    end

    test "extends: names a variant by its defvariant name, even when as: renames it" do
      assert %Person{name: "big boss", title: "Boss"} = Factory.build_big_boss_person_struct()
    end

    test "a named combination is a variant that extends others" do
      assert %Person{role: "admin", confirmed: true} =
               Factory.build_confirmed_admin_person_struct()

      assert Factory.build_person_struct(%{}, variants: [:confirmed_admin]) ==
               Factory.build_confirmed_admin_person_struct()
    end
  end

  describe "non-struct factories" do
    test "accept variants: on the builder and list functions" do
      assert Factory.build_greeting("bob", variants: [:loud]) == "Hello, BOB!"

      assert Factory.build_greeting_list(2, "bob", variants: [:loud]) ==
               ["Hello, BOB!", "Hello, BOB!"]
    end

    test "run a variant's own function with more variants" do
      # The chain runs from the last variant to the base: `excited`, then `loud`, then `greeting`
      assert Factory.build_loud_greeting("bob", variants: [:excited]) == "Hello, BOB!!!"
    end
  end

  describe "__factory_man__(:variants, factory_name)" do
    test "lists a factory's variants in definition order" do
      assert Factory.__factory_man__(:variants, :person) ==
               [:admin, :moderator, :confirmed, :senior, :confirmed_admin, :boss, :big_boss]

      assert Factory.__factory_man__(:variants, :greeting) == [:loud, :excited]
      assert Factory.__factory_man__(:variants, :plain) == []
    end

    test "__factory_man__(:factories) still lists variants under their full name" do
      factories = Factory.__factory_man__(:factories)

      assert :senior_person in factories
      assert :chief in factories
    end
  end

  describe "compile-time validation" do
    test "for: must name a factory, not a variant" do
      assert_raise ArgumentError,
                   ~r/for: must name a factory, and :admin_person is a variant. Build on it with for: :person, extends: \[:admin\]/,
                   fn ->
                     compile_module!("""
                     defvariant senior(params \\\\ %{}), for: :admin_person do
                       params
                     end
                     """)
                   end
    end

    test "extends: must name variants of the same factory, defined earlier" do
      assert_raise ArgumentError,
                   ~r/unknown variants \[:boss\] in extends: for factory :person/,
                   fn ->
                     compile_module!("""
                     defvariant senior(params \\\\ %{}), for: :person, extends: [:boss] do
                       params
                     end
                     """)
                   end
    end

    test "extends: must be a list of names" do
      assert_raise ArgumentError, ~r/extends: must be a list of variant names/, fn ->
        compile_module!("""
        defvariant senior(params \\\\ %{}), for: :person, extends: :admin do
          params
        end
        """)
      end
    end

    test "a variant name is unique per factory" do
      assert_raise ArgumentError, ~r/factory :person already has a variant named :admin/, fn ->
        compile_module!("""
        defvariant admin(params \\\\ %{}), for: :person, as: :other_admin do
          params
        end
        """)
      end
    end
  end
end
