defmodule FactoryMan.AssocTest.Author do
  defstruct [:name]
end

defmodule FactoryMan.AssocTest.Settings do
  use Ecto.Schema

  embedded_schema do
    field :theme, :string
  end
end

defmodule FactoryMan.AssocTest.EctoUser do
  use Ecto.Schema

  schema "factory_man_assoc_test_users" do
    field :username, :string
    field :joined_on, :date
    field :profile, :map
    field :note, :any, virtual: true
    embeds_one :settings, FactoryMan.AssocTest.Settings
    belongs_to :mentor, __MODULE__
    has_many :posts, FactoryMan.AssocTest.EctoPost, foreign_key: :author_id
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

  alias FactoryMan.AssocTest.{EctoTag, EctoUser}

  schema "factory_man_assoc_test_posts" do
    field :title, :string
    belongs_to :author, EctoUser
    many_to_many :tags, EctoTag, join_through: "factory_man_assoc_test_posts_tags"
  end
end

defmodule FactoryMan.AssocTest.EctoComment do
  use Ecto.Schema

  alias FactoryMan.AssocTest.{EctoPost, EctoUser}

  schema "factory_man_assoc_test_comments" do
    field :body, :string
    belongs_to :author, EctoUser
    belongs_to :post, EctoPost
    belongs_to :parent, __MODULE__
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

defmodule FactoryMan.AssocTest.RemoteBuilders do
  alias FactoryMan.AssocTest.EctoTag

  def build_tag(params) do
    send(self(), {:remote_tag_build, params})
    struct!(EctoTag, Map.merge(%{name: "remote-tag"}, params))
  end
end

