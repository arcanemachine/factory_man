defmodule FactoryMan.AssocTest.Author do
  defstruct [:name, :email]
end

defmodule FactoryMan.AssocTest.Comment do
  defstruct [:body, :author]
end

defmodule FactoryMan.AssocTest.EctoUser do
  use Ecto.Schema

  schema "factory_man_assoc_test_users" do
    field :username, :string
    belongs_to :mentor, __MODULE__
  end
end

defmodule FactoryMan.AssocTest.EctoTag do
  use Ecto.Schema

  schema "factory_man_assoc_test_tags" do
    field :name, :string
  end
end

defmodule FactoryMan.AssocTest.EctoPost do
  use Ecto.Schema

  alias FactoryMan.AssocTest.EctoTag
  alias FactoryMan.AssocTest.EctoUser

  schema "factory_man_assoc_test_posts" do
    field :title, :string
    belongs_to :author, EctoUser
    many_to_many :tags, EctoTag, join_through: "factory_man_assoc_test_posts_tags"
  end
end

defmodule FactoryMan.AssocTest.Settings do
  use Ecto.Schema

  embedded_schema do
    field :theme, :string
  end
end

defmodule FactoryMan.AssocTest.ThroughOwner do
  use Ecto.Schema

  alias FactoryMan.AssocTest.{EctoPost, EctoTag, Settings}

  schema "factory_man_assoc_test_through_owners" do
    has_many :posts, EctoPost
    has_many :tags, through: [:posts, :tags]
    embeds_one :settings, Settings
  end
end

defmodule FactoryMan.AssocTest.ExternalFactory do
  use FactoryMan

  alias FactoryMan.AssocTest.{EctoTag, EctoUser}

  deffactory user(params \\ %{}),
    struct: EctoUser,
    strict: true,
    associations: [mentor: :user] do
    send(self(), {:user_build, params})

    base_params = %{username: "external-user"}

    Map.merge(base_params, params)
  end

  defvariant named(params \\ %{}), for: :user do
    base_params = %{username: "variant-default"}

    Map.merge(base_params, params)
  end

  deffactory raw(params \\ %{}) do
    Map.merge(%{}, params)
  end

  deffactory wrong_result(params \\ %{}), struct: EctoUser, body: :struct do
    %EctoTag{name: "wrong schema"}
  end
end

defmodule FactoryMan.AssocTest.DeclarativeFactory do
  use FactoryMan

  alias FactoryMan.AssocTest.{EctoPost, EctoTag, EctoUser, ExternalFactory}

  # The same-module :tag target is intentionally declared after :post.
  deffactory post(params \\ %{}),
    struct: EctoPost,
    associations: [author: {ExternalFactory, :user}, tags: :tag] do
    base_params = %{
      title: "default post",
      author: %EctoUser{username: "default-user"},
      tags: [%EctoTag{name: "default-tag"}]
    }

    Map.merge(base_params, params)
  end

  deffactory tag(params \\ %{}), struct: EctoTag do
    send(self(), {:tag_build, params})
    base_params = %{name: "default-tag"}

    Map.merge(base_params, params)
  end

  deffactory direct_post(params \\ %{}),
    struct: EctoPost,
    body: :struct,
    associations: [author: {ExternalFactory, :user}, tags: :tag] do
    %EctoPost{author: params[:author], tags: params[:tags]}
  end

  defvariant featured(params \\ %{}), for: :post do
    base_params = %{title: "featured post"}

    Map.merge(base_params, params)
  end

  deffactory variant_post(params \\ %{}),
    struct: EctoPost,
    associations: [author: {ExternalFactory, :named_user}] do
    base_params = %{title: "variant target", author: %EctoUser{}}

    Map.merge(base_params, params)
  end

  deffactory wrong_target(params \\ %{}),
    struct: EctoPost,
    associations: [author: {ExternalFactory, :wrong_result}] do
    Map.merge(%{author: %EctoUser{}}, params)
  end
end

