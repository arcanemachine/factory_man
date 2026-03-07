# FactoryMan

Elixir test data factories with automatic struct building, database insertion, and customizable hooks.

> NOTE: FactoryMan is heavily inspired by [ExMachina](https://hex.pm/packages/ex_machina), and copies some code from it in some cases (e.g. for sequences). However, FactoryMan is not a clone of ExMachina. See the examples in the documentation to see what sets us apart!

## Installation

Add FactoryMan to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:factory_man, "0.1.0"}
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

For larger projects, you may want to share common configuration across multiple factory modules. FactoryMan allows you to create a base factory module with shared settings:

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

Child factories are typically placed in `test/support/factory/[your_context].ex` and extend the base factory to inherit common configuration like repo settings and hooks.

The directory structure is up to you, but it is recommended to make a factory module for each context in your application code. Keeping the filesystem hierarchies the same tends to make it easier to remember which factory is where.

> #### Tip {: .tip}
>
> The base factory pattern is completely optional. Use whatever structure fits your project or personal tastes.

## Features

- Easy factories - Define factories with minimal boilerplate
- Generated functions - Build params (for testing changesets), structs, and lists of items
- Database insertion - Built-in `insert_` functions with configurable repo
- List factories - Create multiple records with `*_list` functions
- Sequence generation - Automatic unique value generation for usernames, emails, etc.
- Lazy evaluation - Compute values at build time
- Factory inheritance - Share config from parent factories to reduce boilerplate
- Hooks - Apply custom transformations to data before/after building or inserting a factory item

## Documentation

Full documentation is available in [the `FactoryMan` module](https://hexdocs.pm/factory_man/FactoryMan.html).
