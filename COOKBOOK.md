# Cookbook

This guide is a practical path from a first factory to the patterns that tend to appear in a
real test suite. It uses the same account-and-blog examples as the rest of the documentation so
that you can move between the [README](README.md), this cookbook, and the
[`FactoryMan` API reference](https://hexdocs.pm/factory_man/FactoryMan.html) without learning a
new example domain each time.

The examples assume Ecto schemas such as `MyApp.Accounts.User`, `MyApp.Blog.Post`, and
`MyApp.Blog.Tag`. Replace those modules and fields with the ones in your application.

Two conventions appear throughout the guide:

- Struct factories receive a map, define defaults in `base_params`, and finish with
  `Map.merge(base_params, params)` so caller values win.
- Helpers are called with the module name, such as `FactoryMan.sequence(...)` and
  `FactoryMan.assoc(...)`. Only `deffactory` and `defvariant` are imported by `use FactoryMan`.

## Start with one useful factory

A factory is an ordinary module that uses `FactoryMan`. Configure your repo once, alias the schema,
and return a map of fields from the factory body:

```elixir
defmodule MyApp.Factory do
  use FactoryMan, repo: MyApp.Repo

  alias MyApp.Accounts.User

  deffactory user(params \\ %{}), struct: User do
    base_params = %{
      username: FactoryMan.sequence("user"),
      email: FactoryMan.sequence(:email, fn n -> "user#{n}@example.com" end),
      role: "member",
      joined_at: fn -> DateTime.utc_now() end
    }

    Map.merge(base_params, params)
  end
end
```

The defaults make the factory useful without arguments, while the final merge keeps individual
tests in control:

```elixir
test "shows the member dashboard" do
  user = MyApp.Factory.build_user_struct(%{username: "alice"})

  assert user.username == "alice"
  assert user.role == "member"
  assert user.id == nil
end
```

FactoryMan builds the struct for you. Do not return `%User{}` from a normal struct factory; use
`body: :struct` only when you deliberately need direct control over struct construction.

### Choose the result that matches the test

A struct factory generates several related functions. Use the function that matches the boundary
you are testing instead of building one representation and converting it by hand.

| The test needs                            | Use                            |
| ----------------------------------------- | ------------------------------ |
| An in-memory record                       | `build_user_struct/0,1`        |
| An atom-keyed input map                   | `build_user_params/0,1`        |
| A string-keyed request map                | `build_user_string_params/0,1` |
| Several independently built values        | The matching `*_list` function |
| A row that already exists in the database | `insert_user/0,1,2`            |

Use params when exercising a changeset or context boundary:

```elixir
test "accepts valid registration attributes" do
  attrs = MyApp.Factory.build_user_params(%{username: "alice"})

  assert %Ecto.Changeset{valid?: true} =
           MyApp.Accounts.User.changeset(%MyApp.Accounts.User{}, attrs)
end
```

Use string params when the real caller supplies string keys, as a controller or API client would:

```elixir
test "creates a user through the API", %{conn: conn} do
  params = MyApp.Factory.build_user_string_params(%{username: "alice"})

  conn = post(conn, ~p"/api/users", %{"user" => params})

  assert %{"username" => "alice"} = json_response(conn, 201)
end
```

Params builders first build the struct and then remove Ecto metadata and persistence-only fields.
That is why they are preferable to calling `Map.from_struct/1` yourself.

Use an insert when persistence is part of the behavior under test:

```elixir
test "loads a user by username" do
  user = MyApp.Factory.insert_user(%{username: "alice"})

  assert MyApp.Repo.get_by!(MyApp.Accounts.User, username: "alice").id == user.id
end
```

Repo options can be passed as the final argument:

```elixir
MyApp.Factory.insert_user(%{username: "alice"}, returning: true)
```

### Build several independent values

List builders invoke the factory once per item. Sequences, lazy values, hooks, and association
normalization therefore run independently for every result:

```elixir
users = MyApp.Factory.build_user_struct_list(3, %{role: "moderator"})

assert length(users) == 3
assert Enum.all?(users, &(&1.role == "moderator"))
assert users |> Enum.map(& &1.username) |> Enum.uniq() |> length() == 3
```

The same pattern applies to params and inserts:

```elixir
attrs_list = MyApp.Factory.build_user_params_list(3)
inserted_users = MyApp.Factory.insert_user_list(3, %{role: "moderator"})
```

If you modify an already-built struct before inserting it, keep the factory's insert hooks by using
`insert_user_struct/1,2` rather than calling the repo directly:

```elixir
user = MyApp.Factory.build_user_struct()
edited_user = %{user | username: "edited"}

MyApp.Factory.insert_user_struct(edited_user)
```

## Make defaults realistic

Useful defaults should resemble valid application data, avoid accidental collisions, and defer
work that may be overridden by the caller.

### Generate unique values with sequences

The simplest sequence prefixes a counter with a string:

```elixir
FactoryMan.sequence("user")
# "user0", then "user1", then "user2", ...
```

A formatter gives the counter an application-specific shape:

```elixir
FactoryMan.sequence(:email, fn n -> "user#{n}@example.com" end)
FactoryMan.sequence(:order, fn n -> "ORD-#{n}" end, start_at: 1000)
```

A list formatter cycles through a small set of values:

```elixir
FactoryMan.sequence(:role, ["admin", "member", "guest"])
```

Cycling values are useful for varied data, but they are not unique. Use a formatter when a database
constraint requires uniqueness.

Reset sequence state when a test asserts exact generated values:

```elixir
setup do
  FactoryMan.Sequence.reset()
  :ok
end
```

Sequence state is shared, so tests that reset and assert exact sequence positions should not race
with other tests using the same sequence names.

### Compute values lazily

Function values are evaluated when the factory builds. A zero-arity function computes a fresh
value, and a one-arity function receives the containing map:

```elixir
deffactory user(params \\ %{}), struct: User do
  base_params = %{
    username: FactoryMan.sequence("user"),
    role: "member",
    joined_at: fn -> DateTime.utc_now() end,
    display_name: fn user -> "#{user.username} (#{user.role})" end
  }

  Map.merge(base_params, params)
end
```

This is useful in a test that cares about a value derived from another caller-controlled field:

```elixir
user = MyApp.Factory.build_user_struct(%{username: "alice", role: "admin"})

assert user.display_name == "alice (admin)"
```

Lazy values are resolved in two passes. The zero-arity functions run first, then the one-arity
functions receive the result. A one-arity function can therefore read a plain field such as
`username`, or a zero-arity field such as `joined_at`, but not another one-arity field, which is
still a function reference when it runs:

```elixir
base_params = %{
  role: "member",
  joined_at: fn -> DateTime.utc_now() end,
  # Reads a plain field and a resolved zero-arity field
  summary: fn user -> "#{user.role} since #{user.joined_at.year}" end
}
```

Because the caller's params are merged before any of this happens, an override flows into the
derived value as well:

```elixir
user = MyApp.Factory.build_user_struct(%{role: "admin"})

assert user.summary =~ "admin since"
```

Lazy defaults also avoid work when a caller supplies an override. This matters most when the
default builds another record:

```elixir
base_params = %{
  author: fn -> MyApp.Factory.Accounts.build_user_struct() end,
  tags: []
}

Map.merge(base_params, params)
```

The author is built only when the default survives the final merge. An eager call such as
`author: build_user_struct()` runs even when the caller supplies an author.

## Name recurring scenarios with variants

A variant is a small preprocessor for a base factory. Use one when tests repeatedly need the same
kind of record:

```elixir
defvariant admin(params \\ %{}), for: :user do
  base_params = %{role: "admin"}

  Map.merge(base_params, params)
end

defvariant guest(params \\ %{}), for: :user do
  base_params = %{role: "guest", username: "guest"}

  Map.merge(base_params, params)
end
```

FactoryMan combines the variant and base names:

```elixir
admin = MyApp.Factory.build_admin_user_struct()
guest = MyApp.Factory.insert_guest_user()

assert admin.role == "admin"
assert guest.role == "guest"
```

A variant runs before the base factory. With the canonical merge order, callers can still override
the preset:

```elixir
user = MyApp.Factory.build_admin_user_struct(%{role: "owner"})
assert user.role == "owner"
```

That behavior is useful for defaults. If the name promises an invariant that callers must not
contradict, validate it explicitly as shown in [Validated presets](#validated-presets).

Variants may build on other variants:

```elixir
defvariant senior(params \\ %{}), for: :admin_user do
  Map.merge(%{display_name: "Senior administrator"}, params)
end

MyApp.Factory.build_senior_admin_user_struct()
```

Use `as:` when the combined name would be awkward:

```elixir
defvariant moderator(params \\ %{}), for: :user, as: :mod do
  Map.merge(%{role: "moderator"}, params)
end

MyApp.Factory.build_mod_struct()
```

## Build related data

Ecto relationships are where factory setup can become noisy. Prefer declarative associations for
direct Ecto associations, and be explicit about whether the test needs an in-memory graph or rows
that already exist in the database.

Two tools cover different jobs:

- **Declarative `associations:`** — for in-memory graphs whose wiring is fixed at definition time.
  It normalizes caller params *before* the body runs, which is what keeps the canonical
  `Map.merge(base_params, params)` ending safe.
- **`FactoryMan.assoc/3,4`** — for associations that must be inserted, or whose params depend on
  another association resolved earlier in the same body. These factories usually declare
  `body: :struct` and read params selectively; that is a legitimate shape for this kind of work,
  not a shortcut.

The two do not mix inside one params body. Resolving an association imperatively and then ending
with `Map.merge(base_params, params)` puts the caller's raw params map back over the struct you
just resolved:

```elixir
# Wrong: the merge restores %{author: %{username: "alice"}} over the resolved struct
deffactory post(params \\ %{}), struct: Post do
  author = FactoryMan.assoc(params, :author, &build_user_struct/1)

  Map.merge(%{title: "A post", author: author}, params)
end
```

Use declarative associations for that factory, or switch it to `body: :struct` and build the
struct yourself.

### Accept nested params and existing structs

Suppose account and blog factories live in separate modules:

```elixir
defmodule MyApp.Factory.Accounts do
  use FactoryMan, extends: MyApp.Factory

  alias MyApp.Accounts.User

  deffactory user(params \\ %{}), struct: User do
    base_params = %{
      username: FactoryMan.sequence("user"),
      email: FactoryMan.sequence(:email, fn n -> "user#{n}@example.com" end)
    }

    Map.merge(base_params, params)
  end
end

defmodule MyApp.Factory.Blog do
  use FactoryMan, extends: MyApp.Factory

  alias MyApp.Blog.{Post, Tag}

  deffactory tag(params \\ %{}), struct: Tag do
    base_params = %{name: FactoryMan.sequence("tag")}

    Map.merge(base_params, params)
  end

  deffactory post(params \\ %{}),
    struct: Post,
    associations: [author: {MyApp.Factory.Accounts, :user}, tags: :tag] do
    base_params = %{
      title: FactoryMan.sequence("post", fn n -> "Post ##{n}" end),
      content: "A post written for a test",
      author: fn -> MyApp.Factory.Accounts.build_user_struct() end,
      tags: []
    }

    Map.merge(base_params, params)
  end
end
```

An atom such as `:tag` names a factory in the current module. A tuple such as
`{MyApp.Factory.Accounts, :user}` names a factory in another module.

Callers can now supply nested params:

```elixir
test "builds a post from nested API-style input" do
  post =
    MyApp.Factory.Blog.build_post_struct(%{
      title: "Testing with factories",
      author: %{username: "alice"},
      tags: [%{name: "elixir"}, %{name: "testing"}]
    })

  assert post.author.username == "alice"
  assert Enum.map(post.tags, & &1.name) == ["elixir", "testing"]
end
```

Existing structs are reused. A plural association may mix existing structs and params maps:

```elixir
user = MyApp.Factory.Accounts.build_user_struct(%{username: "existing"})
tag = MyApp.Factory.Blog.build_tag_struct(%{name: "existing-tag"})

post =
  MyApp.Factory.Blog.build_post_struct(%{
    author: user,
    tags: [tag, %{name: "new-tag"}]
  })

assert post.author === user
assert hd(post.tags) === tag
```

Only association keys supplied by the caller are normalized. Missing keys remain missing until the
factory body supplies its normal defaults. For a singular association, explicit `nil` stays `nil`;
for a plural association, use `[]` for no related values.

Declarative associations build structs in memory. They do not automatically insert associated
records. They support direct Ecto associations; embeds and `:through` associations are not
supported.

Calling `insert_post/1` with a nested struct still persists that struct, because Ecto cascades the
insert. The nested record is written directly by the repo, so the associated factory's
`before_insert` and `after_insert` hooks do not run for it. When those hooks matter, insert the
association first and pass the result:

```elixir
author = MyApp.Factory.Accounts.insert_user()
post = MyApp.Factory.Blog.insert_post(%{author: author})
```

### Insert a dependency when the database requires it

Sometimes the schema only needs a foreign key and the related row must already exist. Make that
database dependency clear in the factory:

```elixir
deffactory audit_event(params \\ %{}), struct: AuditEvent do
  base_params = %{
    action: "user.created",
    user_id:
      Map.get_lazy(params, :user_id, fn ->
        MyApp.Factory.Accounts.insert_user().id
      end)
  }

  Map.merge(base_params, params)
end
```

`Map.get_lazy/3` avoids inserting a user when the caller supplies `user_id`:

```elixir
user = MyApp.Factory.Accounts.insert_user()
event = MyApp.Factory.insert_audit_event(%{user_id: user.id})

assert event.user_id == user.id
```

Use this pattern when persistence is genuinely required. For ordinary in-memory associations,
`build_*_struct` keeps tests faster and makes the dependency smaller.

### Resolve associations imperatively

`FactoryMan.assoc/3,4` reads one association from the factory's params and resolves it. Use it when
the association must be inserted, when its params depend on an association resolved earlier, or when
the builder is a hand-written helper rather than a plain factory function:

```elixir
deffactory bridge(params \\ %{}), struct: Bridge, body: :struct do
  # An explicit `nil` means a bridge with no supplier property
  supplier_property =
    FactoryMan.assoc(params, :supplier_property, &insert_supplier_property/1,
      struct: SupplierProperty
    )

  # The next association inherits a value derived from the previous one
  master_property =
    FactoryMan.assoc(params, :master_property, &insert_master_property/1,
      struct: MasterProperty,
      inherit: %{supplier_property_id: supplier_property && supplier_property.id}
    )

  %Bridge{supplier_property: supplier_property, master_property: master_property}
end
```

`FactoryMan.assoc_list/3,4` does the same for a plural association. Both have value forms —
`FactoryMan.resolve_assoc/2,3` and `FactoryMan.resolve_assoc_list/2,3` — for helper functions that
already hold the value instead of a params map:

```elixir
def insert_post_for(author_or_params) do
  author = FactoryMan.resolve_assoc(author_or_params, &build_user_struct/1, struct: User)

  insert_post(%{author: author})
end
```

Use `inherit: %{...}` to place defaults beneath supplied params. Use `struct:` when you want both
incoming structs and builder results checked against an expected type.

#### What each input resolves to

All four tools agree on nil: an explicit `nil` from the caller is a decision, and it is preserved.
They differ only in what an *absent* key means, because only the keyed tools can see that.

| Caller supplies | `associations:` | `assoc/3,4` | `resolve_assoc/2,3` | `assoc_list/3,4` | `resolve_assoc_list/2,3` |
| --- | --- | --- | --- | --- | --- |
| key absent | body default | build (or `nil` with `default: nil`) | n/a | `[]` | n/a |
| `nil` | `nil` | `nil` | `nil` | raise | raise |
| params map | build | build | build | raise | raise |
| a struct | reuse | reuse | reuse | raise | raise |
| list of maps/structs | raise (singular) / resolve each (plural) | raise | raise | resolve each | resolve each |
| `nil` inside a list | raise | — | — | raise | raise |

A factory that wants a record even when the caller passes `nil` says so in its own body, where the
rule is visible:

```elixir
author = FactoryMan.assoc(params, :author, &build_user_struct/1) || build_user_struct()
```

## Model non-schema inputs

Factories are also useful for request payloads, job arguments, adapter options, and other values
that are not structs. Omit `struct:` and return whatever shape the application consumes:

```elixir
deffactory api_payload(params \\ %{}) do
  base_params = %{
    action: "create",
    resource: "user",
    request_id: fn -> System.unique_integer([:positive]) end
  }

  Map.merge(base_params, params)
end

deffactory request_options(overrides \\ []) do
  base_options = [
    timeout: 5_000,
    retries: 3,
    label: fn options -> "timeout-#{options[:timeout]}" end
  ]

  Keyword.merge(base_options, overrides)
end
```

Non-struct factories use the shorter `build_*` names:

```elixir
payload = MyApp.Factory.build_api_payload(%{resource: "post"})
options = MyApp.Factory.build_request_options(timeout: 1_000)
payloads = MyApp.Factory.build_api_payload_list(3)

assert payload.resource == "post"
assert options[:label] == "timeout-1000"
assert length(payloads) == 3
```

They can return maps, keyword lists, strings, tuples, or any other value. They do not generate
struct, params, or insert functions because there is no schema to provide those semantics.

## Catch input mistakes with strict params

A misspelled key in a merge-style factory normally fails later during struct construction. A direct
struct factory may ignore it entirely. Opt in to strict params when you want the factory boundary to
report the mistake immediately:

```elixir
deffactory user(params \\ %{}), struct: User, strict: true do
  base_params = %{
    username: FactoryMan.sequence("user"),
    email: FactoryMan.sequence(:email, fn n -> "user#{n}@example.com" end)
  }

  Map.merge(base_params, params)
end
```

Now a typo fails where it was introduced:

```elixir
MyApp.Factory.build_user_struct(%{usernme: "alice"})
# ** (ArgumentError) unknown params [:usernme] for strict factory :user ...
```

Strict validation also applies through params builders, inserts, list builders, and variants.
Set it once for a factory module when that is the desired default:

```elixir
defmodule MyApp.Factory.Accounts do
  use FactoryMan, extends: MyApp.Factory, strict: true

  # Account factories are strict unless one overrides the option.
end
```

A factory may intentionally accept an input that is not a struct field. Allow that input explicitly:

```elixir
deffactory user_from_domain(params \\ %{}),
  struct: User,
  body: :struct,
  strict: [allow: [:domain]] do
  domain = Map.get(params, :domain, "example.com")

  %User{
    username: FactoryMan.sequence("derived-user"),
    email: "derived@#{domain}"
  }
end
```

Keys outside the struct fields and the allowlist still raise. Strict params are ignored for
non-struct factories because those factories have no struct field set to validate against.

## Organize a growing factory suite

A single factory module is convenient at first. As the application grows, keep shared configuration
in a small parent module and organize child factories around application contexts.

```text
test/support/
  factory.ex                    # repo, shared hooks, shared helpers
  factory/
    accounts.ex                 # user and account factories
    blog.ex                     # post and tag factories
    blog/comments.ex            # comment factories
```

### Share configuration with `extends:`

The parent owns configuration that should be consistent across the suite:

```elixir
defmodule MyApp.Factory do
  use FactoryMan,
    repo: MyApp.Repo,
    hooks: [after_insert: &__MODULE__.reset_associations/1]

  def reset_associations(%_{} = struct) do
    Ecto.reset_fields(struct, struct.__struct__.__schema__(:associations))
  end
end
```

Child modules inherit the repo, hooks, and public helper functions:

```elixir
defmodule MyApp.Factory.Accounts do
  use FactoryMan, extends: MyApp.Factory

  alias MyApp.Accounts.User

  deffactory user(params \\ %{}), struct: User do
    base_params = %{username: FactoryMan.sequence("user")}

    Map.merge(base_params, params)
  end
end
```

The `after_insert` hook resets loaded associations so an inserted result resembles a record returned
by a fresh query. This prevents tests from accidentally depending on associations that happened to
be present during construction.

Inheritance chains may have more than one level, and a child may override inherited options. Keep
the parent focused on shared behavior; domain-specific factory definitions belong in the child
modules that use them.

### Use hooks for cross-cutting behavior

Hooks transform values at defined points in the build and insert pipeline. A factory-local hook is
useful when a rule belongs to one kind of data:

```elixir
defmodule MyApp.Factory.Events do
  use FactoryMan

  def add_test_source(params), do: Map.put_new(params, :source, "test")

  deffactory event(params \\ %{}),
    hooks: [before_build_params: &__MODULE__.add_test_source/1] do
    base_params = %{name: "user.created"}

    Map.merge(base_params, params)
  end
end
```

A module-level hook is better for behavior shared by every factory in that module. Parent, child,
and factory hooks merge by hook name, with the more specific level taking precedence when the same
hook is configured again.

For a normal struct factory, the build path is:

```text
params validation
→ before_build_params
→ association normalization
→ factory body and lazy evaluation
→ after_build_params
→ before_build_struct
→ struct!/2
→ after_build_struct
```

An insert continues with `before_insert`, the repo insert, and `after_insert`. This is also why
`insert_*_struct` is preferable to a direct repo call after editing a built struct: it keeps the
insert hooks in the path.

## Handle specialized construction

Most factories should return params maps. The following tools are useful when the value does not
follow the ordinary table-backed Ecto path.

### Build embedded schemas

Embedded schemas use the normal struct and params builders, but FactoryMan skips insert functions
automatically:

```elixir
defmodule MyApp.Factory.Settings do
  use FactoryMan, extends: MyApp.Factory

  alias MyApp.Accounts.Settings

  deffactory settings(params \\ %{}), struct: Settings do
    base_params = %{
      theme: "dark",
      notifications: true
    }

    Map.merge(base_params, params)
  end
end
```

Use the result in tests just like another in-memory struct:

```elixir
settings = MyApp.Factory.Settings.build_settings_struct(%{theme: "light"})
attrs = MyApp.Factory.Settings.build_settings_params()

assert settings.theme == "light"
assert attrs.notifications
```

There is no `insert_settings` because an embedded schema has no table of its own.

### Return a struct directly with `body: :struct`

Use `body: :struct` when construction is genuinely easier after another struct has been built, or
when the body needs control that a params map cannot express:

```elixir
deffactory anonymized_user(params \\ %{}), struct: User, body: :struct do
  user = build_user_struct(params)

  %{user |
    username: "anonymous",
    email: "redacted@example.com",
    display_name: "Anonymous user"
  }
end
```

The full function family is still generated:

```elixir
MyApp.Factory.build_anonymized_user_struct()
MyApp.Factory.build_anonymized_user_params()
MyApp.Factory.build_anonymized_user_struct_list(3)
MyApp.Factory.insert_anonymized_user()
```

Params-stage hooks are skipped because the body does not perform params-to-struct conversion.
Lazy values in the returned struct are still resolved, and `after_build_struct` and insert hooks
still run. In the wrapper above, an `after_build_struct` hook
runs once inside `build_user_struct/1` and again for the wrapping factory.

Use direct struct bodies sparingly. A normal params body is easier to extend, compose, and inspect.

## Build presets that keep their promises

Variants are ideal for caller-overridable defaults. Two more specialized patterns help when a preset
must transform a finished value or enforce an invariant.

### Post-build presets

A variant cannot transform the finished struct because it runs before the base factory. Wrap the
base builder in a direct struct factory when the transformation belongs after construction:

```elixir
deffactory verified_user(params \\ %{}), struct: User, body: :struct do
  user = build_user_struct(params)

  %{user | verified_at: DateTime.utc_now()}
end
```

This retains params, list, and insert functions under the new factory name. Remember the
`after_build_struct` double-run caveat when the wrapper calls another factory that has the same
hook.

### Validated presets

A variant's defaults may be overridden. If a name promises a property such as “published,” validate
the merged params before delegating to the base factory:

```elixir
defvariant published(params \\ %{}), for: :post do
  base_params = %{
    published_at: DateTime.utc_now(),
    draft: false
  }

  result_params = Map.merge(base_params, params)

  if result_params[:draft] or is_nil(result_params[:published_at]) do
    raise ArgumentError, "published posts require published_at and draft: false"
  end

  result_params
end
```

A contradictory call now fails at the factory boundary:

```elixir
MyApp.Factory.Blog.build_published_post_struct(%{draft: true})
# ** (ArgumentError) published posts require published_at and draft: false
```

The validation sees raw params before lazy evaluation. Do not write a predicate that expects a
function-valued field to have been resolved already.

## Inspect factories when names are dynamic

Most tests should call generated functions directly. Reflection is useful for test helpers or tools
that receive a factory name at runtime:

```elixir
def build_named(factory_module, factory_name, params \\ %{}) do
  unless factory_name in factory_module.__factory_man__(:factories) do
    raise ArgumentError, "unknown factory #{inspect(factory_name)}"
  end

  if is_nil(factory_module.__factory_man__(:opts, factory_name)[:struct]) do
    raise ArgumentError, "factory #{inspect(factory_name)} does not build a struct"
  end

  apply(factory_module, :"build_#{factory_name}_struct", [params])
end
```

Checking `__factory_man__(:factories)` before constructing the function name limits dispatch to
registered factories. Variants appear under their full registered names.

For debugging, inspect the resolved options at module or factory level:

```elixir
MyApp.Factory.Accounts.__factory_man__(:opts)
MyApp.Factory.Accounts.__factory_man__(:opts, :user)
```

This can answer whether a child inherited the expected repo, hook, strict setting, or struct module
without guessing from generated function names.

## Habits that keep factories easy to use

- **Merge caller params last.** `Map.merge(base_params, params)` makes defaults predictable and
  keeps tests in control.
- **Pass maps to struct factories.** Keyword lists are appropriate only when the factory itself
  accepts and returns keyword-list data.
- **Use generated names.** A struct factory named `user` generates `build_user_struct`,
  `build_user_params`, and `insert_user`; it does not generate `build_user`.
- **Return params from normal struct factories.** Return a struct only with `body: :struct`.
- **Qualify helpers.** Call `FactoryMan.sequence`, `FactoryMan.assoc`, and
  `FactoryMan.assoc_list`; `use FactoryMan` imports only the definition macros.
- **Let an explicit `nil` mean "none".** Every association tool preserves a caller's `nil`. If a
  factory needs a record regardless, add the fallback in its own body.
- **Build unless persistence matters.** An in-memory graph is usually enough. Insert when a query,
  constraint, or foreign key requires a row.
- **Prefer lazy association defaults.** They avoid unnecessary work when callers override a
  relationship.
- **Avoid recursive defaults.** A default user that builds a post whose default author builds
  another user will never terminate.
- **Reset sequences only when exact positions matter.** Most tests should assert behavior rather
  than the counter value.
- **Keep the cookbook for recipes and the API reference for exhaustive semantics.** When an edge
  case matters, consult the [`FactoryMan` module documentation](https://hexdocs.pm/factory_man/FactoryMan.html).
