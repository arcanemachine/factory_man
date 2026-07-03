# Cookbook

Recipes for common factory patterns. The full API reference lives in the
[`FactoryMan` module documentation](https://hexdocs.pm/factory_man/FactoryMan.html).

## Building associations

Use `FactoryMan.assoc/4` to let callers pass a prebuilt association, params to build one from,
or nothing at all:

```elixir
deffactory post(params \\ %{}), struct: Post do
  base_params = %{title: FactoryMan.sequence("post")}

  params =
    Map.put(params, :author, FactoryMan.assoc(params, :author, &build_author_struct/1, struct: Author))

  Map.merge(base_params, params)
end

build_post_struct()                          # builds a default author
build_post_struct(%{author: my_author})      # reuses the given struct
build_post_struct(%{author: %{name: "Ann"}}) # builds an author from params
```

In merge-style factories, resolve into `params` (as above), not into the defaults map — the
final `Map.merge` would clobber a resolved default with the caller's raw input. Factories
with `body: :struct` don't merge, so they can use `FactoryMan.assoc/4` directly in field
position.

The `struct:` option raises on a struct of the wrong type — without it, a mistyped value
would be reused silently. See `FactoryMan.assoc/4` for the full semantics (`:inherit`
defaults, optional associations via `on_nil: :keep` and `on_missing: nil`) and
`FactoryMan.assoc_list/4` for `has_many`-style lists.

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
