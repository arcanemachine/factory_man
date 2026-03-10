# FactoryMan

An Elixir library for generating test data. Define factories with `deffactory`, and FactoryMan
generates functions for building params, structs, and database records.

Inspired by [ExMachina](https://hex.pm/packages/ex_machina), but with a different API and feature
set. See the examples below.

## Quick Tour

### Build factories

```elixir
defmodule MyApp.Factory do
  use FactoryMan, repo: MyApp.Repo

  alias MyApp.Accounts.User
  alias MyApp.Blog.Post

  # Basic factory
  deffactory user(params \\ %{}), struct: User do
    base_params = %{
      username: sequence("user"),
      email: sequence(:email, fn n -> "user#{n}@example.com" end),
      role: sequence(:role, ["admin", "mod", "user"]),
      joined_at: fn -> DateTime.utc_now() end,
      display: fn u -> "#{u.username} (#{u.role})" end
    }

    Map.merge(base_params, params)
  end

  # Variant — preprocesses params, then delegates to the base factory
  defvariant admin(params \\ %{}), for: :user do
    base_params = %{role: "admin"}

    Map.merge(base_params, params)
  end

  # Associations — call other factories to build related records
  deffactory post(params \\ %{}), struct: Post do
    base_params = %{
      title: sequence("post", fn n -> "Post ##{n}" end),
      author: params[:author] || build_user_struct()
    }

    Map.merge(base_params, params)
  end

  # Params-only (no struct) — only generates build_*_params functions
  deffactory api_payload(params \\ %{}) do
    base_params = %{action: "create", resource: "user"}

    Map.merge(base_params, params)
  end
end
```

### FactoryMan generates functions from your factories

```elixir
iex> Factory.build_user_params()
%{username: "user0", email: "user0@example.com", role: "admin", ...}

iex> Factory.build_user_struct()
%User{username: "user1", email: "user1@example.com", ...}

iex> Factory.insert_user!()
%User{id: 1, username: "user2", ...}

iex> Factory.insert_user_list!(3)
[%User{id: 2, ...}, %User{id: 3, ...}, %User{id: 4, ...}]

iex> Factory.build_admin_user_struct()
%User{role: "admin", username: "user3", ...}

iex> Factory.build_api_payload_params()
%{action: "create", resource: "user"}
```

## Installation

Add FactoryMan to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:factory_man, "~> 0.3.0"}
  ]
end
```

Then run `mix deps.get`.

## Defining Factories

### Basic factories

Use `deffactory` to define a factory:

```elixir
deffactory user(params \\ %{}), struct: User do
  base_params = %{username: "user-#{System.os_time()}"}

  Map.merge(base_params, params)
end
```

When using the `:struct` option, the factory body must return a plain map so FactoryMan can call
`struct!()` on it. If you need to return a struct directly, use `build_params?: false` instead.
Without `:struct`, the body can return any value (see [Arbitrary value factories](#arbitrary-value-factories)).

You can name the parameter anything and use pattern matching:

```elixir
deffactory user(%{role: role} = attrs \\ %{role: "member"}), struct: User do
  base_params = %{username: "user-#{System.os_time()}", role: role}

  Map.merge(base_params, attrs)
end
```

### Params-only factories

Omit the `struct:` option to create factories that only generate `build_*_params` functions:

```elixir
deffactory api_payload(params \\ %{}) do
  %{action: "create", data: params}
end
# Generates: build_api_payload_params/0,1, build_api_payload_params_list/1,2
```

### Arbitrary value factories

Without the `:struct` option, factory bodies can return any value — strings, keyword lists,
tuples, or anything else:

```elixir
deffactory greeting(name \\ "world") do
  "Hello, #{name}!"
end

deffactory search_opts(overrides \\ []) do
  Keyword.merge([page: 1, per_page: 20], overrides)
end
# Generates: build_greeting_params/0,1, build_search_opts_params/0,1 (and _list variants)
```

Lazy evaluation works in keyword lists the same way it does in maps.

### Non-insertable factories

Use `insert?: false` to skip insert function generation, or let FactoryMan detect embedded schemas
automatically:

```elixir
deffactory read_only_user(params \\ %{}), struct: User, insert?: false do
  base_params = %{username: "readonly"}

  Map.merge(base_params, params)
end
# Generates: build_read_only_user_params, build_read_only_user_struct (and _list variants)
# Skips: insert_read_only_user!
```

### Direct struct factories (`build_params?: false`)

For factories that need full control over struct construction, set `build_params?: false`. The body
returns a **struct** directly, and no `build_*_params` functions are generated:

```elixir
deffactory invoice(params \\ %{}), struct: Invoice, build_params?: false do
  customer =
    case params[:customer] do
      %Customer{} = c -> c
      _ -> MyApp.Factory.Accounts.insert_customer!()
    end

  %Invoice{
    customer: customer,
    total: Map.get(params, :total, Enum.random(100..10_000))
  }
end
# Generates: build_invoice_struct, insert_invoice! (and _list variants)
# Skips: build_invoice_params
```

`build_params?: false` can also be set at the module level via
`use FactoryMan, build_params?: false`.

## Generated Functions

For a factory named `:user` with `struct: User`:

| Function | Returns | Purpose |
| --- | --- | --- |
| `build_user_params/0,1` | `%{}` | Plain map (for changesets, APIs) |
| `build_user_struct/0,1` | `%User{}` | Struct in memory (not persisted) |
| `insert_user!/0,1` | `%User{}` | Inserted into database |
| `build_user_params_list/1,2` | `[%{}, ...]` | List of params maps |
| `build_user_struct_list/1,2` | `[%User{}, ...]` | List of structs |
| `insert_user_list!/1,2` | `[%User{}, ...]` | List of inserted records |

What gets generated depends on the options:

| Options | Params | Struct | Insert |
| --- | --- | --- | --- |
| `struct: User` (default) | Yes | Yes | Yes |
| No `struct:` option | Yes | No | No |
| `insert?: false` | Yes | Yes | No |
| `build_struct?: false` | Yes | No | No |
| `build_params?: false` | No | Yes | Yes |
| Embedded schema | Yes | Yes | No |

## Sequences

Generate unique values across builds:

```elixir
sequence("user")                                          # "user0", "user1", ...
sequence(:email, fn n -> "user#{n}@example.com" end)      # custom formatter
sequence(:role, ["admin", "mod", "user"])                  # cycles through list
sequence(:order, fn n -> "ORD-#{n}" end, start_at: 1000)  # custom start value
```

Reset sequences in test setup:

```elixir
setup do
  FactoryMan.Sequence.reset()
  :ok