defmodule FactoryMan.AssocTest.HookedFactory do
  use FactoryMan

  alias FactoryMan.AssocTest.{EctoPost, EctoUser, ExternalFactory}

  def add_author(params) do
    send(self(), {:before_params, params})
    Map.put_new(params, :author, %{username: "from-hook"})
  end

  def after_params(params) do
    send(self(), {:after_params, params})
    params
  end

  def before_struct(params) do
    send(self(), {:before_struct, params})
    params
  end

  def after_struct(record) do
    send(self(), {:after_struct, record})
    record
  end

  deffactory post(params \\ %{}),
    struct: EctoPost,
    strict: true,
    associations: [author: {ExternalFactory, :user}],
    hooks: [
      before_build_params: &__MODULE__.add_author/1,
      after_build_params: &__MODULE__.after_params/1,
      before_build_struct: &__MODULE__.before_struct/1,
      after_build_struct: &__MODULE__.after_struct/1
    ] do
    send(self(), {:factory_body, params})

    base_params = %{
      title: "hooked post",
      author: %EctoUser{username: "default-user"}
    }

    Map.merge(base_params, params)
  end

  deffactory direct_post(params \\ %{}),
    struct: EctoPost,
    body: :struct,
    strict: true,
    associations: [author: {ExternalFactory, :user}],
    hooks: [
      before_build_params: &__MODULE__.add_author/1,
      after_build_params: &__MODULE__.after_params/1,
      before_build_struct: &__MODULE__.before_struct/1,
      after_build_struct: &__MODULE__.after_struct/1
    ] do
    send(self(), {:factory_body, params})
    %EctoPost{author: params[:author]}
  end
end

defmodule FactoryMan.AssocTest.RecordingRepo do
  def insert!(record, opts) do
    send(self(), {:repo_insert, record, opts})
    record
  end
end

