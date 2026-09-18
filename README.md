# FactoryMan

An Elixir library for generating test data. Define factories with `deffactory`, and FactoryMan
generates functions for building params, structs, and database records.

Inspired by [ExMachina](https://hex.pm/packages/ex_machina), but with a different API and feature
set.

Looking for recipes? See the [Cookbook](COOKBOOK.md).

## Installation

Add FactoryMan to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:factory_man, "~> 0.12.0", only: [:dev, :test]}
  ]
end
```

Then run `mix deps.get`.

## Quick Tour

Define factories:

```elixir
defmodule MyApp.Factory do
  use FactoryMan, repo: MyApp.Repo

  alias MyApp.Accounts.User
  alias MyApp.Blog.{Post, Tag}

  # Basic factory (struct-ful)
  deffactory user(params \\ %{}), struct: User do
    base_params = %{
      username: FactoryMan.sequence("user"),
      email: FactoryMan.sequence(:email, fn n -> "user#{n}@example.com" end),
      role: FactoryMan.sequence(:role, ["admin", "mod", "user"]),
      joined_at: fn -> DateTime.utc_now() end,
      display: fn user -> "#{user.username} (#{user.role})" end
    }

    Map.merge(base_params, params)
  end

  # Variant: Preprocesses params, then delegates to the base factory
  defvariant admin(params \\ %{}), for: :user do
    base_params = %{role: "admin"}

    Map.merge(base_params, params)
  end

  deffactory tag(params \\ %{}), struct: Tag do
    base_params = %{name: FactoryMan.sequence("tag")}

    Map.merge(base_params, params)
  end

  # Associations accept nested params through the declarative :associations option
  deffactory post(params \\ %{}), struct: Post, associations: [author: :user, tags: :tag] do
    base_params = %{
      title: FactoryMan.sequence("post", fn n -> "Post ##{n}" end),
      author: build_user_struct(%{username: "post-author"}),
      tags: [
        build_tag_struct(%{name: "elixir"}),
        build_tag_struct(%{name: "testing"})
      ]
    }

    Map.merge(base_params, params)
  end

  # Struct-less factories: Only generates `build_*` and `build_*_list` functions
  deffactory api_payload(params \\ %{}) do
    base_params = %{action: "create", resource: "user"}

    Map.merge(base_params, params)
  end
end
```

Factory calls in `base_params` supply association defaults. The `associations:` option also lets
callers supply nested params or existing structs. An atom names a factory in the same module; use
`{FactoryModule, :factory}` for another module, as shown in the [Cookbook](COOKBOOK.md).

Each factory generates a family of functions.

```elixir
iex> alias MyApp.Factory, as: Factory
MyApp.Factory

# Build a struct without saving it
iex> Factory.build_user_struct(%{username: "alice"})
%User{id: nil, username: "alice", ...}

# Build associations from nested params
iex> Factory.build_post_struct(%{author: %{username: "alice"}, tags: [%{name: "elixir"}]})
%Post{author: %User{username: "alice", ...}, tags: [%Tag{name: "elixir"}], ...}

# Atom-keyed input for a changeset
iex> Factory.build_user_params(%{username: "alice"})
%{username: "alice", ...}

# String-keyed input for a controller test
iex> Factory.build_user_string_params(%{username: "alice"})
%{"username" => "alice", ...}

# Build several structs without saving them
iex> Factory.build_user_struct_list(3)
[%User{id: nil, ...}, %User{id: nil, ...}, %User{id: nil, ...}]

# Build and save a struct
iex> Factory.insert_user(%{username: "alice"})
%User{id: 1, username: "alice", ...}

# Build and insert multiple structs in a single call
iex> Factory.insert_user_list(3)
[%User{id: 2, ...}, %User{id: 3, ...}, %User{id: 4, ...}]

# Save an edited struct through the factory's insert hooks
iex> user = Factory.build_user_struct()
iex> Factory.insert_user_struct(%{user | username: "edited"})
%User{id: 5, username: "edited", ...}

# Build a variant struct
iex> Factory.build_admin_user_struct(%{username: "the_boss"})
%User{id: nil, role: "admin", username: "the_boss", ...}

# Insert a variant struct
iex> Factory.insert_admin_user(%{username: "the_boss"})
%User{id: 6, role: "admin", username: "the_boss", ...}

## Struct-less factory functions

# Build a struct-less factory item
iex> Factory.build_api_payload()
%{action: "create", resource: "user"}

