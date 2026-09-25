# FactoryMan

An Elixir library for generating test data. Define factories with `deffactory`, and FactoryMan
generates functions for building params, structs, and database records.

Inspired by [ExMachina](https://hex.pm/packages/ex_machina), but with a different API and feature
set.

- [Cookbook](COOKBOOK.md) - recipes, from a first factory to variants, associations, and hooks
- [Cheat sheet](CHEATSHEET.cheatmd) - generated functions, options, and precedence rules at a glance
- [Usage rules](usage-rules.md) - the rules for writing factories, for people and coding agents
- [`FactoryMan` module documentation](https://hexdocs.pm/factory_man/FactoryMan.html) - the full
  reference

## Installation

Add FactoryMan to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:factory_man, "~> 0.18.0", only: [:dev, :test]}
  ]
end
```

Then run `mix deps.get`.

## Quick Tour

Define factories:

```elixir
defmodule MyApp.Factory do
  # `strict: true` raises on misspelled keys and on params a factory body ignores
  use FactoryMan, repo: MyApp.Repo, strict: true

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

  defvariant confirmed(params \\ %{}), for: :user do
    Map.merge(%{confirmed_at: fn -> DateTime.utc_now() end}, params)
  end

  deffactory tag(params \\ %{}), struct: Tag do
    base_params = %{name: FactoryMan.sequence("tag")}

    Map.merge(base_params, params)
  end

  # Associations: each builder runs before the body and is the key's default
  deffactory post(params \\ %{}),
    struct: Post,
    assocs: [
      author: &build_user_struct/1,
      tags: {&build_tag_struct/1, default: [%{name: "elixir"}, %{name: "testing"}]}
    ] do
    base_params = %{title: "Post by #{params.author.username}"}

    Map.merge(base_params, params)
  end

  # Struct-less factories: Only generates `build_*` and `build_*_list` functions
  deffactory api_payload(params \\ %{}) do
    base_params = %{action: "create", resource: "user"}

    Map.merge(base_params, params)
  end
end
```

The `assocs:` builders resolve each association before the body runs, so the body sees a built
author, and callers can supply nested params, existing structs, or `nil` instead. See the
[Cookbook](COOKBOOK.md) for chaining, variants, and recursion.

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

# Build and save a struct
iex> Factory.insert_user(%{username: "alice"})
%User{id: 1, username: "alice", ...}

# Build and insert several, each built independently
iex> Factory.insert_user_list(3)
[%User{id: 2, ...}, %User{id: 3, ...}, %User{id: 4, ...}]

# Build a variant struct
iex> Factory.build_admin_user_struct(%{username: "the_boss"})
%User{id: nil, role: "admin", username: "the_boss", ...}

# Combine variants in one build
iex> Factory.build_user_struct(%{}, variants: [:admin, :confirmed])
%User{id: nil, role: "admin", confirmed_at: ~U[2026-09-24 12:00:00.000000Z], ...}

# Build a struct-less factory item
iex> Factory.build_api_payload()
%{action: "create", resource: "user"}
```

## How It Works

You write one factory, and FactoryMan generates the rest:

- **`build_<name>_struct`** - builds the struct in memory (runs your body, resolves lazy values,
  calls `struct!/2`)
- **`build_<name>_params`** / **`build_<name>_string_params`** - builds the struct, then converts
  it to a clean params map (Ecto metadata stripped) for changesets or controller tests
- **`insert_<name>`** - builds the struct and inserts it with your configured repo, or with the
  insert function you choose (`insert:`)
- **`insert_<name>_struct`** - inserts an already-built struct through the same insert pipeline
- **List builders** - `build_<name>_struct_list`, `build_<name>_params_list`, and
  `build_<name>_string_params_list` build each item independently. `insert_<name>_list` builds and
  inserts each item independently. `insert_<name>_struct` has no list counterpart.

Factories without a `struct:` option are simpler: they generate `build_<name>` and
`build_<name>_list`, and the body can return any value (maps, keyword lists, strings, ...).

## Organizing Factories

Keep shared configuration in a base factory:

```elixir
defmodule MyApp.Factory do
  use FactoryMan,
    repo: MyApp.Repo,
    strict: true,
    hooks: [after_insert: &__MODULE__.reset_assocs/1]

  def reset_assocs(struct) do
    Ecto.reset_fields(struct, struct.__struct__.__schema__(:associations))
  end
end
```

Child modules inherit its options and helper functions with `use FactoryMan, extends:
MyApp.Factory`. See "Organize a growing factory suite" in the [Cookbook](COOKBOOK.md) for a
recommended layout.

## Going Further

The full reference lives in the
[`FactoryMan` module documentation](https://hexdocs.pm/factory_man/FactoryMan.html), including:

- **Hooks** - transform data at each stage of the build/insert pipeline
- **Variants** (`defvariant`) - presets for a base factory, combined with `variants:` and built on
  each other with `extends:`
- **Associations** (`assocs:`) - build associations before the body, from nested params or defaults
- **Strict params** (`strict: true`) - reject misspelled keys, and params a factory body ignores
- **Sequences** - counters, formatted values, and cycling lists
- **Lazy evaluation** - 0- and 1-arity functions as attribute values, resolved at build time
- **Factory inheritance** (`extends:`) - share repo, hooks, and helper functions
- **Direct struct factories** (`body: :struct`) - full control over struct construction
- **Insert targets** (`insert:`, `insert_via:`) - insert into other stores, such as a search index
- **Disabling function families** (`disable:`) - switch off generated functions a suite does not use
- **Embedded schemas** - no Ecto insert functions, detected automatically
- **[Cookbook](COOKBOOK.md)** - a practical progression from a first factory through realistic
  defaults, variants, associations, suite organization, hooks, strict params, insert targets, and
  advanced presets
