# FactoryMan

Elixir test data factories with automatic struct building, database insertion, and customizable hooks.

> NOTE: FactoryMan is heavily inspired by [ExMachina](https://hex.pm/packages/ex_machina), and copies some code from it in some cases (e.g. for sequences). However, FactoryMan is not a clone of ExMachina. See the examples in the documentation to see what sets us apart!

## Features

- Easy factories - Define factories with minimal boilerplate
- Generated functions - Build params (for testing changesets), structs, and lists of items
- Database insertion - Built-in `insert_` functions with configurable repo
- List factories - Create multiple records with `*_list` functions
- Sequence generation - Automatic unique value generation for usernames, emails, etc.
- Lazy evaluation - Compute values at build time
- Factory inheritance - Share config from parent factories to reduce boilerplate
- Hooks - Apply custom transformations to data before/after building or inserting a factory item

## Installation

Add FactoryMan to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:factory_man, "0.2.0"}
  ]
end
```

Then run `mix deps.get`.

No further configuration should be necessary.

## Quick Start

Create a factory module in your project's `test/support/` directory:

`test/support/factory.ex`
```elixir
defmodule MyApp.Factory do
  use FactoryMan, repo: MyApp.Repo

  alias MyApp.Users.User

  deffactory user(params \\ %{}), struct: User do
    base_params = %{username: "user-#{System.os_time()}"}

    Map.merge(base_params, params)
  end
end
```

Build and insert some test data:

```elixir
# Build params (e.g. for testing changesets)
iex> MyApp.Factory.build_user_params(%{username: "test_user"})
%{username: "test_user"}

# Build a struct (not persisted)
iex> MyApp.Factory.build_user_struct(%{username: "test_user"})
%User{id: nil, username: "test_user"}

# Insert into the database
iex> MyApp.Factory.insert_user!(%{username: "test_user"})
%User{id: 1, username: "test_user"}

# Insert multiple items in a single statement
iex> MyApp.Factory.insert_user_list!(3)
[%User{id: 1, ...}, %User{id: 2, ...}, %User{id: 3, ...}]
```

## Base Factory Pattern (Optional)

For larger projects, you may want to share common configuration across multiple factory modules.
FactoryMan allows you to create a base factory module with shared settings:

```elixir
defmodule MyApp.Factory do
  # Define the base factory options here
  use FactoryMan, repo: MyApp.Repo

  # You may define generic factory helpers in this module as well
  def generate_username, do: "user-#{System.os_time()}"
end
```

Then extend the base factory in child factory modules:

```elixir
defmodule MyApp.Factory.ChildFactory do
  # Extend the base factory
  use FactoryMan, extends: MyApp.Factory

  alias MyApp.Factory
  alias MyApp.Users.User

  # Child factories in this module inherit the options set in the base factory module
  deffactory user(params \\ %{}), struct: User do
    %{username: Factory.generate_username()} |> Map.merge(params)
  end
end
```

Child factories are typically placed in `test/support/factory/[your_context].ex` and extend the
base factory to inherit common configuration like repo settings and hooks.

The directory structure is up to you, but it is recommended to make a factory module for each
context in your application code. Keeping the filesystem hierarchies the same tends to make it
easier to remember which factory is where.

> #### Tip {: .tip}
>
> The base factory pattern is completely optional. Use whatever structure fits your project or personal tastes.

### Recommended Project Structure

> #### Note {: .info}
>
> This is an opinionated recommendation, not a requirement. FactoryMan is intended to work with
> any module structure. However, having a consistent convention reduces decision fatigue and makes
> it easier to navigate factory code across projects.

We recommend keeping the base factory as a dedicated module focused on shared configuration: repo
settings, hooks, and generic helpers.

```elixir
# test/support/factory.ex
defmodule MyApp.Factory do
  use FactoryMan, repo: MyApp.Repo

  # Shared hooks
  def after_insert_handler(%_{} = struct),
    do: Ecto.reset_fields(struct, struct.__struct__.__schema__(:associations))

  # Generic helpers used across multiple child factories
  def generate_email(name), do: "#{name}@example.com"
