# Cookbook

This guide is a practical path from a first factory to the patterns that tend to appear in a
real test suite. It uses the same account-and-blog examples as the rest of the documentation so
that you can move between the [README](README.md), this cookbook, and the
[`FactoryMan` API reference](https://hexdocs.pm/factory_man/FactoryMan.html) without learning a
new example domain each time.

The examples assume Ecto schemas such as `MyApp.Accounts.User`, `MyApp.Blog.Author`,
`MyApp.Blog.Post`, `MyApp.Blog.Tag`, and `MyApp.Blog.Comment`. Replace those modules and fields
with the ones in your application.

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

Use a struct when the code under test takes a record and no database row is needed:

```elixir
test "formats a display name" do
  user = MyApp.Factory.build_user_struct(%{username: "alice"})

  assert MyApp.Accounts.display_name(user) == "@alice"
end
```

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

### Build several independent values

List builders invoke the factory once per item. Sequences, lazy values, hooks, and association
builders therefore run independently for every result:

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

assert user.summary == "admin since #{user.joined_at.year}"
```

Lazy defaults also avoid work when a caller supplies an override. An eager default is computed
before the merge, even when the caller's value replaces it:

```elixir
base_params = %{
  # Advances the sequence only when the caller does not supply a username
  username: fn -> FactoryMan.sequence("user") end
}

Map.merge(base_params, params)
```

For associations, declare a builder with `assocs:` instead (see
[Build related data](#build-related-data)). The builder is the default, and it runs only when the
caller does not supply the key.

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
contradict, force the value or validate it explicitly (see
[Build presets that keep their promises](#build-presets-that-keep-their-promises)).

### Combine variants for one test

Pass `variants:` to any generated function to apply several variants in one build:

```elixir
MyApp.Factory.build_user_struct(%{username: "alice"}, variants: [:admin, :confirmed])
MyApp.Factory.insert_user(%{}, variants: [:admin, :confirmed])
```

List variants by the name in their `defvariant` (`:admin`, not `:admin_user`). The caller's params
win, and a later variant wins over an earlier one:

```elixir
user = MyApp.Factory.build_user_struct(%{}, variants: [:admin, :guest])
assert user.role == "guest"
```

`insert_*` takes one option list: FactoryMan uses `:variants`, and every other option goes to
`Repo.insert!/2` unchanged, as in `insert_user(%{}, variants: [:admin], returning: true)`.

### Build on another variant

When a variant always includes another, declare it with `extends:`. The variant wins over the
variants it extends:

```elixir
defvariant senior(params \\ %{}), for: :user, extends: [:admin] do
  Map.merge(%{display_name: "Senior administrator"}, params)
end

user = MyApp.Factory.build_senior_user_struct()
assert user.role == "admin"
```

A variant that only extends others names a combination that many tests use:

```elixir
defvariant confirmed_admin, for: :user, extends: [:admin, :confirmed]

MyApp.Factory.build_confirmed_admin_user_struct()
```

`for:` always names the base factory, and each extended variant must be defined earlier in the
same module.

### Choose defaults or forced values

A variant's defaults can be overridden by the caller; its forced values cannot. Use defaults for
convenience presets, and forced values for presets whose name is a promise. A variant that only
sets values declares them:

```elixir
# Defaults: the caller can override the role
defvariant admin, for: :user, defaults: %{role: "admin"}

# Forced: a banned user is always banned, whatever the caller passes
defvariant banned, for: :user, force: %{banned: true}
```

`defaults:` and `force:` are evaluated on every build. Wrap a value in a lazy function when it
should only be computed when the caller does not supply the key:

```elixir
defvariant confirmed, for: :user, defaults: %{confirmed_at: fn -> DateTime.utc_now() end}
```

When the values are computed from the params, write a body instead. Which side of
`Map.merge/2` the body puts `params` on decides who wins:

```elixir
defvariant renamed(params \\ %{}), for: :user do
  Map.merge(%{display_name: String.upcase(params[:username] || "user")}, params)
end
```

Add `:factory_man` to `import_deps` in `.formatter.exs`, so `mix format` keeps a variant without a
body free of parentheses.

In a `variants:` list, a variant that forces a value wins over the caller and over every variant
after it in the list.

Use `as:` when the combined name would be awkward:

```elixir
defvariant moderator(params \\ %{}), for: :user, as: :mod do
  Map.merge(%{role: "moderator"}, params)
end

MyApp.Factory.build_mod_struct()
```

## Build related data

Ecto relationships are where factory setup can become noisy. Declare association builders with
`assocs:`, and be explicit about whether the test needs an in-memory graph or rows that already
exist in the database.

### Declare association builders

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
  alias MyApp.Factory.Accounts

  deffactory tag(params \\ %{}), struct: Tag do
    base_params = %{name: FactoryMan.sequence("tag")}

    Map.merge(base_params, params)
  end

  deffactory post(params \\ %{}),
    struct: Post,
    assocs: [author: &Accounts.build_user_struct/1, tags: &build_tag_struct/1] do
    base_params = %{
      title: "#{params.author.username}'s first post",
      content: "A post written for a test"
    }

    Map.merge(base_params, params)
  end
end
```

Every declared key is resolved **before** the body runs, so the body always receives it resolved
(here, `params.author` is a `%User{}`).

**The builder is the default.** An absent key is built with `%{}` (a singular association) or
resolves to `[]` (a plural one). Don't also put a default for a declared key in `base_params`; it
is never used. Use `default:` to change what an absent key means:

```elixir
assocs: [
  # No editor unless the caller supplies one
  editor: {&Accounts.build_user_struct/1, default: nil},
  # A post comes with two tags
  tags: {&build_tag_struct/1, default: [%{name: "elixir"}, %{}]}
]
```

Callers can supply nested params, existing structs, or `nil`. A plural association may mix
existing structs and params maps:

```elixir
test "builds a post from nested input" do
  user = MyApp.Factory.Accounts.build_user_struct(%{username: "existing"})
  tag = MyApp.Factory.Blog.build_tag_struct(%{name: "existing-tag"})

  post = MyApp.Factory.Blog.build_post_struct(%{author: user, tags: [tag, %{name: "new-tag"}]})

  assert post.author === user
  assert [^tag, %Tag{name: "new-tag"}] = post.tags
end
```

The rules for each kind of caller value are in the
[`FactoryMan` module documentation](https://hexdocs.pm/factory_man/FactoryMan.html#module-associations)
and the [cheat sheet](CHEATSHEET.cheatmd).

### Require an association

An explicit `nil` normally resolves to `nil`, because "no associated value" is often a real state.
When it never is, mark the key `required: true`:

```elixir
deffactory post(params \\ %{}),
  struct: Post,
  assocs: [author: {&Accounts.build_user_struct/1, required: true}] do
  Map.merge(%{title: "#{params.author.username}'s first post"}, params)
end
```

```elixir
MyApp.Factory.Blog.build_post_struct(%{author: nil})
# ** (ArgumentError) association :author in factory :post in MyApp.Factory.Blog is required, got nil
```

`required: true` means the key resolves to a value, not that the caller must supply it: an absent
key still builds. A builder that returns `nil` for a required key also raises. Builders declared
below a required key can rely on it being set.

It applies to singular associations only (a plural association already raises on `nil`, and
`required:` is not a check that the list is non-empty), and it can't be combined with
`default: nil`. It is checked when the key resolves, so a body that puts `nil` back afterwards is
not caught. A variant can add `required: true` to a key, but can't relax a base factory's.

### Chain associations

Keys resolve top to bottom. A 2-arity builder also receives the factory params, with every key
declared above it already resolved:

```elixir
deffactory comment(params \\ %{}),
  struct: Comment,
  assocs: [
    author: &Accounts.build_user_struct/1,
    post: fn params, factory_params ->
      # The comment's post defaults to one written by the same author
      build_post_struct(Map.put_new(params, :author, factory_params.author))
    end
  ] do
  Map.merge(%{body: "Nice post"}, params)
end
```

In `factory_params`, the current key and every key declared below it are hidden until they
resolve. Undeclared keys are visible as the caller passed them, which is how a builder can read
an input that is not a declarable association. The body's `base_params` have not been computed
yet, so a builder that needs one of those values computes it itself. A caller-supplied struct is
reused without calling the builder. An earlier key may be `nil` when the caller passed `nil`, so
write builders to handle that.

### Build associations differently in a variant

`defvariant` accepts `assocs:` too. The variant resolves its keys before its body, and the base
factory reuses the resulting structs, since supplied structs are never rebuilt:

```elixir
defvariant guest(params \\ %{}),
  for: :post,
  assocs: [author: &MyApp.Factory.build_guest_user_struct/1] do
  Map.merge(%{title: "A guest post"}, params)
end
```

### Share a declaration

`assocs:` takes any expression that returns a keyword list, so factories can share one:

```elixir
deffactory post(params \\ %{}), struct: Post, assocs: authored() do
  Map.merge(%{title: "A post"}, params)
end

deffactory draft(params \\ %{}), struct: Post, assocs: authored() do
  Map.merge(%{title: "A draft", draft: true}, params)
end

def authored, do: [author: &Accounts.build_user_struct/1]
```

The expression is evaluated at build time, like the body, but the factory's `params` variable is
not in scope in it. It must be written directly in the `deffactory` or `defvariant` call, not in
options held in a module attribute.

### Keep `default:` values literal

`assocs:` is evaluated on **every** build, so a `default:` value is too, whether or not the caller
supplies the key. Any side effect inside one happens every time: an insert, a query, or a
sequence, which advances even when the default goes unused. Keep defaults to literals, and put
build logic in the builder, which runs only when it is needed.

A record at an association position inside `default:` (e.g. `default: %{mentor: %User{}}`) is
rejected, because it has already been built. That check covers only records at association
positions: `%{author_id: MyApp.Factory.Accounts.insert_user().id}` passes it and still inserts a
user on every build.

### Resolve associations imperatively

`FactoryMan.assoc/3,4` and `FactoryMan.assoc_list/3,4` apply the same rules to one key of a
params map, without `required:` or the schema check. Use them where `assocs:` does not fit: a plain helper function, an association
resolved from a value computed in the body, or inside a builder. Their only option is `default:`,
with the same meaning as in `assocs:`:

```elixir
def insert_post_for(params) do
  author = FactoryMan.assoc(params, :author, &MyApp.Factory.Accounts.insert_user/1)

  MyApp.Factory.Blog.insert_post(Map.put(params, :author, author))
end
```

To give an absent key extra params, close over them:

```elixir
FactoryMan.assoc(params, :author, &build_user_struct(Map.merge(%{role: "writer"}, &1)))
```

The helpers return the resolved value and do not modify the params map. In a body that ends with
`Map.merge(base_params, params)`, the merge would put the caller's raw value back over the
resolved one, so handle the key before merging.

When an association is only an input used to derive other fields, and should not be stored on the
struct, drop it:

```elixir
deffactory author(params \\ %{}), struct: Author do
  # Only the user's row and name are needed, not the association itself
  user = FactoryMan.assoc(params, :user, &Accounts.insert_user/1)

  base_params = %{name: user.username, user_id: user.id}

  Map.merge(base_params, Map.drop(params, [:user]))
end
```

When the body changes a resolved association, put the changed value back:

```elixir
deffactory post(params \\ %{}), struct: Post, assocs: [author: &Accounts.build_user_struct/1] do
  # The post's author is always marked as a writer
  author = %{params.author | role: "writer"}

  Map.merge(%{title: "A post"}, Map.put(params, :author, author))
end
```

### Avoid recursive defaults

A self-referential association builds forever when its key is absent: building a user builds
its mentor, which builds its mentor, and so on. So does a mutually recursive pair whose defaults
build each other, such as a user declared with a non-empty `default:` for its posts, where each
post builds its author. (An absent plural key resolves to `[]` unless `default:` says otherwise,
so a list only loops when its default builds something.) FactoryMan raises instead:

```text
** (ArgumentError) association :mentor in factory :user in MyApp.Factory.Accounts is
self-referential: building it by default builds :user again, which recurses forever.
Build path: :user → :mentor → :user → :mentor
Declare it as {builder, default: nil}, or pass a value (nil, a struct, or params).
If the recursion is meant to stop on its own, supply the key at each level instead.
```

Declare such a key with `default: nil` (`default: []` for a list), or pass a value. To build a
fixed number of levels by default, supply the next level's key in the builder:

```elixir
# One default level of mentor, then stop
mentor: fn params -> build_user_struct(Map.put_new(params, :mentor, nil)) end
```

The guard applies to `assocs:`, `FactoryMan.assoc/3,4`, and `FactoryMan.assoc_list/3,4`. It
tracks only default builds (an absent key whose default builds something), so values supplied by
the caller, nested to any depth, always terminate. It cannot see why a recursion would stop, only
that the same default build started again inside itself, so recursion that stops for any reason
other than a supplied key is also rejected. Supply the key at each level instead.

### Build or insert

`assocs:` builders build structs in memory unless the builder inserts. Calling `insert_post/1`
with a built association still persists it, because Ecto cascades the insert. The nested record
is written directly by the repo, so the associated factory's `before_insert` and `after_insert`
hooks do not run for it. When those hooks matter, insert the association first and pass the
result, or use an insert function as the builder:

```elixir
author = MyApp.Factory.Accounts.insert_user()
post = MyApp.Factory.Blog.insert_post(%{author: author})
```

The cascade inserts a built record once for each association that holds it. So when two
`belongs_to` keys share one built record, for example an editor that defaults to the author:

```elixir
assocs: [
  author: &Accounts.build_user_struct/1,
  editor: fn
    params, factory_params when params == %{} -> factory_params.author
    params, _factory_params -> Accounts.build_user_struct(params)
  end
]
```

`build_post_struct/1` gives one shared `%User{}`, but `insert_post/1` inserts two users. To share
one row, insert the record first and pass it for both keys, or add a `before_insert` hook that
inserts it once and puts the persisted record into both fields.

The same happens across a list insert: each item inserts the shared built record again.

```elixir
# Each post inserts the built author again, so a unique column conflicts on the second post
MyApp.Factory.Blog.insert_post_list(2, %{author: MyApp.Factory.Accounts.build_user_struct()})

# The author is inserted once and shared by both posts
MyApp.Factory.Blog.insert_post_list(2, %{author: MyApp.Factory.Accounts.insert_user()})
```

### Get foreign keys into params

`build_*_params` drops a `belongs_to` association and sets its foreign key only when the associated
record has been inserted. With the default builder, the author is only built, so the params have no
author ID:

```elixir
MyApp.Factory.Blog.build_post_params()
# %{title: "post0", author_id: nil, ...}
```

For a changeset or controller test that needs a real foreign key, pass an inserted record:

```elixir
MyApp.Factory.Blog.build_post_params(%{author: MyApp.Factory.Accounts.insert_user()})
# %{title: "post1", author_id: 42, ...}
```

When many tests need it, declare a variant whose builder inserts. The base factory still only
builds, and the inserted author goes through the user factory's insert hooks:

```elixir
defvariant persisted(params \\ %{}), for: :post, assocs: [author: &Accounts.insert_user/1] do
  params
end

MyApp.Factory.Blog.build_persisted_post_params()
# %{title: "post2", author_id: 43, ...}
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

Params can be lost in two ways: a caller misspells a key, or a factory body drops a key it was
given. A misspelled key in a merge-style factory normally fails later during struct construction,
and a direct struct factory may ignore it entirely. A body that forgets its final merge ignores the
caller's values without any error. Opt in to strict params to catch both at the factory:

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

A body that ignores or changes a param it was given fails too:

```elixir
deffactory user(params \\ %{}), struct: User, strict: true do
  %{username: FactoryMan.sequence("user")}
end

MyApp.Factory.build_user_struct(%{username: "alice"})
# ** (ArgumentError) strict factory :user in MyApp.Factory ignored or changed params it was given:
#
#      :username - given "alice", built "user0"
#    ...
```

Strict validation also applies through params builders, inserts, list builders, and variants.
Turn it on in the base factory, so every child factory is strict unless one overrides the option:

```elixir
defmodule MyApp.Factory do
  use FactoryMan, repo: MyApp.Repo, strict: true
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

`allow:` also covers a field that the body changes on purpose, such as a value it normalizes:

```elixir
deffactory account(params \\ %{}), struct: Account, strict: [allow: [:email]] do
  %{email: "user@example.com"}
  |> Map.merge(params)
  |> Map.update!(:email, &String.downcase/1)
end
```

Keys in `allow:` are not checked at all. Other keys outside the struct fields still raise, and
other fields must still come through the body unchanged.

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

Inheritance chains may have more than one level, and a child may override inherited options:

```elixir
defmodule MyApp.Factory.Reporting do
  # Inherits the hooks, and uses another repo
  use FactoryMan, extends: MyApp.Factory, repo: MyApp.ReportingRepo
end

defmodule MyApp.Factory.Reporting.Exports do
  # Inherits MyApp.Factory.Reporting's resolved options, including its repo
  use FactoryMan, extends: MyApp.Factory.Reporting
end
```

Keep the parent focused on shared behavior; domain-specific factory definitions belong in the child
modules that use them.

### Switch off functions the suite does not use

A suite that never calls some generated functions can switch them off in the base factory. Fewer
functions keep autocompletion and the generated docs focused:

```elixir
defmodule MyApp.Factory do
  use FactoryMan,
    repo: MyApp.Repo,
    disable: [string_params: true, params_list: true]
end
```

A factory that needs one of them back enables it again with `false`:

```elixir
deffactory registration(params \\ %{}), struct: Registration, disable: [string_params: false] do
  Map.merge(%{email: FactoryMan.sequence(:email, &"user#{&1}@example.com")}, params)
end
```

`build_*_struct` is always generated, and inserts are switched off with `insert: false`. Check
what a factory has disabled with `__factory_man__(:opts, :registration)[:disable]`.

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

A module-level hook is better for behavior shared by every factory in that module. Hooks must be
remote captures (`&__MODULE__.my_hook/1`); anything else, such as an anonymous function, raises at
compile time. To run several functions at one hook, give a list; they run in order:

```elixir
hooks: [after_insert: [&__MODULE__.reset_associations/1, &__MODULE__.log_insert/1]]
```

For a normal struct factory, the build path is:

```text
params validation
→ before_build_params
→ assocs: resolution
→ factory body and lazy evaluation
→ strict params check (with strict: true)
→ after_build_params
→ before_build_struct
→ struct!/2
→ after_build_struct
```

An insert continues with `before_insert`, the repo insert, and `after_insert`. This is also why
`insert_*_struct` is preferable to a direct repo call after editing a built struct: it keeps the
insert hooks in the path.

### Chain a factory hook with an inherited one

A hook set on a factory is chained with the hooks it inherits from its modules. The order is
onion-style, like middleware: the parent wraps the child. A parent's `before_*` hook runs first,
and a parent's `after_*` hook runs last.

With the `reset_associations/1` parent from "Share configuration with `extends:`", a factory-level
`after_insert` runs before the reset. In the `MyApp.Factory.Blog` module from above:

```elixir
deffactory post(params \\ %{}),
  struct: Post,
  hooks: [after_insert: &__MODULE__.add_comment/1] do
  base_params = %{title: FactoryMan.sequence("post")}

  Map.merge(base_params, params)
end

def add_comment(post) do
  insert_comment(%{post: post})
  post
end
```

`insert_post/0` runs `add_comment/1`, then `reset_associations/1`, so the result still resembles a
freshly queried record. To run a hook after the inherited ones instead (for example, to preload
the comments onto the result), place it explicitly:

```elixir
hooks: [after_insert: {&__MODULE__.preload_comments/1, :after_parent}]
```

The placements are `:before_parent`, `:after_parent`, and `:replace_parent`. A placement applies
to a whole list of hooks. To switch off the inherited hooks for one factory, replace them with an
empty list:

```elixir
hooks: [after_insert: {[], :replace_parent}]
```

`__factory_man__(:opts, :post)` shows each hook name's resolved list in run order.

### Cast values before insert

FactoryMan inserts values exactly as the factory builds them, so a value of the wrong type (e.g.
`"42"` for an integer field) fails in the repo. To convert values to their field types first, as a
changeset would, cast them in a `before_insert` hook:

```elixir
defmodule MyApp.Factory do
  use FactoryMan, repo: MyApp.Repo, hooks: [before_insert: &__MODULE__.cast_fields/1]

  def cast_fields(%schema{} = struct) do
    fields = schema.__schema__(:fields) -- schema.__schema__(:embeds)

    schema
    |> struct()
    |> Ecto.Changeset.cast(Map.take(struct, fields), fields, empty_values: [])
    |> Ecto.Changeset.apply_action!(:insert)
    |> then(&Map.merge(struct, Map.take(&1, fields)))
  end
end
```

A value that cannot be cast raises an `Ecto.InvalidChangesetError` that names the field. The hook
casts the struct's own fields only, not its associations or embeds. It does not run your schema's
`changeset/2` (which would also validate): a required foreign key that an association fills in on
insert would fail validation before the insert.

## Handle specialized construction

Most factories should return params maps. The following tools are useful when the value does not
follow the ordinary table-backed Ecto path.

### Build embedded schemas

Embedded schemas use the normal struct and params builders. They cannot be inserted with Ecto,
so FactoryMan generates no Ecto insert functions for them:

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

There is no `insert_settings` because an embedded schema has no table of its own. To store one
somewhere else, give it an insert function (see
[Insert into other stores](#insert-into-other-stores)).

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

## Insert into other stores

By default, `insert_*` inserts with the repo. An insert target sends a built struct somewhere
else: a search index, a cache, an in-memory store, or an external API stub.

### Insert a plain struct

A plain struct has no Ecto insert. Give it one with `insert:`, a remote capture of arity 2:

```elixir
defmodule MyApp.Factory.Events do
  use FactoryMan, extends: MyApp.Factory

  alias MyApp.Events.Event

  deffactory event(params \\ %{}), struct: Event, insert: &__MODULE__.publish!/2 do
    base_params = %{name: FactoryMan.sequence("event"), payload: %{}}

    Map.merge(base_params, params)
  end

  def publish!(event, _opts) do
    :ok = MyApp.EventBus.publish(event)

    event
  end
end
```

The whole insert family is generated, and the insert hooks run around `publish!/2`:

```elixir
MyApp.Factory.Events.insert_event(%{name: "signed_up"})
MyApp.Factory.Events.insert_event_list(3)
MyApp.Factory.Events.insert_event_struct(event)
```

An insert function receives the built struct and the caller's options (without `:variants`),
and returns the inserted struct. A store that takes no options ignores them, as above.

### Add a named target

`insert_via:` keeps the Ecto insert and adds a second way to insert. Set it in the base factory
to give every factory the target:

```elixir
defmodule MyApp.Factory do
  use FactoryMan,
    repo: MyApp.Repo,
    insert_via: [search: &__MODULE__.index!/2]

  def index!(struct, opts) do
    MyApp.Search.index!(struct, refresh: Keyword.get(opts, :refresh, true))

    struct
  end
end
```

Each struct factory now has an `insert_*_via_search` family:

```elixir
user = insert_user_via_search(%{username: "alice"})
users = insert_user_via_search_list(3, %{}, refresh: false)
post = insert_post_via_search(%{}, variants: [:published])
```

`insert_via:` merges by name: a factory adds its own targets, replaces an inherited one with the
same name, or removes it with `false`:

```elixir
deffactory audit_log(params \\ %{}), struct: AuditLog, insert_via: [search: false] do
  Map.merge(%{action: "login"}, params)
end
```

Targets run no insert hooks, and they do not check whether the struct has already been inserted.
Anything a target needs goes inside its function.

### Insert a row, then index it

A row that a query needs and a search document that a search needs are two steps. Pipe the
inserted row into the target's struct form:

```elixir
user =
  %{username: "alice"}
  |> insert_user()
  |> insert_user_struct_via_search()
```

`insert_user/1` runs the insert hooks and the Ecto insert. `insert_user_struct_via_search/1`
indexes the record it is given, with its database id.

### Do both steps in one target

When most tests need both, make one target do both:

```elixir
use FactoryMan,
  repo: MyApp.Repo,
  insert_via: [indexed: &__MODULE__.insert_and_index!/2]

def insert_and_index!(struct, opts) do
  struct
  |> MyApp.Repo.insert!(opts)
  |> tap(&MyApp.Search.index!(&1, refresh: true))
end
```

```elixir
user = insert_user_via_indexed(%{username: "alice"})
```

The target calls `MyApp.Repo.insert!/2` directly, so the factory's insert hooks do not run.
To get the same result shape as `insert_user/1`, call your hook functions from the target.

### Check where a factory inserts

The resolved targets appear in the factory's options:

```elixir
iex> MyApp.Factory.Accounts.__factory_man__(:opts, :user)[:insert]
:ecto

iex> MyApp.Factory.Accounts.__factory_man__(:opts, :user)[:insert_via]
[search: &MyApp.Factory.index!/2]
```

## Build presets that keep their promises

Variants are ideal for caller-overridable defaults. Three more specialized patterns help when a
preset must force a value, transform a finished value, or enforce an invariant.

### Forced values

When a preset's name is a promise that a caller should not be able to break by accident, merge the
preset's values over the params instead of under them:

```elixir
defvariant banned(params \\ %{}), for: :user do
  Map.merge(params, %{banned: true})
end

MyApp.Factory.build_banned_user_struct(%{banned: false}).banned
# true
```

The forced value also wins over every variant after it in a `variants:` list. Use this form
sparingly: a caller cannot override the value, even on purpose.

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
`__factory_man__(:variants, :user)` lists a factory's variants by the names that `variants:`
accepts, e.g. to build every variant of a factory in a test.

## Habits that keep factories easy to use

The [usage rules](usage-rules.md) list the rules and anti-patterns for writing factories. The
[`FactoryMan` module documentation](https://hexdocs.pm/factory_man/FactoryMan.html) is the full
reference for edge cases.
