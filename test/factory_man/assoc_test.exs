defmodule FactoryMan.AssocTest.Author do
  defstruct [:name, :email]
end

defmodule FactoryMan.AssocTest.Comment do
  defstruct [:body, :author]
end

defmodule FactoryMan.AssocTest do
  use ExUnit.Case, async: true

  alias FactoryMan.AssocTest.Author
  alias FactoryMan.AssocTest.Comment

  defp build_author(params), do: struct!(Author, Map.put_new(params, :name, "Default Author"))

  describe "assoc/4" do
    test "missing key builds the default" do
      assert %Author{name: "Default Author"} = FactoryMan.assoc(%{}, :author, &build_author/1)
    end

    test "missing key builds from :inherit params" do
      author = FactoryMan.assoc(%{}, :author, &build_author/1, inherit: %{email: "a@b.c"})

      assert author.email == "a@b.c"
    end

    test "explicit nil builds the default (on_nil: :build is the default)" do
      assert %Author{} = FactoryMan.assoc(%{author: nil}, :author, &build_author/1)
    end

    test "explicit nil stays nil with on_nil: :keep" do
      assert FactoryMan.assoc(%{author: nil}, :author, &build_author/1, on_nil: :keep) == nil
    end

    test "missing key resolves to nil with on_missing: nil" do
      assert FactoryMan.assoc(%{}, :author, &build_author/1, on_missing: nil) == nil
    end

    test "on_missing: nil still builds from a present params map" do
      author =
        FactoryMan.assoc(%{author: %{name: "Ann"}}, :author, &build_author/1, on_missing: nil)

      assert author == %Author{name: "Ann"}
    end

    test "on_missing: nil does not change on_nil (explicit nil still builds)" do
      assert %Author{} =
               FactoryMan.assoc(%{author: nil}, :author, &build_author/1, on_missing: nil)
    end

    test "a struct matching :struct is reused as-is" do
      author = %Author{name: "Ann"}

      assert FactoryMan.assoc(%{author: author}, :author, &build_author/1, struct: Author) ==
               author
    end

    test "a struct is reused as-is when no :struct option is given" do
      author = %Author{name: "Ann"}

      assert FactoryMan.assoc(%{author: author}, :author, &build_author/1) == author
    end

    test "a struct not matching :struct raises" do
      assert_raise ArgumentError, ~r/expected :author to be a FactoryMan.AssocTest.Author/, fn ->
        FactoryMan.assoc(%{author: %Comment{}}, :author, &build_author/1, struct: Author)
      end
    end

    test "a params map builds the association from those params" do
      author = FactoryMan.assoc(%{author: %{name: "Ann"}}, :author, &build_author/1)

      assert author == %Author{name: "Ann"}
    end

    test "caller params override :inherit params" do
      author =
        FactoryMan.assoc(%{author: %{name: "Ann"}}, :author, &build_author/1,
          inherit: %{name: "Inherited", email: "a@b.c"}
        )

      assert author.name == "Ann"
      assert author.email == "a@b.c"
    end

    test "a non-map value raises" do
      assert_raise ArgumentError, ~r/expected :author to be a struct, a params map, or nil/, fn ->
        FactoryMan.assoc(%{author: "Ann"}, :author, &build_author/1)
      end
    end

    test "an invalid :on_nil option raises" do
      assert_raise ArgumentError, ~r/invalid :on_nil option: :ignore/, fn ->
        FactoryMan.assoc(%{}, :author, &build_author/1, on_nil: :ignore)
      end
    end

    test "an invalid :on_missing option raises" do
      assert_raise ArgumentError, ~r/invalid :on_missing option: :ignore/, fn ->
        FactoryMan.assoc(%{}, :author, &build_author/1, on_missing: :ignore)
      end
    end
  end

  describe "assoc_list/4" do
    test "missing key resolves to an empty list" do
      assert FactoryMan.assoc_list(%{}, :comments, &build_author/1) == []
    end

    test "explicit nil resolves to an empty list" do
      assert FactoryMan.assoc_list(%{comments: nil}, :comments, &build_author/1) == []
    end

    test "each element is resolved independently (mixed structs and params maps)" do
      existing = %Author{name: "Existing"}
      params = %{authors: [%{name: "Built"}, existing]}

      assert [%Author{name: "Built"}, ^existing] =
               FactoryMan.assoc_list(params, :authors, &build_author/1, struct: Author)
    end

    test ":inherit applies to each built element" do
      authors =
        FactoryMan.assoc_list(%{authors: [%{}, %{email: "b@b.c"}]}, :authors, &build_author/1,
          inherit: %{email: "a@b.c"}
        )

      assert Enum.map(authors, & &1.email) == ["a@b.c", "b@b.c"]
    end

    test "an element of the wrong struct type raises" do
      assert_raise ArgumentError, ~r/expected :authors to be a FactoryMan.AssocTest.Author/, fn ->
        FactoryMan.assoc_list(%{authors: [%Comment{}]}, :authors, &build_author/1, struct: Author)
      end
    end

    test "a non-list value raises" do
      assert_raise ArgumentError, ~r/expected :authors to be a list/, fn ->
        FactoryMan.assoc_list(%{authors: %Author{}}, :authors, &build_author/1)
      end
    end
  end

  describe "use FactoryMan import surface" do
    test "qualified assoc/assoc_list work in factory bodies" do
      [{mod, _}] =
        Code.compile_string("""
        defmodule FactoryMan.AssocTest.QualifiedFactory do
          use FactoryMan

          deffactory post(params \\\\ %{}) do
            %{
              author: FactoryMan.assoc(params, :author, fn p -> Map.put_new(p, :name, "Ann") end),
              tags: FactoryMan.assoc_list(params, :tags, fn p -> p end)
            }
          end
        end
        """)

      assert %{author: %{name: "Ann"}, tags: []} = mod.build_post()
    end

    test "helper functions are not imported (bare assoc does not compile)" do
      assert_raise CompileError, fn ->
        Code.compile_string("""
        defmodule FactoryMan.AssocTest.BareFactory do
          use FactoryMan

          deffactory post(params \\\\ %{}) do
            %{author: assoc(params, :author, fn p -> p end)}
          end
        end
        """)
      end
    end
  end
end