# Build a list of struct-less factory items
iex> Factory.build_api_payload_list(2)
[%{action: "create", resource: "user"}, %{action: "create", resource: "user"}]
```

## How It Works

You write one factory, and FactoryMan generates the rest:

- **`build_<name>_struct`** — builds the struct in memory (runs your body, resolves lazy values,
  calls `struct!/2`)
- **`build_<name>_params`** / **`build_<name>_string_params`** — builds the struct, then converts
  it to a clean params map (Ecto metadata stripped) for changesets or controller tests
- **`insert_<name>`** — builds the struct and inserts it with your configured repo
- **`insert_<name>_struct`** — inserts an already-built struct through the same insert pipeline
- **List builders** — `build_<name>_struct_list`, `build_<name>_params_list`, and
  `build_<name>_string_params_list` build each item independently. `insert_<name>_list` builds and
  inserts each item independently. `insert_<name>_struct` has no list counterpart.

Factories without a `struct:` option are simpler: they generate `build_<name>` and
`build_<name>_list`, and the body can return any value (maps, keyword lists, strings, ...).

## Which Function Should I Use?

- **`build_*_params`** — For testing changesets, passing to functions that expect maps, or when no
  struct shape is needed.

- **`build_*_struct`** — For setting association fields on other structs being built in memory. Use
  when the record doesn't need to exist in the database yet.

- **`insert_*`** — When a foreign key constraint requires the record to exist, or when the test
  queries the database for it.

## Extending factories

### Child factories with `extends:`

Use `extends:` to keep shared configuration, hooks, and helpers in a base factory while defining
factories in focused child modules:

```elixir
defmodule MyApp.Factory do
  use FactoryMan,
    # These options will be inherited by any child factories that extend the parent
    repo: MyApp.Repo,
    hooks: [after_insert: &__MODULE__.unset_assocs/1]

  @doc "Unset all assocs from a given Ecto schema `struct`."
  def unset_assocs(struct) do
    Ecto.reset_fields(struct, struct.__struct__.__schema__(:associations))
  end
end

defmodule MyApp.Factory.Accounts do
  # The child factory uses `:extends` to inherit options from the parent factory
  use FactoryMan,
    extends: MyApp.Factory,
    # Child factories can add their own options too
    repo: MyApp.OtherRepo

  alias MyApp.Accounts.User

  # This factory inherits the post-insert hook, so its assocs will be unset after insert
  deffactory user(params \\ %{}), struct: User do
    base_params = %{username: FactoryMan.sequence("user")}

    Map.merge(base_params, params)
  end
end

defmodule MyApp.Factory.Accounts.Admins do
  use FactoryMan, extends: MyApp.Factory.Accounts
end
```

`MyApp.Factory.Accounts` overrides the parent's repo and still inherits its hooks and helpers.
`MyApp.Factory.Accounts.Admins` inherits those resolved options, including the repo override. Any
factory module can be extended again, so inheritance chains have no fixed depth.

### Recommended project structure

Keep the base factory focused on shared config (repo, hooks, helpers). Child factories use
`extends:` to inherit that config, and mirror your application's context structure:

```text
test/support/
  factory.ex                    # Base factory (config, hooks, shared helpers)
  factory/
    accounts.ex                 # MyApp.Factory.Accounts (extends MyApp.Factory)
    accounts/
      admins.ex                 # MyApp.Factory.Accounts.Admins (extends MyApp.Factory.Accounts)
    blog.ex                     # MyApp.Factory.Blog (extends MyApp.Factory)
    blog/comments.ex            # MyApp.Factory.Blog.Comments (extends MyApp.Factory)
```

## Going Further

The full reference lives in the
[`FactoryMan` module documentation](https://hexdocs.pm/factory_man/FactoryMan.html), including:

- **Hooks** — transform data at each stage of the build/insert pipeline
- **Variants** (`defvariant`) — lightweight presets that preprocess params for a base factory
- **Associations** (`associations:`) — normalize nested params through same- or cross-module factories
- **Strict params** (`strict: true`) — reject unknown param keys at the factory boundary
- **Sequences** — counters, formatted values, and cycling lists
- **Lazy evaluation** — 0- and 1-arity functions as attribute values, resolved at build time
- **Factory inheritance** (`extends:`) — share repo, hooks, and helper functions
- **Direct struct factories** (`body: :struct`) — full control over struct construction
- **Embedded schemas** — build-only factories, detected automatically
- **[Cookbook](COOKBOOK.md)** — a practical progression from a first factory through realistic
  defaults, variants, associations, suite organization, hooks, strict params, and advanced presets