end
```

Child factory modules extend the base and mirror your application's context structure:

```
test/support/
  factory.ex                    # Base factory (config, hooks, shared helpers)
  factory/
    accounts.ex                 # MyApp.Factory.Accounts (extends MyApp.Factory)
    blog.ex                     # MyApp.Factory.Blog (extends MyApp.Factory)
    blog/comments.ex            # MyApp.Factory.Blog.Comments (extends MyApp.Factory)
```

`test/support/factory/accounts.ex`

```elixir
defmodule MyApp.Factory.Accounts do
  use FactoryMan, extends: MyApp.Factory

  alias MyApp.Accounts.User
  alias MyApp.Factory

  deffactory user(params \\ %{}), struct: User do
    base_params = %{
      username: "user-#{System.os_time()}",
      email: Factory.generate_email("user-#{System.os_time()}")
    }

    Map.merge(base_params, params)
  end
end
```

Why this structure?

- The base factory is a clear, single-purpose module. It is easy to find, and easy to understand
- Child factories map to application contexts, so you always know where to look
- The `extends:` relationship is obvious and consistent
- New team members (and LLM agents) can follow the pattern without guessing

### When to Use Params vs Struct vs Insert

- `build_*_params` - For testing changesets, passing to functions that expect maps, or when no
struct shape is needed.

- `build_*_struct` - For setting association fields on other structs being built in memory. Use
this when the record does not need to exist in the database at the time the struct is generated.

- `insert_*!` - When a foreign key constraint requires the record to exist in the database, or
when the test itself queries the database for this record.

- Lazy evaluation (0-arity) - When a default value is expensive to compute or depends on runtime
state. This avoids eagerly inserting records that may not be needed.

- Lazy evaluation (1-arity) - When a field's default depends on another field in the same factory.
The function receives the parent map at build time.

A common mistake when building factories is inserting records into the database when a plain
struct would suffice. If the only reason to insert is to get an ID for a foreign key, consider
whether the test actually needs that constraint enforced. If not, a struct with a generated ID is
simpler and faster.

## Direct Struct Factories (`params?: false`)

For complex factories that need full control over struct construction, set `params?: false`.
The factory body returns a struct directly, and no `build_*_params` functions are generated:

```elixir
deffactory invoice(params \\ %{}), struct: Invoice, params?: false do
  customer =
    case params[:customer] do
      %Customer{} = customer -> customer
      _ -> MyApp.Factory.Accounts.insert_customer!()
    end

  %Invoice{
    customer: customer,
    total: Map.get(params, :total, Enum.random(100..10_000))
  }
end
```

This generates `build_invoice_struct/0,1`, `insert_invoice!/0,1,2`, and list variants, but
**not** `build_invoice_params`.

`params?: false` can also be set at the module level via `use FactoryMan, params?: false`.

## Variant Factories (`defvariant`)

A variant wraps a base factory. It transforms params **before** the base factory runs (it is a
preprocessor, not a postprocessor). The variant is defined after the base factory in your code,
but executes before it at runtime:

```elixir
deffactory user(params \\ %{}), struct: User do
  %{username: sequence("user"), role: "member"}
  |> Map.merge(params)
end

defvariant admin(params \\ %{}), for: :user do
  Map.merge(%{role: "admin"}, params)
end
```

```text
Code order:     deffactory user(...)   ->  defvariant admin(...), for: :user
Execution order:  admin (preprocessor)  ->  user (base factory)
```

This generates `build_admin_user_struct/0,1`, `insert_admin_user!/0,1,2`, and list variants.
Calling `build_admin_user_struct()` is equivalent to `build_user_struct(%{role: "admin"})`.

### Custom naming with `:as`

The `:as` option overrides the combined `{variant}_{base}` name:

```elixir
defvariant moderator(params \\ %{}), for: :user, as: :mod do
  Map.merge(params, %{role: "moderator"})
end
```

This generates `build_mod_struct/0,1`, `insert_mod!/0,1,2`, etc.
— instead of the default `build_moderator_user_struct`.

## Documentation

Full documentation is available in [the `FactoryMan` module](https://hexdocs.pm/factory_man/FactoryMan.html).