defmodule FactoryMan.AssocTest do
  use ExUnit.Case, async: true

  alias FactoryMan.AssocTest.Author
  alias FactoryMan.AssocTest.Comment

  defp build_author(params), do: struct!(Author, Map.put_new(params, :name, "Default Author"))

  defp compile_factory!(opts) do
    module =
      Module.concat(
        __MODULE__,
        "Generated#{System.unique_integer([:positive, :monotonic])}"
      )

    Code.compile_string("""
    defmodule #{inspect(module)} do
      use FactoryMan

      deffactory sample(params), #{inspect(opts, limit: :infinity)} do
        base_params = %{}

        Map.merge(base_params, params)
      end
    end
    """)

    module
  end

  describe "assoc/2,3" do
    test "a params map builds the association" do
      assert FactoryMan.assoc(%{name: "Ann"}, &build_author/1) == %Author{name: "Ann"}
    end

    test "nil builds the default" do
      assert FactoryMan.assoc(nil, &build_author/1) == %Author{name: "Default Author"}
    end

    test "nil stays nil with on_nil: :keep" do
      assert FactoryMan.assoc(nil, &build_author/1, on_nil: :keep) == nil
    end

    test "a struct is reused as-is" do
      author = %Author{name: "Ann"}

      assert FactoryMan.assoc(author, &build_author/1, struct: Author) == author
    end

    test "a struct is reused without a type option" do
      comment = %Comment{body: "A comment"}

      assert FactoryMan.assoc(comment, &build_author/1) == comment
    end

    test "a struct does not invoke the builder" do
      existing = %Author{name: "Existing"}

      builder = fn _params ->
        send(self(), :builder_called)
        existing
      end

      assert FactoryMan.assoc(existing, builder, struct: Author) == existing
      refute_received :builder_called
    end

    test "inherit params are merged below caller params" do
      author =
        FactoryMan.assoc(%{name: "Ann"}, &build_author/1,
          inherit: %{name: "Inherited", email: "a@b.c"}
        )

      assert author == %Author{name: "Ann", email: "a@b.c"}
    end

    test "a wrong struct type raises" do
      assert_raise ArgumentError, ~r/expected .*FactoryMan.AssocTest.Author struct/, fn ->
        FactoryMan.assoc(%Comment{}, &build_author/1, struct: Author)
      end
    end

    test "a builder result of the wrong type raises" do
      assert_raise ArgumentError, ~r/expected .*FactoryMan.AssocTest.Author struct/, fn ->
        FactoryMan.assoc(%{}, fn _params -> %Comment{} end, struct: Author)
      end
    end

    test "a non-map, non-struct value raises" do
      assert_raise ArgumentError, ~r/expected an association to be a struct/, fn ->
        FactoryMan.assoc("Ann", &build_author/1)
      end
    end

    test "invalid builder, options, and values raise" do
      assert_raise ArgumentError, ~r/1-arity function/, fn ->
        FactoryMan.assoc(%{}, :not_a_builder)
      end

      assert_raise ArgumentError, ~r/invalid association options/, fn ->
        FactoryMan.assoc(%{}, &build_author/1, on_missing: nil)
      end

      assert_raise ArgumentError, ~r/invalid :on_nil option/, fn ->
        FactoryMan.assoc(%{}, &build_author/1, on_nil: :ignore)
      end

      assert_raise ArgumentError, ~r/:inherit option/, fn ->
        FactoryMan.assoc(%{}, &build_author/1, inherit: [])
      end

      assert_raise ArgumentError, ~r/struct module/, fn ->
        FactoryMan.assoc(%{}, &build_author/1, struct: String)
      end

      assert_raise ArgumentError, ~r/:inherit option/, fn ->
        FactoryMan.assoc(%{}, &build_author/1, inherit: %Author{})
      end
    end
  end

  describe "assoc_list/2,3" do
    test "nil and an empty list resolve to an empty list" do
      assert FactoryMan.assoc_list(nil, &build_author/1) == []
      assert FactoryMan.assoc_list([], &build_author/1) == []
    end

    test "each map and struct is resolved independently" do
      existing = %Author{name: "Existing"}

      assert [%Author{name: "Built"}, ^existing] =
               FactoryMan.assoc_list([%{name: "Built"}, existing], &build_author/1,
                 struct: Author
               )
    end

    test "inherit applies to each built element" do
      authors =
        FactoryMan.assoc_list([%{}, %{email: "b@b.c"}], &build_author/1,
          inherit: %{email: "a@b.c"}
        )

      assert Enum.map(authors, & &1.email) == ["a@b.c", "b@b.c"]
    end

    test "a wrong struct type raises" do
      assert_raise ArgumentError, ~r/expected .*FactoryMan.AssocTest.Author struct/, fn ->
        FactoryMan.assoc_list([%Comment{}], &build_author/1, struct: Author)
      end
    end

    test "nil list elements raise" do
      assert_raise ArgumentError, ~r/list item 0/, fn ->
        FactoryMan.assoc_list([nil], &build_author/1)
      end
    end

    test "a non-list value raises" do
      assert_raise ArgumentError, ~r/expected an association list/, fn ->
        FactoryMan.assoc_list(%Author{}, &build_author/1)
      end
    end

    test "on_nil is not accepted" do
      assert_raise ArgumentError, ~r/invalid association options/, fn ->
        FactoryMan.assoc_list([], &build_author/1, on_nil: :keep)
      end
    end
  end

  describe "resolver execution guarantees" do
    test "nil keep and empty collections do not invoke the builder" do
      builder = fn _ -> flunk("builder must not run") end

      assert FactoryMan.assoc(nil, builder, on_nil: :keep) == nil
      assert FactoryMan.assoc_list(nil, builder) == []
      assert FactoryMan.assoc_list([], builder) == []
    end

    test "builder exceptions propagate unchanged" do
      builder = fn _ -> raise RuntimeError, "builder failed" end

      assert_raise RuntimeError, "builder failed", fn ->
        FactoryMan.assoc(%{}, builder)
      end

      assert_raise RuntimeError, "builder failed", fn ->
        FactoryMan.assoc_list([%{}], builder)
      end
    end

    test "list builder results are checked against the requested struct" do
      assert_raise ArgumentError, ~r/Author struct/, fn ->
        FactoryMan.assoc_list([%{}], fn _ -> %Comment{} end, struct: Author)
      end
    end

    test "both helpers reject malformed option containers" do
      for opts <- [%{}, [:struct], [{"struct", Author}]] do
        assert_raise ArgumentError, ~r/keyword list/, fn ->
          FactoryMan.assoc(%{}, &build_author/1, opts)
        end

        assert_raise ArgumentError, ~r/keyword list/, fn ->
          FactoryMan.assoc_list([], &build_author/1, opts)
        end
      end
    end
  end

  describe "declarative associations" do
    alias FactoryMan.AssocTest.DeclarativeFactory
    alias FactoryMan.AssocTest.EctoPost
    alias FactoryMan.AssocTest.EctoTag
    alias FactoryMan.AssocTest.EctoUser

    test "uses same-module and cross-module factory references" do
      post =
        DeclarativeFactory.build_post_struct(%{
          author: %{username: "from-external-factory"},
          tags: [%{name: "elixir"}, %{name: "testing"}]
        })

      assert %EctoPost{author: %EctoUser{username: "from-external-factory"}} = post
      assert [%EctoTag{name: "elixir"}, %EctoTag{name: "testing"}] = post.tags
    end

    test "leaves missing keys for factory defaults" do
      assert %EctoPost{
               author: %EctoUser{username: "default-user"},
               tags: [%EctoTag{name: "default-tag"}]
             } = DeclarativeFactory.build_post_struct()
    end

    test "reuses existing structs and preserves explicit nil" do
      user = %EctoUser{username: "existing"}
      tag = %EctoTag{name: "existing"}

      assert %EctoPost{author: ^user, tags: [^tag]} =
               DeclarativeFactory.build_post_struct(%{author: user, tags: [tag]})

      assert %EctoPost{author: nil, tags: []} =
               DeclarativeFactory.build_post_struct(%{author: nil, tags: []})
    end

    test "normalizes associations for body: :struct factories" do
      assert %EctoPost{
               author: %EctoUser{username: "direct"},
               tags: [%EctoTag{name: "direct-tag"}]
             } =
               DeclarativeFactory.build_direct_post_struct(%{
                 author: %{username: "direct"},
                 tags: [%{name: "direct-tag"}]
               })
    end

    test "normalizes through generated params and list functions" do
      input = %{author: %{username: "alice"}, tags: [%{name: "elixir"}]}

      params = DeclarativeFactory.build_post_params(input)
      refute Map.has_key?(params, :author)
      assert [%{name: "elixir"}] = params.tags
      refute Map.has_key?(hd(params.tags), :__struct__)

      string_params = DeclarativeFactory.build_post_string_params(input)
      refute Map.has_key?(string_params, "author")
      assert [%{"name" => "elixir"}] = string_params["tags"]

      structs = DeclarativeFactory.build_post_struct_list(2, input)
      assert length(structs) == 2
      assert Enum.all?(structs, &match?(%EctoUser{username: "alice"}, &1.author))

      params_list = DeclarativeFactory.build_post_params_list(2, input)
      assert length(params_list) == 2
      assert Enum.all?(params_list, &match?([%{name: "elixir"}], &1.tags))

      string_list = DeclarativeFactory.build_post_string_params_list(2, input)
      assert length(string_list) == 2
      assert Enum.all?(string_list, &match?([%{"name" => "elixir"}], &1["tags"]))
    end

    test "normalizes associations through variants" do
      assert %EctoPost{
               title: "featured post",
               author: %EctoUser{username: "variant"}
             } =
               DeclarativeFactory.build_featured_post_struct(%{
                 author: %{username: "variant"},
                 tags: []
               })
    end

    test "uses a registered variant as an association target" do
      assert %EctoPost{author: %EctoUser{username: "variant-default"}} =
               DeclarativeFactory.build_variant_post_struct(%{author: %{}})
    end

    test "rejects a target builder that returns the wrong schema" do
      assert_raise ArgumentError, ~r/association :author.*EctoUser struct/, fn ->
        DeclarativeFactory.build_wrong_target_struct(%{author: %{}})
      end
    end

    test "normalizes nested configured associations" do
      post =
        DeclarativeFactory.build_post_struct(%{
          author: %{username: "alice", mentor: %{username: "mentor"}},
          tags: []
        })

      assert %EctoUser{
               username: "alice",
               mentor: %EctoUser{username: "mentor"}
             } = post.author

      assert_received {:user_build, %{username: "mentor"}}
      assert_received {:user_build, %{username: "alice", mentor: %EctoUser{}}}
      refute_received {:user_build, _}
    end

    test "normalizes only maps in mixed association lists" do
      existing = %EctoTag{name: "existing"}

      post =
        DeclarativeFactory.build_post_struct(%{
          author: %EctoUser{username: "existing-user"},
          tags: [%{name: "first"}, existing, %{name: "last"}]
        })

      assert post.author.username == "existing-user"
      assert [%EctoTag{name: "first"}, ^existing, %EctoTag{name: "last"}] = post.tags
      assert_received {:tag_build, %{name: "first"}}
      assert_received {:tag_build, %{name: "last"}}
      refute_received {:tag_build, _}
      refute_received {:user_build, _}
    end

    test "does not automatically build an omitted nested association" do
      user =
        FactoryMan.AssocTest.ExternalFactory.build_user_struct(%{
          username: "without-mentor"
        })

      assert %Ecto.Association.NotLoaded{} = user.mentor
      assert_received {:user_build, %{username: "without-mentor"}}
      refute_received {:user_build, _}
    end

    test "rejects wrong values and shapes" do
      assert_raise ArgumentError, ~r/association :author/, fn ->
        DeclarativeFactory.build_post_struct(%{author: %EctoTag{}})
      end

      assert_raise ArgumentError, ~r/association :tags.*list/, fn ->
        DeclarativeFactory.build_post_struct(%{tags: %{name: "not-a-list"}})
      end

      assert_raise ArgumentError, ~r/association :tags.*list/, fn ->
        DeclarativeFactory.build_post_struct(%{tags: nil})
      end

      assert_raise ArgumentError, ~r/association :tags.*0/, fn ->
        DeclarativeFactory.build_post_struct(%{tags: [nil]})
      end
    end

    test "validates association declarations" do
      assert_raise ArgumentError, ~r/through association/, fn ->
        FactoryMan.Associations.compile_specs!(
          __MODULE__,
          :through,
          FactoryMan.AssocTest.ThroughOwner,
          tags: :tag
        )
      end

      assert_raise ArgumentError, ~r/is not defined on/, fn ->
        FactoryMan.Associations.compile_specs!(
          __MODULE__,
          :embed,
          FactoryMan.AssocTest.ThroughOwner,
          settings: :tag
        )
      end

      assert_raise ArgumentError, ~r/unknown factory :missing/, fn ->
        FactoryMan.Associations.normalize_params!(
          %{},
          [{:author, :one, EctoUser, {FactoryMan.AssocTest.ExternalFactory, :missing}}],
          __MODULE__,
          :post
        )
      end

      assert_raise ArgumentError, ~r/is not defined on/, fn ->
        FactoryMan.Associations.compile_specs!(
          __MODULE__,
          :post,
          EctoPost,
          missing: :tag
        )
      end

      assert_raise ArgumentError, ~r/must be a keyword list/, fn ->
        FactoryMan.Associations.compile_specs!(__MODULE__, :post, EctoPost, [:author])
      end

      assert_raise ArgumentError, ~r/not an Ecto schema/, fn ->
        FactoryMan.Associations.compile_specs!(__MODULE__, :plain, Author, author: :user)
      end
    end
  end

  describe "declaration validation through deffactory" do
    alias FactoryMan.AssocTest.{EctoPost, ThroughOwner}

    test "rejects malformed declarations during module compilation" do
      cases = [
        {[struct: EctoPost, associations: [:author]], ~r/keyword list/},
        {
          [struct: EctoPost, associations: [author: :user, author: :other]],
          ~r/duplicate association keys/
        },
        {
          [struct: EctoPost, associations: [author: {"not-a-module", :user}]],
          ~r/must reference a factory/
        },
        {[struct: EctoPost, associations: [missing: :user]], ~r/is not defined on/},
        {[struct: Author, associations: [author: :user]], ~r/not an Ecto schema/},
        {[associations: [author: :user]], ~r/not an Ecto schema/}
      ]

      for {opts, message} <- cases do
        assert_raise ArgumentError, message, fn ->
          compile_factory!(opts)
        end
      end
    end

    test "rejects through associations during module compilation" do
      assert_raise ArgumentError, ~r/through association/, fn ->
        compile_factory!(struct: ThroughOwner, associations: [tags: :tag])
      end
    end

    test "rejects embeds during module compilation" do
      assert_raise ArgumentError, ~r/is not defined on/, fn ->
        compile_factory!(struct: ThroughOwner, associations: [settings: :settings])
      end
    end

    test "empty configuration does not require an Ecto schema" do
      factory = compile_factory!(associations: [])

      assert apply(factory, :build_sample, [%{value: 1}]) == %{value: 1}
    end
  end

  describe "runtime factory-reference validation" do
    alias FactoryMan.AssocTest.{DeclarativeFactory, EctoPost, ExternalFactory}

    test "rejects invalid targets even when the association key is absent" do
      cases = [
        {{FactoryMan.AssocTest.UnavailableFactory, :user}, ~r/could not load factory module/},
        {{String, :user}, ~r/not a FactoryMan module/},
        {{ExternalFactory, :missing}, ~r/unknown factory :missing/},
        {{ExternalFactory, :raw}, ~r/non-struct factory/},
        {{DeclarativeFactory, :tag}, ~r/expects .*EctoUser.*declares .*EctoTag/}
      ]

      for {target, message} <- cases do
        factory = compile_factory!(struct: EctoPost, associations: [author: target])

        error =
          assert_raise ArgumentError, message, fn ->
            apply(factory, :build_sample_struct, [%{}])
          end

        assert error.message =~ ":author"
        assert error.message =~ ":sample"
        assert error.message =~ inspect(factory)
      end
    end

    test "insert_struct bypasses association normalization" do
      factory =
        compile_factory!(
          struct: EctoPost,
          repo: FactoryMan.AssocTest.RecordingRepo,
          associations: [author: {ExternalFactory, :missing}]
        )

      record = %EctoPost{author: nil, tags: []}

      assert apply(factory, :insert_sample_struct, [record, [returning: true]]) === record
      assert_received {:repo_insert, ^record, [returning: true]}

      assert_raise ArgumentError, ~r/unknown factory :missing/, fn ->
        apply(factory, :build_sample_struct, [%{}])
      end
    end
  end

  describe "hook ordering" do
    alias FactoryMan.AssocTest.{EctoPost, EctoUser, HookedFactory}

    test "normalizes associations after before_build_params" do
      assert %EctoPost{author: %EctoUser{username: "from-hook"}} =
               HookedFactory.build_post_struct()
    end

    test "runs before hook, normalization, body, and struct hooks in order" do
      input = %{author: %{username: "alice"}}
      record = HookedFactory.build_post_struct(input)

      events =
        for _ <- 1..6 do
          receive do
            event -> event
          after
            100 -> flunk("missing pipeline event")
          end
        end

      assert [
               {:before_params, ^input},
               {:user_build, %{username: "alice"}},
               {:factory_body, %{author: %EctoUser{username: "alice"}}},
               {:after_params, %{author: %EctoUser{username: "alice"}}},
               {:before_struct, %{author: %EctoUser{username: "alice"}}},
               {:after_struct, ^record}
             ] = events
    end

    test "strict validation runs before hooks or associated builders" do
      assert_raise ArgumentError, ~r/unknown params.*:typo/, fn ->
        HookedFactory.build_post_struct(%{typo: true, author: %{username: "alice"}})
      end

      refute_received {:before_params, _}
      refute_received {:user_build, _}
      refute_received {:factory_body, _}
    end

    test "nested strict validation occurs in the associated factory" do
      assert_raise ArgumentError, ~r/unknown params.*:typo/, fn ->
        HookedFactory.build_post_struct(%{author: %{typo: true}})
      end

      assert_received {:before_params, %{author: %{typo: true}}}
      refute_received {:user_build, _}
      refute_received {:factory_body, _}
    end

    test "body: :struct skips params-stage hooks after normalization" do
      record = HookedFactory.build_direct_post_struct(%{author: %{username: "direct"}})

      assert_received {:user_build, %{username: "direct"}}
      assert_received {:factory_body, %{author: %EctoUser{username: "direct"}}}
      assert_received {:after_struct, ^record}
      refute_received {:before_params, _}
      refute_received {:after_params, _}
      refute_received {:before_struct, _}
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
              author: FactoryMan.assoc(params[:author], fn p -> Map.put_new(p, :name, "Ann") end),
              tags: FactoryMan.assoc_list(params[:tags], fn p -> p end)
            }
          end
        end
        """)

      assert %{author: %{name: "Ann"}, tags: []} = mod.build_post()
    end

    test "helper functions are not imported (bare assoc does not compile)" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise CompileError, fn ->
          Code.compile_string("""
          defmodule FactoryMan.AssocTest.BareFactory do
            use FactoryMan

            deffactory post(params \\\\ %{}) do
              %{author: assoc(%{}, fn p -> p end)}
            end
          end
          """)
        end
      end)
    end
  end
end
