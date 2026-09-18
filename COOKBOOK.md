# Cookbook

Recipes for common factory patterns. The full API reference lives in the
[`FactoryMan` module documentation](https://hexdocs.pm/factory_man/FactoryMan.html).

> NOTE: This section was LLM-generated and needs work.

## Building associations

For Ecto-backed factories, use the declarative `:associations` option. Ecto supplies the
associated schema and whether each association is singular or plural; the factory reference
supplies the builder. An atom refers to a factory in the current module, while a tuple refers to
a factory in another module:

```elixir
defmodule MyApp.AccountFactory do
  use FactoryMan

  alias MyApp.Accounts.User

  deffactory user(params \\ %{}), struct: User do
    base_params = %{username: FactoryMan.sequence("user")}

    Map.merge(base_params, params)
  end
end

defmodule MyApp.BlogFactory do
  use FactoryMan

  alias MyApp.Blog.{Post, Tag}

  deffactory tag(params \\ %{}), struct: Tag do
    base_params = %{name: FactoryMan.sequence("tag")}

    Map.merge(base_params, params)
  end

  deffactory post(params \\ %{}),
    struct: Post,
    associations: [author: {MyApp.AccountFactory, :user}, tags: :tag] do
    base_params = %{
      title: FactoryMan.sequence("post"),
      author: MyApp.AccountFactory.build_user_struct(),
      tags: []
    }

    Map.merge(base_params, params)
  end
end

# Missing associations use the factory defaults
MyApp.BlogFactory.build_post_struct()

# Nested maps are built through the configured factories
MyApp.BlogFactory.build_post_struct(%{
  author: %{username: "Ann"},
  tags: [%{name: "Elixir"}]
})

# Existing structs are reused
MyApp.BlogFactory.build_post_struct(%{author: existing_user, tags: [existing_tag]})

# Lists may mix existing structs and nested params
MyApp.BlogFactory.build_post_struct(%{
  author: existing_user,
  tags: [existing_tag, %{name: "Testing"}]
})
```

Only keys present in the caller's params are normalized. Missing keys remain missing, so the
factory's `base_params` still supplies defaults and the body keeps the usual final merge.
Association values must be a struct or params map for singular associations, and a list of
structs and/or params maps for plural associations. Explicit `nil` is valid for a singular
association; use `[]` for an empty plural association. This option currently supports direct Ecto
associations only; embeds and `:through` associations are not supported.

Normalization runs after `before_build_params` and before the factory body. With `body: :struct`,
normalization runs before the body without enabling params-stage hooks. Associated factories
process their own configured nested associations.

Missing keys are not automatically built by this option. Keep association defaults in the body.
An eager default runs even when the caller overrides it; use a lazy default when needed:

```elixir
base_params = %{
  title: FactoryMan.sequence("post"),
  author: fn -> MyApp.AccountFactory.build_user_struct() end,
  tags: []
}

Map.merge(base_params, params)
```

The normal lazy-evaluation stage evaluates that default only if it survives the merge. Do not
write defaults that endlessly build each other—for example, a user's default post building a
default author who builds another default post.

For plain structs or custom builder functions, the lower-level value resolvers are available:

```elixir
FactoryMan.assoc(author_or_params, &build_author_struct/1, struct: Author)
FactoryMan.assoc_list(tags_or_params, &build_tag_struct/1, struct: Tag)
```

These helpers accept an existing struct or params for building one. `:inherit` supplies defaults
beneath params maps. `assoc/3` builds nil by default and supports `on_nil: :keep` to preserve it;
`assoc_list/3` treats an outer nil as `[]` but rejects nil members.

The optional `struct:` check validates both existing structs and builder results. Without it, the
callback remains generic. If the input is already known to be a params map, a direct factory call
is simpler than a resolver.

When the schema only needs a foreign key (and the record must exist), insert the association
and use its ID:

```elixir
deffactory comment(params \\ %{}), struct: Comment do
  base_params = %{
    body: "Nice post!",
    post_id: Map.get_lazy(params, :post_id, fn -> insert_post().id end)
  }

  Map.merge(base_params, params)
end
```

## Post-build presets

Variants preprocess params — they cannot transform the *built* value. When a preset needs
to derive fields from the built struct, define a separate factory with `body: :struct`
whose body calls the base build function and transforms the result:

```elixir
deffactory anonymized_user(params \\ %{}), struct: User, body: :struct do
  user = build_user_struct(params)

  %{user | email: "redacted+#{user.id}@example.com", display_name: "anonymous"}
end
```

Unlike a hand-written `build_anonymized_user/1` function, this keeps the whole generated
family: `build_anonymized_user_params`, the `_list` builders, and `insert_anonymized_user`
all come for free.

One caveat: an `after_build_struct` hook runs twice — once inside the base build call and
once for the wrapping factory. Insert hooks run once (only the wrapping factory's insert
is called).

## Validated presets

A variant that promises a property of its result ("this post is always published") can be
silently broken by caller params. To make the promise explicit, assert it over the merged
result and raise:

```elixir
defvariant published(params \\ %{}), for: :post do
  base_params = %{published_at: DateTime.utc_now(), draft: false}
  result_params = Map.merge(base_params, params)

  if Post.published?(result_params),
    do: result_params,
    else: raise("params contradict the published preset")
end
```

A misuse like `build_published_post_struct(%{draft: true})` now fails at the factory
boundary instead of producing a self-contradictory record. The same shape works in the
opposite polarity (a `draft` variant raising when the params imply a published post).

Note the check runs on raw params, before lazy evaluation — the predicate cannot see
resolved values of lazy (function) fields.