defmodule FactoryMan.AssocTest.Factory do
  use FactoryMan

  alias FactoryMan.AssocTest.{EctoComment, EctoPost, EctoTag, EctoUser, RemoteBuilders}

  deffactory user(params \\ %{}), struct: EctoUser do
    send(self(), {:user_build, params})
    base_params = %{username: "user-#{System.unique_integer([:positive])}"}

    Map.merge(base_params, params)
  end

  deffactory tag(params \\ %{}), struct: EctoTag do
    base_params = %{name: "tag-#{System.unique_integer([:positive])}"}

    Map.merge(base_params, params)
  end

  # A local capture, a remote capture, and a builder default that overrides `base_params`
  deffactory post(params \\ %{}),
    struct: EctoPost,
    assocs: [author: &build_user_struct/1, tags: &RemoteBuilders.build_tag/1] do
    send(self(), {:post_body, params})
    base_params = %{title: "post", author: :unused_body_default}

    Map.merge(base_params, params)
  end

  defvariant guest(params \\ %{}),
    for: :post,
    assocs: [author: fn params -> build_user_struct(Map.put_new(params, :username, "guest")) end] do
    send(self(), {:guest_body, params})

    Map.merge(%{title: "guest post"}, params)
  end

  deffactory anonymous_post(params \\ %{}),
    struct: EctoPost,
    assocs: [author: fn params -> build_user_struct(Map.put_new(params, :username, "anon")) end] do
    Map.merge(%{title: "anonymous"}, params)
  end

  deffactory direct_post(params \\ %{}),
    struct: EctoPost,
    body: :struct,
    assocs: [author: &build_user_struct/1] do
    %EctoPost{title: "direct", author: params.author}
  end

  deffactory shared_post(params \\ %{}), struct: EctoPost, assocs: post_assocs("shared") do
    Map.merge(%{title: "shared"}, params)
  end

  def post_assocs(username) do
    [author: fn params -> build_user_struct(Map.put_new(params, :username, username)) end]
  end

  deffactory defaults_post(params \\ %{}),
    struct: EctoPost,
    assocs: [
      author: {&build_user_struct/1, default: nil},
      tags: {&build_tag_struct/1, default: [%{name: "elixir"}, %{}]}
    ] do
    Map.merge(%{title: "defaults"}, params)
  end

  deffactory map_default_post(params \\ %{}),
    struct: EctoPost,
    assocs: [author: {&build_user_struct/1, default: %{username: "defaulted"}}] do
    Map.merge(%{title: "map default"}, params)
  end

  # Chaining: the post builder sees the resolved author, and not the raw `post` or `parent` input
  deffactory comment(params \\ %{}),
    struct: EctoComment,
    assocs: [
      author: &build_user_struct/1,
      post: fn params, factory_params ->
        send(self(), {:post_factory_params, factory_params})
        build_post_struct(Map.put_new(params, :author, factory_params.author))
      end,
      parent: {&build_comment_struct/1, default: nil}
    ] do
    Map.merge(%{body: "Nice post"}, Map.drop(params, [:extra]))
  end

  # Defaults that are checked at build time
  deffactory record_default(params \\ %{}),
    struct: EctoPost,
    assocs: [author: {&build_user_struct/1, default: %{mentor: %EctoUser{username: "prebuilt"}}}] do
    Map.merge(%{}, params)
  end

  deffactory nested_record_default(params \\ %{}),
    struct: EctoPost,
    assocs: [
      author: {&build_user_struct/1, default: %{mentor: %{posts: [%{}, %EctoPost{}]}}}
    ] do
    Map.merge(%{}, params)
  end

  deffactory value_structs_default(params \\ %{}),
    struct: EctoPost,
    assocs: [
      author:
        {&build_user_struct/1,
         default: %{
           joined_on: ~D[2026-01-01],
           settings: %FactoryMan.AssocTest.Settings{theme: "dark"},
           profile: %{best_post: %EctoPost{title: "data"}},
           note: %EctoUser{username: "virtual"}
         }}
    ] do
    Map.merge(%{}, params)
  end

  deffactory struct_item_default(params \\ %{}),
    struct: EctoPost,
    assocs: [tags: {&build_tag_struct/1, default: [%EctoTag{}]}] do
    Map.merge(%{}, params)
  end

  deffactory nil_many_default(params \\ %{}),
    struct: EctoPost,
    assocs: [tags: {&build_tag_struct/1, default: nil}] do
    Map.merge(%{}, params)
  end

  deffactory list_one_default(params \\ %{}),
    struct: EctoPost,
    assocs: [author: {&build_user_struct/1, default: [%{}]}] do
    Map.merge(%{}, params)
  end

  deffactory map_many_default(params \\ %{}),
    struct: EctoPost,
    assocs: [tags: {&build_tag_struct/1, default: %{}}] do
    Map.merge(%{}, params)
  end

  deffactory miswired_post(params \\ %{}),
    struct: EctoPost,
    assocs: [author: &build_tag_struct/1] do
    Map.merge(%{}, params)
  end

  deffactory optional_author_post(params \\ %{}),
    struct: EctoPost,
    assocs: [author: fn params -> if params[:username], do: build_user_struct(params) end] do
    Map.merge(%{}, params)
  end

  deffactory nil_item_post(params \\ %{}),
    struct: EctoPost,
    assocs: [tags: fn _params -> nil end] do
    Map.merge(%{}, params)
  end

  deffactory strict_user(params \\ %{}), struct: EctoUser, strict: true do
    Map.merge(%{}, params)
  end

  defvariant mentored(params \\ %{}),
    for: :strict_user,
    assocs: [mentor: &build_user_struct/1] do
    Map.merge(%{username: "mentored"}, params)
  end

  ## Required

  deffactory required_author_post(params \\ %{}),
    struct: EctoPost,
    assocs: [author: {&build_user_struct/1, required: true}] do
    Map.merge(%{title: "required"}, params)
  end

  defvariant plain(params \\ %{}), for: :required_author_post do
    params
  end

  # A variant cannot relax its base's `required:`
  defvariant anonymous(params \\ %{}),
    for: :required_author_post,
    assocs: [author: {&build_user_struct/1, default: nil}] do
    params
  end

  # A variant can add `required:` to a base key that allows nil
  defvariant authored(params \\ %{}),
    for: :post,
    assocs: [author: {&build_user_struct/1, required: true}] do
    params
  end

  deffactory nil_builder_required_post(params \\ %{}),
    struct: EctoPost,
    assocs: [author: {fn _params -> nil end, required: true}] do
    Map.merge(%{}, params)
  end

  deffactory reordered_required_post(params \\ %{}),
    struct: EctoPost,
    assocs: [author: {&build_user_struct/1, required: true, default: %{username: "first"}}] do
    Map.merge(%{}, params)
  end

  def nil_author(params), do: Map.put(params, :author, nil)

  deffactory hooked_required_post(params \\ %{}),
    struct: EctoPost,
    hooks: [before_build_params: &__MODULE__.nil_author/1],
    assocs: [author: {&build_user_struct/1, required: true}] do
    Map.merge(%{}, params)
  end

  ## Recursion

  deffactory required_mentee(params \\ %{}),
    struct: EctoUser,
    assocs: [mentor: {&build_required_mentee_struct/1, required: true}] do
    Map.merge(%{}, params)
  end

  # A self-loop through a variant and its base: the base builds the variant by default
  deffactory node(params \\ %{}),
    struct: EctoUser,
    assocs: [mentor: &build_special_node_struct/1] do
    Map.merge(%{}, params)
  end

  defvariant special(params \\ %{}), for: :node do
    Map.merge(%{username: "special"}, params)
  end

  deffactory mentee(params \\ %{}), struct: EctoUser, assocs: [mentor: &build_mentee_struct/1] do
    Map.merge(%{}, params)
  end

  deffactory bounded_user(params \\ %{}),
    struct: EctoUser,
    assocs: [
      mentor: fn params -> build_bounded_user_struct(Map.put_new(params, :mentor, nil)) end
    ] do
    Map.merge(%{username: "bounded"}, params)
  end

  deffactory optional_mentor_user(params \\ %{}),
    struct: EctoUser,
    assocs: [mentor: {&build_optional_mentor_user_struct/1, default: nil}] do
    Map.merge(%{}, params)
  end

  deffactory looping_user(params \\ %{}),
    struct: EctoUser,
    assocs: [posts: {&build_looping_post_struct/1, default: [%{}]}] do
    Map.merge(%{}, params)
  end

  deffactory looping_post(params \\ %{}),
    struct: EctoPost,
    assocs: [author: &build_looping_user_struct/1] do
    Map.merge(%{}, params)
  end

  deffactory body_loop_user(params \\ %{}), struct: EctoUser do
    mentor = FactoryMan.assoc(params, :mentor, &build_body_loop_user_struct/1)

    Map.merge(%{}, Map.put(params, :mentor, mentor))
  end

  deffactory list_loop_user(params \\ %{}), struct: EctoUser do
    posts =
      FactoryMan.assoc_list(params, :posts, &build_list_loop_post_struct/1, default: [%{}])

    Map.merge(%{}, Map.put(params, :posts, posts))
  end

  deffactory list_loop_post(params \\ %{}), struct: EctoPost do
    author = FactoryMan.assoc(params, :author, &build_list_loop_user_struct/1)

    Map.merge(%{}, Map.put(params, :author, author))
  end

  deffactory raising_mentor_user(params \\ %{}),
    struct: EctoUser,
    assocs: [mentor: fn _params -> raise "builder failed" end] do
    Map.merge(%{}, params)
  end

  # A wrapper that resolves the same key as its caller, with a different builder
  deffactory wrapped_post(params \\ %{}), struct: EctoPost do
    author = FactoryMan.assoc(params, :author, &author_wrapper/1)

    Map.merge(%{}, Map.put(params, :author, author))
  end

  def author_wrapper(params) do
    FactoryMan.assoc(params, :author, &build_user_struct/1)
  end

  def helper_user(params) do
    %EctoUser{mentor: FactoryMan.assoc(params, :mentor, &helper_user/1)}
  end

  def closure_user(n) do
    fn params ->
      %EctoUser{
        username: "user#{n}",
        mentor: FactoryMan.assoc(params, :mentor, closure_user(n + 1))
      }
    end
  end

  # Would stop on its own at zero, while the key stays absent
  def countdown_user(n) do
    fn params ->
      mentor = if n > 0, do: FactoryMan.assoc(params, :mentor, countdown_user(n - 1))
      %EctoUser{username: "user#{n}", mentor: mentor}
    end
  end
