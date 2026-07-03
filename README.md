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
    {:factory_man, "~> 0.9.0", only: [:dev, :test]}
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
  alias MyApp.Blog.Post

  # Basic factory
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

  # Associations: assoc/4 accepts a prebuilt struct, params to build one from, or nothing
  deffactory post(params \\ %{}), struct: Post do
    base_params = %{title: FactoryMan.sequence("post", fn n -> "Post ##{n}" end)}

    params = Map.put(params, :author, FactoryMan.assoc(params, :author, &build_user_struct/1, struct: User))

    Map.merge(base_params, params)
  end

  # Struct-less factories: Only generates `build_*` and `build_*_list` functions
  deffactory api_payload(params \\ %{}) do
    base_params = %{action: "create", resource: "user"}

    Map.merge(base_params, params)
  end
end
```

Each factory generates a family of functions:

```elixir
iex> Factory.build_user_struct()
%User{username: "user1", email: "user1@example.com", ...}

iex> Factory.build_user_params()
%{username: "user0", email: "user0@example.com", role: "admin", ...}

iex> Factory.insert_user()
%User{id: 1, username: "user2", ...}

iex> Factory.insert_user_list(3)
[%User{id: 2, ...}, %User{id: 3, ...}, %User{id: 4, ...}]

iex> Factory.build_admin_user_struct()
%User{role: "admin", username: "user3", ...}

iex> Factory.build_api_payload()
%{action: "create", resource: "user"}
```

## How It Works

You write one factory, and FactoryMan generates the rest:

- **`build_<name>_struct`** — builds the struct in memory (runs your body, resolves lazy values,
  calls `struct!/2`)
- **`build_<name>_params`** / **`build_<name>_string_params`** — builds the struct, then converts
  it to a clean params map (Ecto metadata stripped) for changesets or controller tests
- **`insert_<name>`** — builds the struct and inserts it with your configured repo
- **`insert_<name>_struct`** — inserts an already-built struct through the same insert pipeline
- **`*_list` variants** of the builders above, each item evaluated independently

Factories without a `struct:` option are simpler: they generate `build_<name>` and
`build_<name>_list`, and the body can return any value (maps, keyword lists, strings, ...).

## Which Function Should I Use?

- **`build_*_params`** — For testing changesets, passing to functions that expect maps, or when no
  struct shape is needed.

- **`build_*_struct`** — For setting association fields on other structs being built in memory. Use
  when the record doesn't need to exist in the database yet.

- **`insert_*`** — When a foreign key constraint requires the record to exist, or when the test
  queries the database for it.

A common mistake is inserting records when a plain struct would suffice. If you only need an ID for
a foreign key, consider whether the test actually needs that constraint enforced.

## Recommended Project Structure

Keep the base factory focused on shared config (repo, hooks, helpers). Child factories use
`extends:` to inherit that config, and mirror your application's context structure:

```text
test/support/
  factory.ex                    # Base factory (config, hooks, shared helpers)
  factory/
    accounts.ex                 # MyApp.Factory.Accounts (extends MyApp.Factory)
    blog.ex                     # MyApp.Factory.Blog (extends MyApp.Factory)
    blog/comments.ex            # MyApp.Factory.Blog.Comments (extends MyApp.Factory)
```

## Going Further

The full reference lives in the
[`FactoryMan` module documentation](https://hexdocs.pm/factory_man/FactoryMan.html), including:

- **Hooks** — transform data at each stage of the build/insert pipeline
- **Variants** (`defvariant`) — lightweight presets that preprocess params for a base factory
- **Associations** (`assoc/4`) — resolve a prebuilt struct, a params map, or a built default
- **Strict params** (`strict: true`) — reject unknown param keys at the factory boundary
- **Sequences** — unique values across builds (`FactoryMan.sequence("user")` → `"user0"`, `"user1"`, ...)
- **Lazy evaluation** — 0- and 1-arity functions as attribute values, resolved at build time
- **Factory inheritance** (`extends:`) — share repo, hooks, and helper functions
- **Direct struct factories** (`body: :struct`) — full control over struct construction
- **Embedded schemas** — build-only factories, detected automatically
- **[Cookbook](COOKBOOK.md)** — recipes for common patterns like building associations and
  post-build/validated presets
