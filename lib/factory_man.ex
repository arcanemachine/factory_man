defmodule FactoryMan do
  @moduledoc """
  Test data factories with automatic struct building, database insertion, and customizable hooks.

  ## Quick Start

  Create your first factory module:

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

  For larger projects, you may use a base factory which can be extended with child factories:

  `test/support/factory.ex` (base)
  ```elixir
  defmodule MyApp.Factory do
    use FactoryMan, repo: MyApp.Repo

    # Base configuration and helper functions
    def generate_username, do: "user-#{System.os_time()}"
  end
  ```

  `test/support/factory/child_factory.ex` (child)
  ```elixir
  defmodule MyApp.Factory.ChildFactory do
    use FactoryMan, extends: MyApp.Factory

    alias MyApp.Users.User

    deffactory user(params \\ %{}), struct: User do
      %{username: generate_username()} |> Map.merge(params)
    end
  end
  ```

  ## Dependencies

  FactoryMan itself has no required runtime dependencies. However, you will need to add
  dependencies based on which factory functions you intend to use:

  For params-only factories (no `:struct` option):
  - No additional dependencies required

  For struct factories (with `:struct` option):
  - `{:ecto_sql, "~> 3.0"}` - Required in your mix.exs

  For database insertion (for `insert_*!` functions):
  - `{:ecto_sql, "~> 3.0"}` - Required in your mix.exs
  - Database driver (e.g., `{:postgrex, ">= 0.0.0"}`) - Required for your specific database

  Add these to your `mix.exs` deps:

  ```elixir
  def deps do
    [
      {:factory_man, "0.1.1"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"}  # If using PostgreSQL
    ]
  end
  ```

  ## Generated Functions

  When you define a struct factory:

  ```elixir
  deffactory user(params \\ %{}), struct: User do
    base_params = %{username: "user-#{System.os_time()}"}
    Map.merge(base_params, params)
  end
  ```

  FactoryMan generates:

  **Params builders** - Return plain maps
  - `build_user_params` - Single or list with `build_user_params_list`

  **Struct builders** - Return structs (not persisted)
  - `build_user_struct` - Single or list with `build_user_struct_list`

  **Insert functions** - Persist to database
  - `insert_user!` - Single or list with `insert_user_list!`

  All functions accept optional params for customization. Insert functions also accept repo options.

  **List variants** - All functions have corresponding list builders (`*_list`) for batch creation.

  ## Using Generated Functions

  **Params builders** return plain data:

  ```elixir
  iex> MyApp.Factory.build_user_params()
  %{username: "user-1234567890"}

  iex> MyApp.Factory.build_user_params(%{username: "alice"})
  %{username: "alice"}

  iex> MyApp.Factory.build_user_params_list(3)
  [%{username: "user-1234567890"}, %{username: "user-1234567891"}, %{username: "user-1234567892"}]

  iex> MyApp.Factory.build_user_params_list(2, %{role: "admin"})
  [%{username: "user-1234567893", role: "admin"}, %{username: "user-1234567894", role: "admin"}]
  ```

  **Struct builders** return structs:

  ```elixir
  iex> MyApp.Factory.build_user_struct()
  %User{id: nil, username: "user-1234567895"}

  iex> MyApp.Factory.build_user_struct(%{username: "bob"})
  %User{id: nil, username: "bob"}

  iex> MyApp.Factory.build_user_struct_list(2)
  [%User{id: nil, username: "user-1234567896"}, %User{id: nil, username: "user-1234567897"}]
  ```

  **Insert functions** persist to database:

  ```elixir
  iex> MyApp.Factory.insert_user!()
  %User{id: 1, username: "user-1234567898"}

  iex> MyApp.Factory.insert_user!(%{username: "charlie"})
  %User{id: 2, username: "charlie"}

  iex> MyApp.Factory.insert_user_list!(2, %{verified: true})
  [
    %User{id: 3, username: "user-1234567899", verified: true},
    %User{id: 4, username: "user-1234567900", verified: true}
  ]
  ```

  **List functions** create multiple items:

  ```elixir
  iex> MyApp.Factory.build_user_params_list(2)
  [%{username: "user-1234567901"}, %{username: "user-1234567902"}]

  iex> MyApp.Factory.build_user_struct_list(2, %{role: "admin"})
  [
    %User{id: nil, username: "user-1234567903", role: "admin"},
    %User{id: nil, username: "user-1234567904", role: "admin"}
  ]

  iex> MyApp.Factory.insert_user_list!(2)
  [%User{id: 5, username: "user-1234567905"}, %User{id: 6, username: "user-1234567906"}]
  ```

  **Customizing what gets generated:**

  **Params-only** (no `:struct` option) - Only generates params builders

  ```elixir
  deffactory api_payload(params \\ %{}) do
    %{action: "create", data: params}
  end
  # Generates: build_api_payload_params, build_api_payload_params_list
  ```

  **Non-insertable structs** (e.g. Embedded Ecto schemas or non-Ecto structs) - Automatically
  skips insert functions (since there is no database table)

  ```elixir
  deffactory user_settings(params \\ %{}), struct: UserSettings do
    %{theme: "dark", notifications: true} |> Map.merge(params)
  end
  # Generates: build_user_settings_params, build_user_settings_struct (and _list variants)
  # Embedded schemas automatically skip insert functions
  ```

  **Struct factory** (default) - Generates all functions

  ```elixir
  deffactory user(params \\ %{}), struct: User do
    %{username: "user-#{System.os_time()}"} |> Map.merge(params)
  end
  # Generates: build_user_params, build_user_struct, insert_user! (and _list variants)
  ```

  **No insert** (`:insert? false`) - Generates params and struct builders, skips insert functions

  ```elixir
  deffactory read_only_user(params \\ %{}), struct: User, insert?: false do
    %{username: "readonly-user"}
  end
  # Generates: build_read_only_user_params, build_read_only_user_struct (and _list variants)
  # Skips: insert_read_only_user!
  ```

  ## Defining Factories

  The `deffactory` macro works like defining a function. You specify the factory name and a single
  parameter (e.g. `params`), with an optional default value (e.g. `%{}`):

  ```elixir
  deffactory user(params \\ %{}), struct: User do
    base_params = %{username: "user-#{System.os_time()}"}

    Map.merge(base_params, params)
  end
  ```

  You can name the parameter whatever you want:

  ```elixir
  deffactory user(attrs \\ %{}), struct: User do
    base_attrs = %{username: "user-#{System.os_time()}"}

    Map.merge(base_attrs, attrs)
  end
  ```

  You can also pattern match on the parameter to require specific keys:

  ```elixir
  deffactory user_from_config(%{username: username} = params), struct: User do
    base_params = %{username: username}

    Map.merge(base_params, params)
  end
  ```

  **Non-struct factories** (simple params-only):

  Use factories without the `:struct` option for building plain data structures:

  ```elixir
  deffactory api_payload(params \\ %{}) do
    %{
      action: "create",
      resource: "user",
      data: %{
        username: sequence("user"),
        email: sequence(:email, &"test\#{&1}@example.com")
      }
    }
    |> Map.merge(params)
  end
  ```

  Usage:

  ```elixir
  iex> MyApp.Factory.build_api_payload_params()
  %{action: "create", resource: "user", data: %{username: "user0", email: "test0@example.com"}}

  iex> MyApp.Factory.build_api_payload_params(%{action: "update"})
  %{action: "update", resource: "user", data: %{username: "user1", email: "test1@example.com"}}
  ```

  **Building factories on other factories:**

  Call other factory functions within a factory definition to automatically create required
  associations:

  ```elixir
  deffactory author(params \\ %{}), struct: Author do
    base_params = %{
      name: "Test Author",
      # Automatically build associated user if not provided
      user: params[:user] || build_user_struct()
    }

    Map.merge(base_params, params)
  end
  ```

  Extend and customize existing factories:

  ```elixir
  deffactory user(params \\ %{}), struct: User do
    base_params = %{username: "user-#{System.os_time()}"}

    Map.merge(base_params, params)
  end

  deffactory admin(params \\ %{}), struct: User do
    # Reuse user factory, override role
    base_params = %{role: "admin"}

    params
    |> build_user_params()    # Get base user params
    |> Map.merge(base_params) # Add admin overrides
    |> Map.merge(params)      # Apply caller overrides
  end
  ```

  ## Factory Options

  Options cascade from parent module to child module to individual factory, letting you configure
  behavior at whichever level is right for you:

  **Module-level options** (set with `use FactoryMan`):
  - `:repo` - Ecto repo for database operations (required for insert functions)
  - `:extends` - Parent factory module to inherit common configuration
  - `:hooks` - Hooks applied to all factories in the module
  - `:suppress_duplicate_option_warning` - Set to `true` to suppress warnings when this module
  specifies an option that is already defined by the parent with the same value

  **Factory-level options** (set with `deffactory`):
  - `:struct` - Ecto schema struct to build (generates struct and insert functions)
  - `:insert?` - Set to `false` to prevent accidental database insertion (e.g. for read-only test
  data)
  - `:build_struct?` - Set to `false` when you only need raw params (e.g. for API request bodies)
  - `:build_params?` (boolean, defaut: `true`) - Set to `false` to skip params builder generation. The
  factory body returns a struct directly instead of a params map. Requires `:struct` to be set.
  Useful for complex factories that need full control over struct construction
  - `:hooks` - Additional hooks merged with module-level hooks
  - `:suppress_duplicate_option_warning` - Set to `true` to suppress warnings when this factory
  specifies an option that is already defined by the module with the same value

  ## Factory Inheritance

  Use inheritance to avoid repeating common configuration across multiple factory modules:

  ```elixir
  defmodule MyApp.Factory do
    use FactoryMan, repo: MyApp.Repo

    def generate_username, do: "user-#{System.os_time()}"
  end
  ```

  Child factories inherit the parent's repo, hooks, and helper functions via `:extends`:

  ```elixir
  defmodule MyApp.Factory.ChildFactory do
    use FactoryMan, extends: MyApp.Factory

    alias MyApp.Users.User

    deffactory user(params \\ %{}), struct: User do
      %{username: generate_username()} |> Map.merge(params)
    end
  end
  ```

  **Child factories can also be extended** - inheritance chains are unlimited:

  ```elixir
  # test/support/factory/child_factory.ex
  defmodule MyApp.Factory.ChildFactory do
    use FactoryMan, extends: MyApp.Factory

    def generate_email, do: "user-#{System.os_time()}@example.com"

    deffactory user(params \\ %{}), struct: User do
      %{username: generate_username()} |> Map.merge(params)
    end
  end

  # test/support/factory/child_factory/child_child_factory.ex
  defmodule MyApp.Factory.ChildFactory.ChildChildFactory do
    use FactoryMan, extends: MyApp.Factory.ChildFactory

    # Inherits :repo from MyApp.Factory
    # Inherits generate_username/0 and generate_email/0 from MyApp.Factory.ChildFactory

    deffactory admin(params \\ %{}), struct: User do
      %{
        username: generate_username(),
        email: generate_email(),
        role: "admin"
      }
      |> Map.merge(params)
    end
  end
  ```

  **Options cascade through all levels:**
  Parent module options → Child module options → Individual factory options.
  Later options override earlier ones, letting you customize at any level.

  ```elixir
  defmodule MyApp.Factory do
    use FactoryMan,
      repo: MyApp.Repo,
      hooks: [after_insert: &reset_assocs/1]
  end

  defmodule MyApp.Factories.Users do
    use FactoryMan,
      extends: MyApp.Factory,
      hooks: [before_build_params: &log_build/1]  # Merged with parent hooks

    # Inherits :repo and both hooks from MyApp.Factory
    deffactory user(params \\\\ %{}), struct: User do
      base_params = %{username: "user-#{System.os_time()}"}

      Map.merge(base_params, params)
    end

    # Override hooks for this specific factory only
    deffactory admin(params \\\\ %{}), struct: User, hooks: [after_insert: &promote_to_admin/1] do
      base_params = %{username: "admin-#{System.os_time()}"}

      Map.merge(base_params, params)
    end
  end
  ```

  ## List Factories

  Create multiple records:

  ```elixir
  iex> MyApp.Factories.Users.build_user_struct_list(3)
  [%User{id: nil, ...}, %User{id: nil, ...}, %User{id: nil, ...}]

  iex> MyApp.Factories.Users.insert_user_list!(3)
  [%User{id: 1, ...}, %User{id: 2, ...}, %User{id: 3, ...}]

  # With custom params
  MyApp.Factories.Users.insert_user_list!(2, %{role: "admin"}, returning: true)
  ```

  Each item is evaluated independently, so timestamps and sequences generate unique values.

  ## Sequence Generation

  Generate unique values across test runs:

  Basic sequences:

  ```elixir
  deffactory user(params \\ %{}), struct: User do
    base_params = %{username: sequence("user")}  # user0, user1, user2...

    Map.merge(base_params, params)
  end
  ```

  Custom formatters:

  ```elixir
  deffactory user(params \\ %{}), struct: User do
    base_params = %{
      email: sequence(:email, fn n -> "user\#{n}@example.com" end)
    }

    Map.merge(base_params, params)
  end
  ```

  Cyclical sequences:

  ```elixir
  deffactory user(params \\ %{}), struct: User do
    base_params = %{
      role: sequence(:role, ["admin", "moderator", "user"])
    }

    Map.merge(base_params, params)
  end
  ```

  Custom starting value:

  ```elixir
  deffactory order(params \\ %{}), struct: Order do
    base_params = %{
      order_number: sequence(:order, fn n -> "ORD-\#{n}" end, start_at: 1000)
    }

    Map.merge(base_params, params)
  end
  ```

  Reset sequences in test setup for predictable values:

  ```elixir
  setup do
    FactoryMan.Sequence.reset()
    :ok
  end
  ```

  ## Lazy Evaluation

  Functions in factory params are evaluated at build time:

  ```elixir
  deffactory user(params \\ %{}), struct: User do
    base_params = %{
      username: "user-#{System.os_time()}",

      # 0-arity lazy evaluation: called with no arguments
      created_at: fn -> DateTime.utc_now() end,

      # 1-arity lazy evaluation: receives the parent factory
      display_name: fn user -> "\#{user.username} (User)" end
    }

    Map.merge(base_params, params)
  end
  ```

  > #### Lazy evaluation ordering {: .warning}
  >
  > 1-arity lazy functions receive the **original map before any lazy evaluation**. This means
  > if field A is a 0-arity lazy function and field B is a 1-arity function that references A,
  > B will see A as a function reference, not its resolved value.
  >
  > To avoid surprises, make sure fields that 1-arity lazy functions depend on are **plain
  > values**, not lazy functions themselves.
  >
  > ```elixir
  > # Good: first_name is a plain value, so full_name can read it
  > %{
  >   first_name: "John",
  >   full_name: fn user -> "\#{user.first_name} Smith" end
  > }
  >
  > # Bad: first_name is lazy, so full_name will see a function, not a string
  > %{
  >   first_name: fn -> "John" end,
  >   full_name: fn user -> "\#{user.first_name} Smith" end
  > }
  > ```

  ## Hooks

  Transform data at specific stages. Every factory action has both a `before` and `after` hook,
  letting you intercept and modify data at the exact point you need.

  ### Hook Pipeline

  Each generated function uses a subset of the pipeline. The full flow for `insert_user!` is:

  ```text
  build_user_params:
    before_build_params → [factory body + lazy eval] → after_build_params

  build_user_struct (calls build_user_params internally):
    → before_build_struct → struct!() → after_build_struct

  insert_user! (calls build_user_struct internally):
    → before_insert → Repo.insert!() → after_insert
  ```

  ### Hook Reference

  | Hook                   | Receives        | Returns         | When to Use                                      |
  | ---------------------- | --------------- | --------------- | ------------------------------------------------ |
  | `:before_build_params` | params (map)    | params (map)    | Transform or inject params before the factory body runs |
  | `:after_build_params`  | params (map)    | params (map)    | Modify params after the factory body (e.g. add computed fields) |
  | `:before_build_struct` | params (map)    | params (map)    | Last chance to modify params before `struct!()` is called |
  | `:after_build_struct`  | struct          | struct          | Transform the struct after creation (e.g. set virtual fields) |
  | `:before_insert`       | struct          | struct          | Modify struct just before database insertion |
  | `:after_insert`        | struct          | struct          | Post-process after insertion (e.g. reset associations) |

  ### Hook Precedence

  Hooks can be set at three levels. Later levels override earlier ones for the same hook key:

  1. **Parent module** — `use FactoryMan, hooks: [...]`
  2. **Child module** — `use FactoryMan, extends: Parent, hooks: [...]`
  3. **Individual factory** — `deffactory name(params), hooks: [...]`

  ### Examples

  **Reset associations after insert** (most common hook usage):

  ```elixir
  defmodule MyApp.Factory do
    use FactoryMan,
      repo: MyApp.Repo,
      hooks: [after_insert: &__MODULE__.reset_assocs/1]

    def reset_assocs(struct) do
      Ecto.reset_fields(struct, struct.__struct__.__schema__(:associations))
    end
  end
  ```

  **Log factory usage for debugging:**

  ```elixir
  deffactory user(params \\ %{}), struct: User,
    hooks: [after_build_params: &__MODULE__.log_params/1] do
    %{username: "user-#{System.os_time()}"} |> Map.merge(params)
  end

  def log_params(params) do
    IO.inspect(params, label: "factory params")
    params
  end
  ```

  ## Embedded Schemas

  Factories for embedded schemas work like regular struct factories but without database
  insertion:

  ```elixir
  defmodule MyApp.Factories.Settings do
    use FactoryMan, extends: MyApp.Factory

    alias MyApp.Users.Settings

    deffactory settings(params \\ %{}), struct: Settings do
      base_params = %{
        theme: "dark",
        notifications: true
      }

      Map.merge(base_params, params)
    end
  end
  ```

  Embedded schemas generate `build_*_params` and `build_*_struct` functions only (as well as
  the matching `*_list` functions), but do not generate any `insert_*` functions.

  ## Direct Struct Factories (`build_params?: false`)

  For complex factories that need full control over struct construction, set `build_params?: false`.
  The factory body returns a struct directly instead of a params map, and no `build_*_params`
  functions are generated:

  ```elixir
  deffactory invoice(params \\ %{}), struct: Invoice, build_params?: false do
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
  **not** `build_invoice_params`. The `after_build_struct`, `before_insert`, and `after_insert`
  hooks still run. The `before_build_params`, `after_build_params`, and `before_build_struct`
  hooks are skipped since there is no params-to-struct conversion stage.

  `build_params?: false` can also be set at the module level with `use FactoryMan, build_params?: false`,
  then overridden per-factory with `build_params?: true` if needed.

  ## Variant Factories (`defvariant`)

  A variant wraps an existing base factory. It transforms the caller's params **before** passing
  them to the base factory. Think of it as a preprocessor: the variant runs first, then the
  base factory runs with the transformed params.

  This ordering can be counterintuitive because the variant is defined **after** the base
  factory in your code, but its logic executes **before** the base factory at runtime:

  ```text
  Code order:     deffactory user(...)   ->  defvariant admin(...), for: :user
  Execution order:  admin (preprocessor)  ->  user (base factory)
  ```

  ### Example

  ```elixir
  deffactory user(params \\\\ %{}), struct: User do
    %{username: sequence("user"), role: "member"}
    |> Map.merge(params)
  end

  # The admin variant sets role to "admin", then delegates to :user.
  # Caller params override variant defaults (merge variant defaults first,
  # then caller params on top):
  defvariant admin(params \\\\ %{}), for: :user do
    Map.merge(%{role: "admin"}, params)
  end
  ```

  Calling `build_admin_user_struct()` is equivalent to `build_user_struct(%{role: "admin"})`.
  Calling `build_admin_user_struct(%{role: "superadmin"})` passes `%{role: "superadmin"}` to
  the base factory because the caller's params override the variant defaults.

  Generated functions follow the pattern `{variant}_{base}`:
  `build_admin_user_params/0,1`, `build_admin_user_struct/0,1`, `insert_admin_user!/0,1,2`,
  plus list variants.

  ### Custom naming with `:as`

  The `:as` option overrides the combined `{variant}_{base}` name:

  ```elixir
  defvariant moderator(params \\\\ %{}), for: :user, as: :mod do
    Map.merge(params, %{role: "moderator"})
  end
  ```

  This generates `build_mod_struct/0,1`, `insert_mod!/0,1,2`, etc.
  — instead of the default `build_moderator_user_struct`.

  ## Duplicate Option Warnings

  If a child factory module specifies an option that is already defined by its parent with the
  same value, FactoryMan will emit a compile-time warning. This helps catch redundant options
  that were likely copy-pasted from the parent.

  To suppress the warning for a specific module or factory, add
  `suppress_duplicate_option_warning: true` to the options.

  ## Debugging

  FactoryMan generates debug functions showing configured options:

  ```elixir
  iex> MyApp.Factory._factory_opts()
  [repo: MyApp.Repo]

  iex> MyApp.Factories.Users._user_factory_opts()
  [repo: MyApp.Repo, struct: User]
  ```
  """

  require Logger

  # Keys that should not trigger duplicate option warnings
  @duplicate_warning_skip_keys [:extends, :suppress_duplicate_option_warning]

  defmacro __using__(opts \\ []) do
    quote do
      import unquote(__MODULE__),
        only: [deffactory: 2, deffactory: 3, defvariant: 3]

      Module.register_attribute(__MODULE__, :factory_man_registry, accumulate: true)

      parent_factory_opts =
        case unquote(opts)[:extends] do
          nil ->
            # Use opts from current factory only
            unquote(opts)

          extends ->
            # Extend base factory opts
            parent_opts = extends.__info__(:attributes)[:parent_factory_opts] || []

            FactoryMan._warn_duplicate_options(
              parent_opts,
              unquote(opts),
              "module #{inspect(__MODULE__)}"
            )

            Keyword.merge(parent_opts, unquote(opts))
        end

      # Put factory module options into a module attribute that can be read by the child factories
      Module.register_attribute(__MODULE__, :parent_factory_opts, persist: true)

      Module.put_attribute(
        __MODULE__,
        :parent_factory_opts,
        parent_factory_opts |> Keyword.delete(:suppress_duplicate_option_warning)
      )

      @doc """
      A debug helper function that shows all the options for the `#{inspect(__MODULE__)}` factory
      module.
      """
      def _factory_opts, do: @parent_factory_opts
    end
  end

  @doc """
  Defines a factory that generates test data.

  The `deffactory` macro creates a set of functions for building test data. It works like
  defining a function, where you specify the factory name and a parameter (typically `params`).

  ## Options

  - `:struct` - The Ecto schema module to build structs from. When provided, generates
    struct and insert functions in addition to params builders.
  - `:insert?` - Set to `false` to skip generating insert functions (default: `true` when
    repo is configured and struct is insertable)
  - `:build_struct?` - Set to `false` to skip generating struct builder functions (default: `true`)
  - `:hooks` - A keyword list of hook functions to apply at different stages (see Hooks section)
  - `:suppress_duplicate_option_warning` - Set to `true` to suppress warnings when this
    factory specifies an option already defined by the module with the same value

  ## Generated Functions

  For a factory named `user` which builds a struct, the following functions are generated:

  - `build_user_params/1` - Returns plain params
  - `build_user_struct/1` - Returns an unsaved struct (when `:struct` is set)
  - `insert_user!/1` - Inserts into the database (when `:struct` is set and repo is configured)
  - `build_user_params_list/2` - Builds multiple items
  - `build_user_struct_list/2` - Builds multiple structs (when `:struct` is set)
  - `insert_user_list!/2` - Inserts multiple items (when `:struct` is set and repo is configured)

  ## Examples

      deffactory user(params \\ %{}), struct: User do
        base_params = %{
          username: sequence("user"),
          email: sequence(:email, fn n -> "user\#{n}@example.com" end)
        }

        Map.merge(base_params, params)
      end

      iex> MyApp.Factory.build_user_params(%{username: "alice"})
      %{username: "alice", email: "user0@example.com"}

      iex> MyApp.Factory.insert_user!(%{role: "admin"})
      %User{id: 1, username: "user1", email: "admin@example.com", role: "admin"}

  """

  defmacro deffactory(factory_head, opts \\ [], do: block) do
    # Recursively extract factory name and argument information from AST
    extraction = extract_factory_args(factory_head)

    factory_name = extraction.name
    arg_ast = extraction.arg_ast
    head_ast = extraction.head_ast
    user_var = extraction.user_var
    arg_ast_no_default = extraction.arg_no_default
    has_pattern_match = extraction.has_pattern_match
    plain_var_ast = extraction.plain_var

    quote bind_quoted: [
            factory_name: factory_name,
            arg_ast: Macro.escape(arg_ast, unquote: true),
            head_ast: Macro.escape(head_ast, unquote: true),
            user_var: Macro.escape(user_var, unquote: true),
            arg_ast_no_default: Macro.escape(arg_ast_no_default, unquote: true),
            has_pattern_match: has_pattern_match,
            plain_var_ast: Macro.escape(plain_var_ast, unquote: true),
            opts: opts,
            block: Macro.escape(block, unquote: true)
          ] do
      parent_factory_opts = Module.get_attribute(__MODULE__, :parent_factory_opts)

      FactoryMan._warn_duplicate_options(
        parent_factory_opts,
        opts,
        "factory :#{factory_name} in #{inspect(__MODULE__)}"
      )

      parent_factory_hooks = Keyword.get(parent_factory_opts, :hooks, [])
      child_factory_hooks = Keyword.get(opts, :hooks, [])
      merged_hooks = Keyword.merge(parent_factory_hooks, child_factory_hooks)

      merged_opts = Keyword.merge(parent_factory_opts, opts) |> Keyword.put(:hooks, merged_hooks)

      @doc "A debug helper function that shows all options for the `#{factory_name}` factory."
      def unquote(String.to_atom("_#{factory_name}_factory_opts"))(), do: unquote(merged_opts)

      # Extract hooks - used many times throughout
      hooks = merged_hooks

      # Validate: build_params?: false requires struct: option
      if merged_opts[:build_params?] == false and is_nil(merged_opts[:struct]) do
        raise ArgumentError,
              "deffactory #{factory_name}: build_params?: false requires the struct: option, " <>
                "otherwise no functions would be generated"
      end

      # Generate params builder functions (skipped when build_params?: false)
      if merged_opts[:build_params?] != false do
        # Head declaration (simple variable with default if present)
        def unquote({:"build_#{factory_name}_params", [], [head_ast]})

        # Implementation (with pattern matching if needed, no default)
        def unquote({:"build_#{factory_name}_params", [], [arg_ast_no_default]}) do
          unquote(user_var) =
            FactoryMan.get_hook_handler(unquote(hooks), :before_build_params).(unquote(user_var))

          unquote(block)
          |> FactoryMan.evaluate_lazy_attributes()
          |> then(&FactoryMan.get_hook_handler(unquote(hooks), :after_build_params).(&1))
        end

        # Generate params list builder function
        # Only generate convenience function if there's no pattern match without default
        if not has_pattern_match do
          def unquote(:"build_#{factory_name}_params_list")(count)
              when is_integer(count) and count >= 0 do
            unquote(:"build_#{factory_name}_params_list")(count, %{})
          end
        end

        def unquote(:"build_#{factory_name}_params_list")(count, params)
            when is_integer(count) and count >= 0 and is_map(params) do
          Stream.repeatedly(fn -> unquote(:"build_#{factory_name}_params")(params) end)
          |> Enum.take(count)
        end
      end

      if merged_opts[:struct] != nil and merged_opts[:build_struct?] != false do
        if merged_opts[:build_params?] != false do
          # Generate struct builder function (standard: delegates to params builder)
          # Head declaration (simple variable with default if present)
          def unquote({:"build_#{factory_name}_struct", [], [head_ast]})

          # Implementation - uses plain_var_ast since pattern match variables
          # are only needed in the params builder body
          def unquote({:"build_#{factory_name}_struct", [], [plain_var_ast]}) do
            unquote(user_var)
            |> unquote(:"build_#{factory_name}_params")()
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :before_build_struct).(&1))
            |> then(&struct!(unquote(merged_opts[:struct]), &1))
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :after_build_struct).(&1))
          end
        else
          # Generate struct builder function (build_params?: false: body returns struct directly)
          # Head declaration (simple variable with default if present)
          def unquote({:"build_#{factory_name}_struct", [], [head_ast]})

          # Implementation - uses arg_ast_no_default since pattern matching
          # is needed in the body (same role as params builder in standard mode)
          def unquote({:"build_#{factory_name}_struct", [], [arg_ast_no_default]}) do
            unquote(block)
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :after_build_struct).(&1))
          end
        end

        # Generate struct list builder function
        # Only generate convenience function if there's no pattern match without default
        if not has_pattern_match do
          def unquote(:"build_#{factory_name}_struct_list")(count)
              when is_integer(count) and count >= 0 do
            unquote(:"build_#{factory_name}_struct_list")(count, %{})
          end
        end

        def unquote(:"build_#{factory_name}_struct_list")(count, params)
            when is_integer(count) and count >= 0 and is_map(params) do
          Stream.repeatedly(fn ->
            unquote(:"build_#{factory_name}_struct")(params)
          end)
          |> Enum.take(count)
        end

        struct_module = merged_opts[:struct]
        repo = merged_opts[:repo]
        insert? = merged_opts[:insert?]

        is_insertable_ecto_schema_factory? =
          ((not is_nil(repo) and Code.ensure_compiled!(struct_module)) &&
             function_exported?(struct_module, :__schema__, 1)) and
            struct_module.__schema__(:source) != nil

        if is_insertable_ecto_schema_factory? and insert? != false do
          # Generate struct insert functions
          # Head declaration (simple variable with default if present)
          def unquote({:"insert_#{factory_name}!", [], [head_ast]})

          # Only generate convenience function if there's no pattern match without default
          # Pattern matches require specific keys, so we can't call with %{}
          if not has_pattern_match do
            def unquote(:"insert_#{factory_name}!")(repo_insert_opts)
                when is_list(repo_insert_opts) do
              unquote(:"insert_#{factory_name}!")(%{}, repo_insert_opts)
            end
          end

          # Implementation - uses plain_var_ast since pattern match variables
          # are only needed in the params builder body
          def unquote(:"insert_#{factory_name}!")(unquote(plain_var_ast)) do
            unquote(:"insert_#{factory_name}!")(unquote(user_var), [])
          end

          def unquote(:"insert_#{factory_name}!")(
                unquote(plain_var_ast),
                repo_insert_opts
              )
              when is_list(repo_insert_opts) do
            unquote(user_var)
            |> unquote(:"build_#{factory_name}_struct")()
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :before_insert).(&1))
            |> unquote(repo).insert!(repo_insert_opts)
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :after_insert).(&1))
          end

          # Generate struct insert list functions
          # Only generate convenience functions if there's no pattern match without default
          if not has_pattern_match do
            def unquote(:"insert_#{factory_name}_list!")(count)
                when is_integer(count) and count >= 0 do
              unquote(:"insert_#{factory_name}_list!")(count, %{}, [])
            end

            def unquote(:"insert_#{factory_name}_list!")(count, repo_insert_opts)
                when is_integer(count) and count >= 0 and is_list(repo_insert_opts) do
              unquote(:"insert_#{factory_name}_list!")(count, %{}, repo_insert_opts)
            end
          end

          def unquote(:"insert_#{factory_name}_list!")(count, params)
              when is_integer(count) and count >= 0 and is_map(params) do
            unquote(:"insert_#{factory_name}_list!")(count, params, [])
          end

          def unquote(:"insert_#{factory_name}_list!")(count, params, repo_insert_opts)
              when is_integer(count) and count >= 0 and is_map(params) and
                     is_list(repo_insert_opts) do
            Stream.repeatedly(fn ->
              unquote(:"insert_#{factory_name}!")(params, repo_insert_opts)
            end)
            |> Enum.take(count)
          end
        end
      end

      # Register factory metadata so defvariant can look up base factory capabilities
      @factory_man_registry {factory_name, merged_opts}
    end
  end

  @doc """
  Defines a variant factory that wraps a base factory.

  A variant is a preprocessor: it receives the caller's params, transforms them, and delegates
  to the base factory. The variant body runs **before** the base factory, not after.

  ## Example

      deffactory user(params \\\\ %{}), struct: User do
        %{username: sequence("user"), role: "member"} |> Map.merge(params)
      end

      # The variant body receives params first, transforms them, then passes to :user
      defvariant admin(params \\\\ %{}), for: :user do
        Map.merge(params, %{role: "admin"})
      end

      # Generated: build_admin_user_struct/0,1, insert_admin_user!/0,1,2, etc.
      # Calling build_admin_user_struct() is equivalent to:
      #   build_user_struct(%{role: "admin"})

  ## Options

  - `:for` - (atom, required) The name of the base factory to wrap (e.g. `:user`)

  - `:as` - Instead of the default `<variant>_<base>` structure (e.g. `admin_user`), you may
  specify a custom name for the factory (e.g. `:admin`)
  """

  defmacro defvariant(variant_head, opts, do: block) do
    extraction = extract_factory_args(variant_head)

    variant_name = extraction.name
    arg_ast = extraction.arg_ast
    head_ast = extraction.head_ast
    user_var = extraction.user_var
    arg_ast_no_default = extraction.arg_no_default
    has_pattern_match = extraction.has_pattern_match
    plain_var_ast = extraction.plain_var

    base_factory_name = opts[:for] || raise ArgumentError, "defvariant requires the :for option"
    as_name = opts[:as]

    quote bind_quoted: [
            variant_name: variant_name,
            base_factory_name: base_factory_name,
            as_name: as_name,
            arg_ast: Macro.escape(arg_ast, unquote: true),
            head_ast: Macro.escape(head_ast, unquote: true),
            user_var: Macro.escape(user_var, unquote: true),
            arg_ast_no_default: Macro.escape(arg_ast_no_default, unquote: true),
            has_pattern_match: has_pattern_match,
            plain_var_ast: Macro.escape(plain_var_ast, unquote: true),
            block: Macro.escape(block, unquote: true)
          ] do
      # Look up the base factory's registered metadata
      base_entry =
        @factory_man_registry
        |> Enum.find(fn {name, _opts} -> name == base_factory_name end)

      if is_nil(base_entry) do
        raise ArgumentError,
              "defvariant #{variant_name}: base factory :#{base_factory_name} not found. " <>
                "Ensure deffactory :#{base_factory_name} is defined before defvariant."
      end

      {_base_name, base_opts} = base_entry

      # Variant function names combine variant + base: e.g. :admin + :user = :admin_user
      # The :as option overrides this combined name.
      full_name = as_name || :"#{variant_name}_#{base_factory_name}"

      # Generate params builder variant (if base factory has params)
      if base_opts[:build_params?] != false do
        def unquote({:"build_#{full_name}_params", [], [head_ast]})

        def unquote({:"build_#{full_name}_params", [], [arg_ast_no_default]}) do
          unquote(block)
          |> unquote(:"build_#{base_factory_name}_params")()
        end

        if not has_pattern_match do
          def unquote(:"build_#{full_name}_params_list")(count)
              when is_integer(count) and count >= 0 do
            unquote(:"build_#{full_name}_params_list")(count, %{})
          end
        end

        def unquote(:"build_#{full_name}_params_list")(count, params)
            when is_integer(count) and count >= 0 and is_map(params) do
          Stream.repeatedly(fn ->
            unquote(:"build_#{full_name}_params")(params)
          end)
          |> Enum.take(count)
        end
      end

      # Generate struct builder variant (if base factory has struct)
      if base_opts[:struct] != nil and base_opts[:build_struct?] != false do
        def unquote({:"build_#{full_name}_struct", [], [head_ast]})

        def unquote({:"build_#{full_name}_struct", [], [arg_ast_no_default]}) do
          unquote(block)
          |> unquote(:"build_#{base_factory_name}_struct")()
        end

        if not has_pattern_match do
          def unquote(:"build_#{full_name}_struct_list")(count)
              when is_integer(count) and count >= 0 do
            unquote(:"build_#{full_name}_struct_list")(count, %{})
          end
        end

        def unquote(:"build_#{full_name}_struct_list")(count, params)
            when is_integer(count) and count >= 0 and is_map(params) do
          Stream.repeatedly(fn ->
            unquote(:"build_#{full_name}_struct")(params)
          end)
          |> Enum.take(count)
        end

        # Generate insert variant -- delegates to base factory's insert
        # (reuses base factory's hooks, repo config, and insert pipeline)
        struct_module = base_opts[:struct]
        repo = base_opts[:repo]
        insert? = base_opts[:insert?]

        is_insertable_ecto_schema_factory? =
          ((not is_nil(repo) and Code.ensure_compiled!(struct_module)) &&
             function_exported?(struct_module, :__schema__, 1)) and
            struct_module.__schema__(:source) != nil

        if is_insertable_ecto_schema_factory? and insert? != false do
          # Head declaration
          def unquote({:"insert_#{full_name}!", [], [head_ast]})

          if not has_pattern_match do
            def unquote(:"insert_#{full_name}!")(repo_insert_opts)
                when is_list(repo_insert_opts) do
              unquote(:"insert_#{full_name}!")(%{}, repo_insert_opts)
            end
          end

          def unquote(:"insert_#{full_name}!")(unquote(plain_var_ast)) do
            unquote(:"insert_#{full_name}!")(unquote(user_var), [])
          end

          def unquote(:"insert_#{full_name}!")(
                unquote(arg_ast_no_default),
                repo_insert_opts
              )
              when is_list(repo_insert_opts) do
            # Transform params via variant body, then delegate to base insert
            unquote(block)
            |> unquote(:"insert_#{base_factory_name}!")(repo_insert_opts)
          end

          # List insert variants
          if not has_pattern_match do
            def unquote(:"insert_#{full_name}_list!")(count)
                when is_integer(count) and count >= 0 do
              unquote(:"insert_#{full_name}_list!")(count, %{}, [])
            end

            def unquote(:"insert_#{full_name}_list!")(
                  count,
                  repo_insert_opts
                )
                when is_integer(count) and count >= 0 and is_list(repo_insert_opts) do
              unquote(:"insert_#{full_name}_list!")(
                count,
                %{},
                repo_insert_opts
              )
            end
          end

          def unquote(:"insert_#{full_name}_list!")(count, params)
              when is_integer(count) and count >= 0 and is_map(params) do
            unquote(:"insert_#{full_name}_list!")(count, params, [])
          end

          def unquote(:"insert_#{full_name}_list!")(
                count,
                params,
                repo_insert_opts
              )
              when is_integer(count) and count >= 0 and is_map(params) and
                     is_list(repo_insert_opts) do
            Stream.repeatedly(fn ->
              unquote(:"insert_#{full_name}!")(params, repo_insert_opts)
            end)
            |> Enum.take(count)
          end
        end
      end
    end
  end

  # Extracts all necessary components from the factory_head AST recursively.
  # Handles: params, params \\ %{}, %{key: val} = params, and variations.
  defp extract_factory_args(factory_head) do
    # First, extract the factory name and the argument list
    {name, args} = extract_name_and_args(factory_head)

    # Now recursively process the argument to extract all components
    process_arg(args, name)
  end

  # Extract factory name and argument list from the head
  defp extract_name_and_args({name, _, args}) when is_list(args) do
    # Factory head is like: user(params) or user(params \\ %{})
    {name, args}
  end

  # Process the argument AST recursively
  defp process_arg([arg_ast], name) do
    # Recursively walk the AST to extract components
    components = walk_arg_ast(arg_ast)

    # Build the result map
    %{
      name: name,
      arg_ast: arg_ast,
      head_ast: components.head_ast,
      user_var: components.user_var,
      arg_no_default: components.arg_no_default,
      has_pattern_match: components.has_pattern_match,
      plain_var: components.plain_var
    }
  end

  # Catch-all for invalid argument counts
  defp process_arg(args, _name) when is_list(args) do
    raise ArgumentError, """
    Invalid factory definition: expected exactly one argument, got #{length(args)}

    FactoryMan factories must have exactly one parameter (typically `params`).

    Valid examples:
      deffactory user(params \\ %{}), struct: User do ... end
      deffactory author(%{name: name} = params), struct: Author do ... end
    """
  end

  # Recursively walk the argument AST and extract all necessary components
  defp walk_arg_ast(ast) do
    do_walk_arg_ast(ast, %{
      head_ast: nil,
      user_var: nil,
      arg_no_default: nil,
      has_pattern_match: false,
      plain_var: nil
    })
  end

  # Case 1: Pattern match with default - %{key: val} = params \\ %{}
  # AST: {:\\, _, [{:=, _, [pattern, {var, _, _}]}, default]}
  defp do_walk_arg_ast({:\\, _, [{:=, _, [_pattern, var_ast]} = pattern, default]}, acc) do
    var_name = extract_var_name(var_ast)
    # For function head, use just the variable with default (no pattern match)
    head_ast = {:\\, [], [Macro.var(var_name, nil), default]}
    user_var = Macro.var(var_name, nil)

    %{
      acc
      | head_ast: head_ast,
        user_var: user_var,
        # Keep the full pattern for implementation
        arg_no_default: pattern,
        has_pattern_match: true,
        plain_var: var_ast
    }
  end

  # Case 2: Variable with default - params \\ %{}
  # AST: {:\\, _, [{var, _, _}, default]}
  defp do_walk_arg_ast({:\\, _, [var_ast, _default]} = ast, acc) do
    var_name = extract_var_name(var_ast)
    # Keep the full \\ expression for head
    head_ast = ast
    user_var = Macro.var(var_name, nil)

    %{
      acc
      | head_ast: head_ast,
        user_var: user_var,
        arg_no_default: var_ast,
        has_pattern_match: false,
        plain_var: var_ast
    }
  end

  # Case 4: Pattern match without default - %{key: val} = params
  # AST: {:=, _, [pattern, {var, _, _}]}
  defp do_walk_arg_ast({:=, _, [_pattern, var_ast]} = ast, acc) do
    var_name = extract_var_name(var_ast)
    # Use just the var for head (no destructuring)
    head_ast = Macro.var(var_name, nil)
    user_var = Macro.var(var_name, nil)

    %{
      acc
      | head_ast: head_ast,
        user_var: user_var,
        # Keep the full pattern for implementation
        arg_no_default: ast,
        has_pattern_match: true,
        plain_var: var_ast
    }
  end

  # Case 5: Simple variable - params
  # AST: {var, _, _}
  defp do_walk_arg_ast({var_name, _, _} = ast, acc) when is_atom(var_name) do
    user_var = Macro.var(var_name, nil)

    %{
      acc
      | head_ast: ast,
        user_var: user_var,
        arg_no_default: ast,
        has_pattern_match: false,
        plain_var: ast
    }
  end

  # Catch-all for unsupported patterns
  defp do_walk_arg_ast(ast, _acc) do
    raise ArgumentError, """
    Unsupported factory argument pattern: #{Macro.to_string(ast)}

    FactoryMan supports these patterns:
      - params
      - params \\ %{}
      - %{key: value} = params
      - %{key: value} = params \\ %{key: default}

    If you need a different pattern, please open an issue.
    """
  end

  # Extract variable name from a variable AST node
  defp extract_var_name({var_name, _, _}) when is_atom(var_name), do: var_name

  @doc """
  Evaluate lazy attributes in a map or struct.

  Functions with 0 arity are called with no arguments.
  Functions with 1 arity receive the parent factory as their argument.

  ## Examples

      iex> FactoryMan.evaluate_lazy_attributes(
      ...> %{name: "test", timestamp: fn -> System.os_time() end}
      ...> )
      %{name: "test", timestamp: 12345}

      iex> FactoryMan.evaluate_lazy_attributes(
      ...>   %{first: "John", last: fn attrs -> attrs.first <> " Smith" end}
      ...> )
      %{first: "John", last: "John Smith"}
  """
  @spec evaluate_lazy_attributes(struct | map) :: struct | map
  def evaluate_lazy_attributes(%{__struct__: record} = factory) do
    struct!(record, factory |> Map.from_struct() |> do_evaluate_lazy_attributes(factory))
  end

  def evaluate_lazy_attributes(attrs) when is_map(attrs) do
    do_evaluate_lazy_attributes(attrs, attrs)
  end

  defp do_evaluate_lazy_attributes(attrs, parent_factory) do
    attrs
    |> Enum.map(fn
      {k, v} when is_function(v, 1) -> {k, v.(parent_factory)}
      {k, v} when is_function(v) -> {k, v.()}
      {_, _} = tuple -> tuple
    end)
    |> Enum.into(%{})
  end

  @doc """
  The default handler for hooks. This function is a no-op, and simply returns the given `value`
  without any modifications.

  ## Examples

      iex> FactoryMan.fallback_hook_handler(123)
      123
  """
  def fallback_hook_handler(value), do: value

  @doc """
  Get the configured handler for a `hook`, or fall back to `&FactoryMan.fallback_hook_handler/0`.

  ## Examples

      iex> hooks = [after_insert: &YourProject.Factories.Users.user_after_insert_handler/1]

      iex> FactoryMan.get_hook_handler(hooks, :before_build)
      &FactoryMan.fallback_hook_handler/0

      iex> FactoryMan.get_hook_handler(hooks, :after_insert)
      &YourProject.Factories.Users.user_after_insert_handler/1
  """
  def get_hook_handler(hooks, hook), do: hooks[hook] || (&FactoryMan.fallback_hook_handler/1)

  @doc """
  Warn at compile time if child opts contain options that are already defined by the parent with
  the same value.

  This is a FactoryMan internal function — called from macro-generated code. Use the underscore
  prefix convention to signal that it is not part of the public API.
  """
  def _warn_duplicate_options(parent_opts, child_opts, context) do
    if Keyword.get(child_opts, :suppress_duplicate_option_warning) != true do
      child_opts
      |> Keyword.drop(@duplicate_warning_skip_keys)
      |> Enum.each(fn {key, value} ->
        if Keyword.has_key?(parent_opts, key) and Keyword.get(parent_opts, key) == value do
          Logger.warning("""
          FactoryMan: duplicate option in #{context}

          The option `#{inspect(key)}: #{inspect(value)}` is already defined by the parent \
          factory with the same value. This is redundant and can be removed.

          To suppress this warning, add `suppress_duplicate_option_warning: true` to the options.\
          """)
        end
      end)
    end
  end

  @doc """
  Generates a sequence of strings.

  The sequence name is used as the beginning of the string. For example, if you
  do `sequence("joe")`, you will get back `"joe0"`, then `"joe1"`, and so on.

  ## Example

      def user_factory do
        %{
          username: sequence("joe")
        }
      end

  If you want to customize the returned string you can use `sequence/2`.
  """

  @spec sequence(String.t()) :: String.t()
  def sequence(name), do: FactoryMan.Sequence.next(name)

  @doc """
  Generates and returns a unique sequence.

  If a formatter function is passed, it will be called with the current
  position of the sequence. You can also pass a list, and each item in the list
  will be returned in sequence.

  ## Example with a formatter function

      def user_factory do
        %{
          email: sequence(:email, fn n -> "me-\#{n}@foo.com" end)
        }
      end

  ## Example with a list

      def user_factory do
        %{
          name: sequence(:name, ["Joe", "Mike", "Sarah"])
        }
      end
  """

  @spec sequence(any, (integer -> any) | nonempty_list) :: any
  def sequence(name, formatter), do: FactoryMan.Sequence.next(name, formatter)

  @doc """
  Generates and returns a unique sequence with options.

  Currently, the only option is `:start_at` which specifies the number to
  start the sequence at.

  ## Example

      def money_factory do
        %{
          cents: sequence(:cents, fn n -> "\#{n}" end, start_at: 600)
        }
      end
  """

  @spec sequence(any, (integer -> any) | nonempty_list, start_at: non_neg_integer) :: any
  def sequence(name, formatter, opts), do: FactoryMan.Sequence.next(name, formatter, opts)
end