end

defmodule FactoryMan.AssocTest.HookedFactory do
  use FactoryMan

  alias FactoryMan.AssocTest.{EctoPost, Factory}

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
    assocs: [author: &Factory.build_user_struct/1],
    hooks: [
      before_build_params: &__MODULE__.add_author/1,
      after_build_params: &__MODULE__.after_params/1,
      before_build_struct: &__MODULE__.before_struct/1,
      after_build_struct: &__MODULE__.after_struct/1
    ] do
    send(self(), {:factory_body, params})

    Map.merge(%{title: "hooked post"}, params)
  end

  deffactory direct_post(params \\ %{}),
    struct: EctoPost,
    body: :struct,
    strict: true,
    assocs: [author: &Factory.build_user_struct/1],
    hooks: [
      before_build_params: &__MODULE__.add_author/1,
      after_build_params: &__MODULE__.after_params/1,
      before_build_struct: &__MODULE__.before_struct/1,
      after_build_struct: &__MODULE__.after_struct/1
    ] do
    send(self(), {:factory_body, params})
    %EctoPost{author: params.author}
  end
end

defmodule FactoryMan.AssocTest do
  use ExUnit.Case, async: true

  alias FactoryMan.AssocTest.{EctoComment, EctoPost, EctoTag, EctoUser, Factory, Settings}

  # Compiles a module that uses FactoryMan. `source` is inserted into the module body.
  defp compile_module!(source) do
    module = Module.concat(__MODULE__, "Generated#{System.unique_integer([:positive])}")

    Code.compile_string("""
    defmodule #{inspect(module)} do
      alias FactoryMan.AssocTest.{Author, EctoPost, EctoUser, ThroughOwner}, warn: false

      #{source}
    end
    """)

    module
  end

  # Compiles a single `sample` factory with the given options source
  defp compile_factory!(opts_source) do
    compile_module!("""
    use FactoryMan

    deffactory sample(params \\\\ %{}), #{opts_source} do
      Map.merge(%{}, params)
    end

    def build_user(params), do: struct!(EctoUser, params)
    """)
  end

  defp build_stack, do: Process.get(:factory_man_build_stack, [])

  describe "assocs: builders" do
    test "local and remote captures build absent keys" do
      post = Factory.build_post_struct()

      assert %EctoUser{} = post.author
      assert post.tags == []
    end

    test "anonymous functions build absent keys" do
      assert %EctoUser{username: "anon"} = Factory.build_anonymous_post_struct().author
    end

    test "the built value overrides a base_params default for the same key" do
      refute Factory.build_post_struct().author == :unused_body_default
    end

    test "the body receives every declared key resolved" do
      post = Factory.build_post_struct(%{tags: [%{name: "a"}]})

      assert_received {:post_body, %{author: %EctoUser{} = author, tags: [%EctoTag{name: "a"}]}}
      assert post.author == author
    end

    test "a shared spec from a function call" do
      assert %EctoUser{username: "shared"} = Factory.build_shared_post_struct().author
    end

    test "body: :struct factories resolve before the body" do
      assert %EctoPost{title: "direct", author: %EctoUser{}} = Factory.build_direct_post_struct()

      assert %EctoUser{username: "given"} =
               Factory.build_direct_post_struct(%{author: %{username: "given"}}).author
    end

    test "list builders resolve each item independently" do
      authors = Factory.build_post_struct_list(3) |> Enum.map(& &1.author.username)

      assert length(Enum.uniq(authors)) == 3
    end
  end

  describe "assocs: resolution rules" do
    test "one: nil resolves to nil without calling the builder" do
      assert Factory.build_post_struct(%{author: nil}).author == nil
      refute_received {:user_build, _}
    end

    test "one: a params map is built" do
      assert %EctoUser{username: "alice"} =
               Factory.build_post_struct(%{author: %{username: "alice"}}).author
    end

    test "one: a struct is reused without calling the builder" do
      user = %EctoUser{username: "existing"}

      assert Factory.build_post_struct(%{author: user}).author === user
      refute_received {:user_build, _}
    end

    test "one: a list raises" do
      assert_raise ArgumentError, ~r/association :author in factory :post in .*Factory/, fn ->
        Factory.build_post_struct(%{author: [%{}]})
      end
    end

    test "many: an absent key resolves to []" do
      assert Factory.build_post_struct().tags == []
      refute_received {:remote_tag_build, _}
    end

    test "many: nil, a map, and a struct raise" do
      for value <- [nil, %{}, %EctoTag{}] do
        assert_raise ArgumentError, ~r/association :tags in factory :post/, fn ->
          Factory.build_post_struct(%{tags: value})
        end
      end
    end

    test "many: maps are built and structs reused, in order" do
      tag = %EctoTag{name: "existing"}
      post = Factory.build_post_struct(%{tags: [%{name: "new"}, tag]})

      assert [%EctoTag{name: "new"}, ^tag] = post.tags
      assert_received {:remote_tag_build, %{name: "new"}}
      refute_received {:remote_tag_build, _}
    end

    test "many: nil and other values inside a list raise, naming the index" do
      for value <- [nil, "tag"] do
        assert_raise ArgumentError, ~r/association :tags\[1\] in factory :post/, fn ->
          Factory.build_post_struct(%{tags: [%{}, value]})
        end
      end
    end
  end

  describe "assocs: type check" do
    test "a supplied struct of another schema raises" do
      assert_raise ArgumentError,
                   ~r/association :author in factory :post in .*Factory expects a %FactoryMan.AssocTest.EctoUser\{\}, got: %FactoryMan.AssocTest.EctoTag/,
                   fn -> Factory.build_post_struct(%{author: %EctoTag{}}) end
    end

    test "a list item of another schema raises, naming the index" do
      assert_raise ArgumentError,
                   ~r/association :tags\[1\] .* expects a %FactoryMan.AssocTest.EctoTag\{\}/,
                   fn ->
                     Factory.build_post_struct(%{tags: [%EctoTag{}, %EctoUser{}]})
                   end
    end

    test "a builder result of another schema raises" do
      assert_raise ArgumentError,
                   ~r/association :author .* expects a %FactoryMan.AssocTest.EctoUser\{\}/,
                   fn ->
                     Factory.build_miswired_post_struct()
                   end
    end

    test "a builder may return nil for a singular association" do
      assert Factory.build_optional_author_post_struct().author == nil

      assert %EctoUser{username: "a"} =
               Factory.build_optional_author_post_struct(%{author: %{username: "a"}}).author
    end

    test "a builder returning nil for a list item raises" do
      assert_raise ArgumentError, ~r/association :tags\[0\] .* expects .*, got: nil/, fn ->
        Factory.build_nil_item_post_struct(%{tags: [%{}]})
      end
    end

    test "the helpers do not check types" do
      tag = %EctoTag{}

      assert FactoryMan.assoc(%{author: tag}, :author, &struct!(EctoUser, &1)) === tag
      assert FactoryMan.assoc_list(%{tags: [%EctoUser{}]}, :tags, & &1) == [%EctoUser{}]
    end
  end

  describe "assocs: required:" do
    test "an absent key still builds" do
      assert %EctoUser{} = Factory.build_required_author_post_struct().author
    end

    test "a caller's params map is built and a struct is reused" do
      user = %EctoUser{username: "existing"}

      assert Factory.build_required_author_post_struct(%{author: user}).author === user

      assert %EctoUser{username: "a"} =
               Factory.build_required_author_post_struct(%{author: %{username: "a"}}).author
    end

    test "a caller's nil raises" do
      assert_raise ArgumentError,
                   ~r/association :author in factory :required_author_post in .*Factory is required, got nil/,
                   fn -> Factory.build_required_author_post_struct(%{author: nil}) end
    end

    test "a builder that returns nil raises" do
      assert_raise ArgumentError,
                   ~r/the builder for association :author in factory :nil_builder_required_post .* returned nil, but the association is required/,
                   fn -> Factory.build_nil_builder_required_post_struct() end
    end

    test "a nil set by a before_build_params hook raises" do
      assert_raise ArgumentError, ~r/is required, got nil/, fn ->
        Factory.build_hooked_required_post_struct()
      end
    end

    test "the error names the variant that was called" do
      assert_raise ArgumentError,
                   ~r/association :author in factory :plain_required_author_post .* is required/,
                   fn -> Factory.build_plain_required_author_post_struct(%{author: nil}) end
    end

    test "a variant cannot relax the base's required:" do
      assert_raise ArgumentError,
                   ~r/factory :anonymous_required_author_post .* is required/,
                   fn ->
                     Factory.build_anonymous_required_author_post_struct()
                   end
    end

    test "a variant can add required: to a base key" do
      assert Factory.build_post_struct(%{author: nil}).author == nil

      assert_raise ArgumentError, ~r/factory :authored_post .* is required, got nil/, fn ->
        Factory.build_authored_post_struct(%{author: nil})
      end
    end

    test "options may appear in any order" do
      assert %EctoUser{username: "first"} = Factory.build_reordered_required_post_struct().author
    end

    test "the type check still applies" do
      assert_raise ArgumentError, ~r/expects a %FactoryMan.AssocTest.EctoUser\{\}/, fn ->
        Factory.build_required_author_post_struct(%{author: %EctoTag{}})
      end
    end

    test "a required self-referential key offers only a caller value in the recursion error" do
      error = assert_raise ArgumentError, fn -> Factory.build_required_mentee_struct() end

      assert error.message =~ "self-referential"
      assert error.message =~ "Pass a value (a struct or params)."
      refute error.message =~ "default: nil"
    end

    test "invalid declarations are rejected when the factory builds" do
      cases = [
        {"struct: EctoPost, assocs: [author: {&build_user/1, required: true, default: nil}]",
         ~r/:author .* is required, so default: nil contradicts it/},
        {"struct: EctoPost, assocs: [tags: {&build_user/1, required: true}]",
         ~r/:tags .* is a list, so required: does not apply/},
        {~s|struct: EctoPost, assocs: [tags: {&build_user/1, required: "yes"}]|,
         ~r/required: for association :tags .* must be true or false/},
        {~s|struct: EctoPost, assocs: [author: {&build_user/1, required: "yes"}]|,
         ~r/required: for association :author .* must be true or false, got: "yes"/},
        {"struct: EctoPost, assocs: [author: {&build_user/1, requird: true}]",
         ~r/\{function, options\} with default: and\/or required:/},
        {"struct: EctoPost, assocs: [author: {&build_user/1, []}]",
         ~r/\{function, options\} with default: and\/or required:/}
      ]

      for {opts_source, message} <- cases do
        factory = compile_factory!(opts_source)

        assert_raise ArgumentError, message, fn -> factory.build_sample_struct() end
      end
    end

    test "required: false is a no-op, on singular and list keys" do
      factory =
        compile_factory!(
          "struct: EctoPost, assocs: [author: {&build_user/1, required: false}, " <>
            "tags: {&build_user/1, required: false}]"
        )

      post = factory.build_sample_struct(%{author: nil})

      assert post.author == nil
      assert post.tags == []
    end
  end

  describe "assocs: default:" do
    test "nil on one resolves an absent key to nil" do
      assert Factory.build_defaults_post_struct().author == nil
      refute_received {:user_build, _}
    end

    test "a params map on one builds with those params" do
      assert %EctoUser{username: "defaulted"} = Factory.build_map_default_post_struct().author
    end

    test "a list of maps on many builds each item, fresh per build" do
      [first, second] = Factory.build_defaults_post_struct().tags
      [_, other_second] = Factory.build_defaults_post_struct().tags

      assert first.name == "elixir"
      refute second.name == other_second.name
    end

    test "a supplied key ignores the default" do
      assert Factory.build_defaults_post_struct(%{tags: []}).tags == []
    end

    test "a record at an association position is rejected" do
      assert_raise ArgumentError,
                   ~r/default: for association :author in factory :record_default .* has a %FactoryMan.AssocTest.EctoUser\{\} record at association :mentor/,
                   fn -> Factory.build_record_default_struct() end
    end

    test "a record in nested association params is rejected" do
      assert_raise ArgumentError, ~r/record at association :mentor.:posts/, fn ->
        Factory.build_nested_record_default_struct()
      end
    end

    test "value structs, embeds, and records in non-association fields are allowed" do
      author = Factory.build_value_structs_default_struct().author

      assert author.joined_on == ~D[2026-01-01]
      assert %Settings{theme: "dark"} = author.settings
      assert %{best_post: %EctoPost{}} = author.profile
      assert %EctoUser{username: "virtual"} = author.note
    end

    test "a struct in a many default's list is rejected" do
      assert_raise ArgumentError,
                   ~r/default: for association :tags .* must be a list of params maps/,
                   fn ->
                     Factory.build_struct_item_default_struct()
                   end
    end

    test "nil on many and wrong shapes are rejected" do
      assert_raise ArgumentError, ~r/:tags .* default: nil is invalid; use \[\]/, fn ->
        Factory.build_nil_many_default_struct()
      end

      assert_raise ArgumentError, ~r/must be nil or a params map/, fn ->
        Factory.build_list_one_default_struct()
      end

      assert_raise ArgumentError, ~r/must be a list of params maps/, fn ->
        Factory.build_map_many_default_struct()
      end
    end
  end

  describe "assocs: chaining" do
    test "a 2-arity builder sees keys declared above it resolved" do
      comment = Factory.build_comment_struct()

      assert %EctoComment{post: %EctoPost{author: author}, author: author} = comment
      assert %EctoUser{} = author
    end

    test "the current key and keys declared below are hidden; undeclared keys are visible raw" do
      Factory.build_comment_struct(%{post: %{title: "t"}, parent: %{}, extra: :raw})

      assert_received {:post_factory_params, factory_params}
      assert %{author: %EctoUser{}, extra: :raw} = factory_params
      refute Map.has_key?(factory_params, :post)
      refute Map.has_key?(factory_params, :parent)
    end

    test "a supplied struct is reused without calling the 2-arity builder" do
      post = %EctoPost{title: "existing"}

      assert Factory.build_comment_struct(%{post: post}).post === post
      refute_received {:post_factory_params, _}
    end
  end

  describe "assocs: on defvariant" do
    test "the variant resolves first and the base reuses the struct" do
      post = Factory.build_guest_post_struct()

      assert %EctoUser{username: "guest"} = post.author
      assert_received {:guest_body, %{author: %EctoUser{username: "guest"}}}
      assert_received {:post_body, %{author: %EctoUser{username: "guest"}}}
    end

    test "the base's strict check runs before the variant's associations" do
      assert_raise ArgumentError,
                   ~r/unknown params \[:typo\] for strict factory :strict_user/,
                   fn ->
                     Factory.build_mentored_strict_user_struct(%{typo: true})
                   end

      refute_received {:user_build, _}
      assert %EctoUser{mentor: %EctoUser{}} = Factory.build_mentored_strict_user_struct()
    end

    test "caller values still win over the variant builder" do
      assert %EctoUser{username: "mine"} =
               Factory.build_guest_post_struct(%{author: %{username: "mine"}}).author
    end
  end

  describe "assocs: build-time validation" do
    test "rejects invalid declarations when the factory builds" do
      cases = [
        {"struct: EctoPost, assocs: [missing: &build_user/1]",
         ~r/:missing .* is not an association/},
        {"struct: EctoUser, assocs: [settings: &build_user/1]",
         ~r/:settings .* is not an association/},
        {"struct: ThroughOwner, assocs: [tags: &build_user/1]",
         ~r/:tags .* :through association/},
        {"struct: EctoPost, assocs: [author: &build_user/1, author: &build_user/1]",
         ~r/duplicate assocs: keys \[:author\]/},
        {"struct: EctoPost, assocs: [author: fn _, _, _ -> nil end]", ~r/1- or 2-arity function/},
        {"struct: EctoPost, assocs: [author: {&build_user/1, other: 1}]",
         ~r/1- or 2-arity function/},
        {"struct: EctoPost, assocs: [:author]", ~r/must be a keyword list/}
      ]

      for {opts_source, message} <- cases do
        factory = compile_factory!(opts_source)

        error = assert_raise ArgumentError, message, fn -> factory.build_sample_struct() end
        assert error.message =~ inspect(factory)
      end
    end
  end

  describe "assocs: compile-time errors" do
    test "params is not in scope in the assocs: expression" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise CompileError, fn ->
          compile_factory!("struct: EctoPost, assocs: [author: {&build_user/1, default: params}]")
        end
      end)
    end

    test "requires an Ecto schema struct" do
      assert_raise ArgumentError, ~r/Author is not an Ecto schema/, fn ->
        compile_factory!("struct: Author, assocs: []")
      end

      assert_raise ArgumentError, ~r/requires struct: to be an Ecto schema/, fn ->
        compile_factory!("assocs: []")
      end
    end

    test "rejects module-level assocs:" do
      assert_raise ArgumentError, ~r/assocs: is set per factory/, fn ->
        compile_module!("use FactoryMan, assocs: []")
      end
    end

    test "rejects assocs: in non-literal options" do
      assert_raise ArgumentError, ~r/must be written directly/, fn ->
        compile_module!("""
        use FactoryMan

        @opts [struct: EctoPost, assocs: []]

        deffactory sample(params), @opts do
          params
        end
        """)
      end
    end

    test "rejects assocs: on a variant of a non-struct factory" do
      assert_raise ArgumentError, ~r/requires struct: to be an Ecto schema/, fn ->
        compile_module!("""
        use FactoryMan

        deffactory raw(params), do: params

        defvariant other(params), for: :raw, assocs: [] do
          params
        end
        """)
      end
    end
  end

  describe "unknown options" do
    test "deffactory rejects them, listing the allowed options" do
      assert_raise ArgumentError, ~r/unknown options \[:associations\] .*Allowed options/, fn ->
        compile_factory!("struct: EctoPost, associations: [author: :user]")
      end
    end

    test "deffactory accepts a factory-level repo" do
      assert compile_factory!("struct: EctoPost, repo: nil")
    end

    test "defvariant rejects them" do
      assert_raise ArgumentError, ~r/unknown options \[:struct\] for defvariant other/, fn ->
        compile_module!("""
        use FactoryMan

        deffactory raw(params), do: params

        defvariant other(params), for: :raw, struct: EctoPost do
          params
        end
        """)
      end
    end

    test "use FactoryMan rejects them" do
      assert_raise ArgumentError, ~r/unknown options \[:typo\] for use FactoryMan/, fn ->
        compile_module!("use FactoryMan, typo: true")
      end
    end
  end

  describe "recursion guard" do
    test "a self-referential default build raises with the build path" do
      error = assert_raise ArgumentError, fn -> Factory.build_mentee_struct() end

      assert error.message =~
               "association :mentor in factory :mentee in FactoryMan.AssocTest.Factory is " <>
                 "self-referential"

      assert error.message =~ "Build path: :mentee → :mentor → :mentee → :mentor"
      assert error.message =~ "{builder, default: nil}"
      assert error.message =~ "supply the key at each level"
    end

    test "a mutual loop through a list raises with the many hint" do
      error = assert_raise ArgumentError, fn -> Factory.build_looping_user_struct() end

      assert error.message =~ "mutually recursive"
      assert error.message =~ "{builder, default: []}"
    end

    test "a self-loop through a variant and its base is self-referential" do
      error = assert_raise ArgumentError, fn -> Factory.build_special_node_struct() end

      assert error.message =~ "association :mentor in factory :special_node"

      assert error.message =~
               "self-referential: building it by default builds :special_node again"
    end

    test "bounded recursion written in the builder passes" do
      user = Factory.build_bounded_user_struct()

      assert %EctoUser{mentor: %EctoUser{mentor: nil}} = user
    end

    test "nil defaults are not tracked, and caller nesting always terminates" do
      assert Factory.build_optional_mentor_user_struct().mentor == nil

      user = Factory.build_optional_mentor_user_struct(%{mentor: %{mentor: %{}}})
      assert %EctoUser{mentor: %EctoUser{mentor: %EctoUser{mentor: nil}}} = user
    end

    test "list builds leave no stale entries between items" do
      assert length(Factory.build_bounded_user_struct_list(3)) == 3
      assert build_stack() == []
    end

    test "the build stack is cleaned up after an exception" do
      assert_raise RuntimeError, "builder failed", fn ->
        Factory.build_raising_mentor_user_struct()
      end

      assert build_stack() == []

      assert_raise ArgumentError, fn -> Factory.build_mentee_struct() end
      assert build_stack() == []
    end

    test "assoc/3 loops inside a factory body raise with the helper hint" do
      error = assert_raise ArgumentError, fn -> Factory.build_body_loop_user_struct() end

      assert error.message =~ "self-referential"
      assert error.message =~ "Pass default: nil"
    end

    test "assoc_list/4 loops inside a factory body raise" do
      error = assert_raise ArgumentError, fn -> Factory.build_list_loop_user_struct() end

      assert error.message =~ "mutually recursive"
      assert error.message =~ "Pass default: []"
    end

    test "a loop through a plain helper is caught on the first repeat" do
      error = assert_raise ArgumentError, fn -> Factory.helper_user(%{}) end

      assert error.message =~ "association :mentor is self-referential"
      assert error.message =~ "Build path: :mentor → :mentor"
    end

    test "a wrapper resolving the same key with a different builder does not raise" do
      assert %EctoPost{author: %EctoUser{}} = Factory.build_wrapped_post_struct()
    end

    test "closures from one code site with different captured values are caught" do
      assert_raise ArgumentError, ~r/self-referential/, fn -> Factory.closure_user(0).(%{}) end
    end

    test "recursion that would stop on its own while the key stays absent is rejected" do
      assert_raise ArgumentError, ~r/supply the key at each level/, fn ->
        Factory.countdown_user(2).(%{})
      end

      # Supplying the key where the recursion ends is the fix
      assert %EctoUser{mentor: %EctoUser{mentor: nil}} =
               Factory.countdown_user(2).(%{mentor: %{mentor: nil}})
    end
  end

  describe "assoc/3,4" do
    test "applies the resolution rules" do
      build = &struct!(EctoUser, &1)
      user = %EctoUser{username: "existing"}

      assert %EctoUser{} = FactoryMan.assoc(%{}, :author, build)
      assert FactoryMan.assoc(%{author: nil}, :author, build) == nil

      assert %EctoUser{username: "a"} =
               FactoryMan.assoc(%{author: %{username: "a"}}, :author, build)

      assert FactoryMan.assoc(%{author: user}, :author, build) === user

      assert_raise ArgumentError,
                   ~r/association :author to be a struct, a params map, or nil/,
                   fn ->
                     FactoryMan.assoc(%{author: "x"}, :author, build)
                   end
    end

    test "default: nil and a params map" do
      build = &struct!(EctoUser, &1)

      assert FactoryMan.assoc(%{}, :author, build, default: nil) == nil

      assert %EctoUser{username: "d"} =
               FactoryMan.assoc(%{}, :author, build, default: %{username: "d"})

      assert %EctoUser{username: "given"} =
               FactoryMan.assoc(%{author: %{username: "given"}}, :author, build,
                 default: %{username: "d"}
               )
    end

    test "rejects invalid defaults, options, and arguments" do
      build = &struct!(EctoUser, &1)

      assert_raise ArgumentError, ~r/must be nil or a params map/, fn ->
        FactoryMan.assoc(%{}, :author, build, default: [%{}])
      end

      assert_raise ArgumentError, ~r/The only option is default:/, fn ->
        FactoryMan.assoc(%{}, :author, build, struct: EctoUser)
      end

      assert_raise ArgumentError, ~r/params map/, fn -> FactoryMan.assoc([], :author, build) end
      assert_raise ArgumentError, ~r/key atom/, fn -> FactoryMan.assoc(%{}, "author", build) end

      assert_raise ArgumentError, ~r/1-arity/, fn ->
        FactoryMan.assoc(%{}, :author, fn -> 1 end)
      end
    end
  end

  describe "assoc_list/3,4" do
    test "applies the resolution rules" do
      build = &struct!(EctoTag, &1)
      tag = %EctoTag{name: "existing"}

      assert FactoryMan.assoc_list(%{}, :tags, build) == []

      assert [%EctoTag{name: "a"}, ^tag] =
               FactoryMan.assoc_list(%{tags: [%{name: "a"}, tag]}, :tags, build)

      assert_raise ArgumentError, ~r/use \[\]/, fn ->
        FactoryMan.assoc_list(%{tags: nil}, :tags, build)
      end

      assert_raise ArgumentError, ~r/:tags\[0\]/, fn ->
        FactoryMan.assoc_list(%{tags: [nil]}, :tags, build)
      end
    end

    test "default: a list of params maps" do
      build = &struct!(EctoTag, &1)

      assert [%EctoTag{name: "d"}] =
               FactoryMan.assoc_list(%{}, :tags, build, default: [%{name: "d"}])

      assert FactoryMan.assoc_list(%{tags: []}, :tags, build, default: [%{name: "d"}]) == []
    end

    test "a builder returning nil for an item raises, naming the index" do
      assert_raise ArgumentError, ~r/the builder for association :tags\[1\] returned nil/, fn ->
        FactoryMan.assoc_list(%{tags: [%EctoTag{}, %{}]}, :tags, fn _ -> nil end)
      end
    end

    test "rejects nil and wrong-shaped defaults" do
      build = &struct!(EctoTag, &1)

      assert_raise ArgumentError, ~r/default: nil is invalid/, fn ->
        FactoryMan.assoc_list(%{}, :tags, build, default: nil)
      end

      assert_raise ArgumentError, ~r/must be a list of params maps/, fn ->
        FactoryMan.assoc_list(%{}, :tags, build, default: [%EctoTag{}])
      end
    end
  end

  describe "hook ordering" do
    alias FactoryMan.AssocTest.HookedFactory

    test "associations resolve after before_build_params" do
      assert %EctoPost{author: %EctoUser{username: "from-hook"}} =
               HookedFactory.build_post_struct()
    end

    test "runs before hook, associations, body, and struct hooks in order" do
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

    test "strict validation runs before hooks or builders" do
      assert_raise ArgumentError, ~r/unknown params.*:typo/, fn ->
        HookedFactory.build_post_struct(%{typo: true, author: %{username: "alice"}})
      end

      refute_received {:before_params, _}
      refute_received {:user_build, _}
      refute_received {:factory_body, _}
    end

    test "body: :struct skips params-stage hooks" do
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
    test "helper functions are not imported (bare assoc does not compile)" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise CompileError, fn ->
          compile_module!("""
          use FactoryMan

          deffactory post(params \\\\ %{}) do
            %{author: assoc(params, :author, fn p -> p end)}
          end
          """)
        end
      end)
    end
  end
end