end
```

## Lazy Evaluation

Functions in factory params are evaluated at build time:

```elixir
%{
  # 0-arity: called with no arguments
  created_at: fn -> DateTime.utc_now() end,

  # 1-arity: receives the parent map (before lazy evaluation)
  display_name: fn user -> "#{user.username} (User)" end
}
```

**Important:** 1-arity functions receive the map *before* lazy evaluation. Don't reference other
lazy fields from a 1-arity function — they'll still be function references, not resolved values.

## Variant Factories

A variant wraps a base factory. It transforms params **before** the base factory runs (it is a
preprocessor, not a postprocessor):

```elixir
deffactory user(params \\ %{}), struct: User do
  base_params = %{username: sequence("user"), role: "member"}

  Map.merge(base_params, params)
end

defvariant admin(params \\ %{}), for: :user do
  base_params = %{role: "admin"}

  Map.merge(base_params, params)
end
```

```text
Code order:       deffactory user(...)   ->  defvariant admin(...), for: :user
Execution order:  admin (preprocessor)   ->  user (base factory)
```

This generates `build_admin_user_struct/0,1`, `insert_admin_user!/0,1,2`, and list variants.
Calling `build_admin_user_struct()` is equivalent to `build_user_struct(%{role: "admin"})`.

### Custom naming with `:as`

The `:as` option overrides the default `{variant}_{base}` name:

```elixir
defvariant moderator(params \\ %{}), for: :user, as: :mod do
  base_params = %{role: "moderator"}

  Map.merge(base_params, params)
end
# Generates: build_mod_struct/0,1, insert_mod!/0,1,2, etc.
```

## Hooks

Hooks let you transform data at each stage of the build pipeline:

```text
build_*_params:
  before_build_params -> [factory body + lazy eval] -> after_build_params

build_*_struct (calls build_*_params internally):
  -> before_build_struct -> struct!() -> after_build_struct

insert_*! (calls build_*_struct internally):
  -> before_insert -> Repo.insert!() -> after_insert
```

Available hooks:

| Hook | Receives | Purpose |
| --- | --- | --- |
| `before_build_params` | params map | Transform params before the factory body runs |
| `after_build_params` | params map | Modify params after the factory body |
| `before_build_struct` | params map | Last chance to modify params before `struct!()` |
| `after_build_struct` | struct | Transform the struct after creation |
| `before_insert` | struct | Modify struct just before database insertion |
| `after_insert` | struct | Post-process after insertion (e.g. reset associations) |

Set hooks at the module level or per-factory:

```elixir
defmodule MyApp.Factory do
  use FactoryMan,
    repo: MyApp.Repo,
    hooks: [after_insert: &__MODULE__.reset_assocs/1]

  def reset_assocs(%_{} = struct),
    do: Ecto.reset_fields(struct, struct.__struct__.__schema__(:associations))
end
```

```elixir
deffactory user(params \\ %{}), struct: User,
  hooks: [after_build_params: &IO.inspect(&1, label: "user params")] do
  base_params = %{username: "user-#{System.os_time()}"}

  Map.merge(base_params, params)
end
```

## Factory Inheritance

### The `extends:` option

Child factories inherit the parent's repo, hooks, and helper functions:

```elixir
defmodule MyApp.Factory do
  use FactoryMan, repo: MyApp.Repo

  def generate_username, do: "user-#{System.os_time()}"
end

defmodule MyApp.Factory.Accounts do
  use FactoryMan, extends: MyApp.Factory

  # Inherits :repo and generate_username/0 from parent
  deffactory user(params \\ %{}), struct: User do
    base_params = %{username: generate_username()}

    Map.merge(base_params, params)
  end
end
```

Inheritance chains are unlimited — a child factory can itself be extended.

### Recommended project structure

Keep the base factory focused on shared config (repo, hooks, helpers). Child factories mirror your
application's context structure:

```text
test/support/
  factory.ex                    # Base factory (config, hooks, shared helpers)
  factory/
    accounts.ex                 # MyApp.Factory.Accounts (extends MyApp.Factory)
    blog.ex                     # MyApp.Factory.Blog (extends MyApp.Factory)
    blog/comments.ex            # MyApp.Factory.Blog.Comments (extends MyApp.Factory)
```

## When to Use What

- **`build_*_params`** — For testing changesets, passing to functions that expect maps, or when no
  struct shape is needed.

- **`build_*_struct`** — For setting association fields on other structs being built in memory. Use
  when the record doesn't need to exist in the database yet.

- **`insert_*!`** — When a foreign key constraint requires the record to exist, or when the test
  queries the database for it.

- **Lazy 0-arity** — When a default is expensive to compute or depends on runtime state.

- **Lazy 1-arity** — When a field's default depends on another field in the same factory.

A common mistake is inserting records when a plain struct would suffice. If you only need an ID for
a foreign key, consider whether the test actually needs that constraint enforced.

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/factory_man/FactoryMan.html).
