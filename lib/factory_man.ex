defmodule FactoryMan do
  @moduledoc """
  An Elixir library for generating test data. Define factories with `deffactory`, and FactoryMan
  generates functions for building params, structs, and database records.

  ## Quick Start

  ```elixir
  defmodule MyApp.Factory do
    use FactoryMan, repo: MyApp.Repo

    alias MyApp.Users.User

    deffactory user(params \\\\ %{}), struct: User do
      base_params = %{username: "user-\#{System.os_time()}"}

      Map.merge(base_params, params)
    end
  end
  ```

  ## Generated Functions

  For a factory named `:user` with `struct: User`:

  | Function                            | Returns          | Purpose                              |
  | ----------------------------------- | ---------------- | ------------------------------------ |
  | `build_user_struct/0,1`             | `%User{}`        | Struct in memory (not persisted)     |
  | `build_user_params/0,1`             | `%{}`            | Clean params map derived from struct |
  | `build_user_string_params/0,1`      | `%{"" => ...}`   | Same, with string keys               |
  | `insert_user/0,1,2`                 | `%User{}`        | Inserted into database               |
  | `build_user_struct_list/1,2`        | `[%User{}, ...]` | List of structs                      |
  | `build_user_params_list/1,2`        | `[%{}, ...]`     | List of params maps                  |
  | `build_user_string_params_list/1,2` | `[%{}, ...]`     | List of string-keyed params maps     |
  | `insert_user_list/1,2,3`            | `[%User{}, ...]` | List of inserted records             |

  All functions accept optional params for customization. Insert functions also accept repo
  options. Each item in a list is evaluated independently (unique timestamps, sequences, etc.).

  What gets generated depends on the options:

  | Options                  | Params | Struct | Insert |
  | ------------------------ | ------ | ------ | ------ |
  | `struct: User` (default) | Yes    | Yes    | Yes    |
  | No `struct:` option      | Yes    | No     | No     |
  | `insert?: false`         | Yes    | Yes    | No     |
  | `body: :struct`          | Yes    | Yes    | Yes    |
  | Embedded schema          | Yes    | Yes    | No     |

  Params functions are derived from the built struct, so they exist for every struct factory —
  including `body: :struct` factories, whose body returns a struct directly.

  How the functions relate (list variants omitted — each generated function also has a `*_list`
  counterpart that evaluates every item independently):

  ```mermaid
  flowchart TD
      body["factory body<br/>(returns params map)"]
      struct_fn["build_user_struct/0,1<br/>params hooks → lazy eval → struct!/2 → struct hooks"]
      params_fn["build_user_params/0,1<br/>struct stripped to a clean map"]
      string_params_fn["build_user_string_params/0,1<br/>keys converted to strings"]
      insert_fn["insert_user/0,1,2<br/>insert hooks → Repo.insert!/2"]

      body --> struct_fn
      struct_fn --> params_fn
      params_fn --> string_params_fn
      struct_fn --> insert_fn
  ```

  ## Defining Factories

  The `deffactory` macro works like defining a function — specify a name, a parameter, and a body
  that returns a **plain map**. For struct factories, the map's keys must be fields of the
  struct (it is passed to `struct!/2`):

  ```elixir
  deffactory user(params \\\\ %{}), struct: User do
    base_params = %{username: "user-\#{System.os_time()}"}

    Map.merge(base_params, params)
  end
  ```

  You can name the parameter anything, and use pattern matching:

  ```elixir
  deffactory user_from_config(%{username: username} = params), struct: User do
    base_params = %{username: username}

    Map.merge(base_params, params)
  end
  ```

  ### Struct vs. Non-Struct Factories

  The `struct:` option controls both what functions are generated and how they're named:

  ```elixir
  # Struct factory — generates build_user_params, build_user_struct, insert_user, etc.
  deffactory user(params \\\\ %{}), struct: User do
    base_params = %{username: "user-\#{System.os_time()}"}
    Map.merge(base_params, params)
  end

  # Non-struct factory — generates build_api_payload and build_api_payload_list only
  deffactory api_payload(params \\\\ %{}) do
    %{action: "create", data: params}
  end
  ```

  | Factory type                  | Generated functions                                           |
  | ----------------------------- | ------------------------------------------------------------- |
  | `struct: User` (`:user`)      | `build_user_params`, `build_user_struct`, `insert_user`, etc. |
  | No `struct:` (`:api_payload`) | `build_api_payload`, `build_api_payload_list`                 |

  Non-struct factories use simplified names (`build_*` instead of `build_*_params`) because
  they can return any value — maps, strings, keyword lists, tuples, nil, etc.:

  ```elixir
  deffactory greeting(name \\\\ "world") do
    "Hello, \#{name}!"
  end

  deffactory search_opts(overrides \\\\ []) do
    Keyword.merge([page: 1, per_page: 20], overrides)
  end
  ```

  Lazy evaluation works in keyword lists the same way it does in maps — 0-arity and 1-arity
  functions are resolved at build time. Non-map, non-keyword-list values are passed through
  unchanged.

  **Associations** — call other factories to build related records:

  ```elixir
  deffactory author(params \\\\ %{}), struct: Author do
    base_params = %{
      name: "Test Author",
      user: Map.get_lazy(params, :user, fn -> build_user_struct() end)
    }

    Map.merge(base_params, params)
  end
  ```

  ## Params Functions

  For struct factories, `build_*_params` and `build_*_string_params` build the struct and
  convert it to a clean map suitable for changesets or controller tests. For Ecto schemas, all
  Ecto metadata is stripped; for plain structs, the struct is converted with `Map.from_struct/1`:

  ```elixir
  # Returns %{username: "alice", first_name: nil, ...}
  # (no __struct__, __meta__, autogenerated :id, or NotLoaded associations)
  build_user_params(%{username: "alice"})

  # Same but with string keys: %{"username" => "alice", ...}
  build_user_string_params(%{username: "alice"})
  ```

  `belongs_to` associations are removed from the output; if the association is persisted, the
  foreign key is set instead. Unlike ExMachina, nil values are preserved (a nil field may be
  intentional), and struct values like `DateTime` are left untouched.

  ## Factory Options

  Options cascade: parent module -> child module -> individual factory.

  **Module-level** (set with `use FactoryMan`):

  - `:repo` — Ecto repo for database operations
  - `:extends` — Parent factory module to inherit configuration from
  - `:hooks` — Hooks applied to all factories in the module
  - `:suppress_duplicate_option_warning` — Suppress warnings for redundant options

  **Factory-level** (set with `deffactory`):

  - `:struct` — Ecto schema module (enables struct, params, and insert functions)
  - `:insert?` — Set to `false` to skip insert functions
  - `:body` — What the factory body returns: `:params` (default, a params map) or `:struct`
    (a struct built directly by the body). Params functions are generated either way (derived
    from the struct). Ignored for non-struct factories.
  - `:hooks` — Merged with module-level hooks
  - `:suppress_duplicate_option_warning` — Suppress warnings for redundant options

  ## Hooks

  Transform data at specific stages. Every factory action has both a `before` and `after` hook.

  ### Hook Pipeline

  Each generated function uses a subset of the pipeline. The full flow for `insert_user` is:

  ```text
  build_user_struct:
    before_build_params → [factory body + lazy eval] → after_build_params
    → before_build_struct → struct!() → after_build_struct

  build_user_params (calls build_user_struct internally):
    → strip Ecto metadata (or Map.from_struct/1 for plain structs)

  insert_user (calls build_user_struct internally):
    → before_insert → Repo.insert!() → after_insert
  ```

  For non-struct factories, `build_*` runs `before_build_params`, the factory body with lazy
  evaluation, then `after_build_params`.

  ### Hook Reference

  | Hook                   | Receives     | Returns      | When to Use                                                     |
  | ---------------------- | ------------ | ------------ | --------------------------------------------------------------- |
  | `:before_build_params` | params (map) | params (map) | Transform or inject params before the factory body runs         |
  | `:after_build_params`  | params (map) | params (map) | Modify params after the factory body (e.g. add computed fields) |
  | `:before_build_struct` | params (map) | params (map) | Last chance to modify params before `struct!()` is called       |
  | `:after_build_struct`  | struct       | struct       | Transform the struct after creation (e.g. set virtual fields)   |
  | `:before_insert`       | struct       | struct       | Modify struct just before database insertion                    |
  | `:after_insert`        | struct       | struct       | Post-process after insertion (e.g. reset associations)          |

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
  deffactory user(params \\\\ %{}), struct: User,
    hooks: [after_build_params: &__MODULE__.log_params/1] do
    base_params = %{username: "user-\#{System.os_time()}"}

    Map.merge(base_params, params)
  end

  def log_params(params) do
    IO.inspect(params, label: "factory params")
    params
  end
  ```

  ## Factory Inheritance

  Child factories inherit the parent's repo, hooks, and helper functions via `:extends`:

  ```elixir
  defmodule MyApp.Factory do
    use FactoryMan, repo: MyApp.Repo
    def generate_username, do: "user-\#{System.os_time()}"
  end

  defmodule MyApp.Factory.Accounts do
    use FactoryMan, extends: MyApp.Factory

    deffactory user(params \\\\ %{}), struct: User do
      base_params = %{username: generate_username()}

      Map.merge(base_params, params)
    end
  end
  ```

  Inheritance chains are unlimited — a child factory can itself be extended.

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
    base_params = %{username: sequence("user"), role: "member"}

    Map.merge(base_params, params)
  end

  defvariant admin(params \\\\ %{}), for: :user do
    base_params = %{role: "admin"}

    Map.merge(base_params, params)
  end
  ```

  Calling `build_admin_user_struct()` is equivalent to `build_user_struct(%{role: "admin"})`.
  Calling `build_admin_user_struct(%{role: "superadmin"})` passes `%{role: "superadmin"}` to
  the base factory because the caller's params override the variant defaults.

  Generated functions follow the pattern `{variant}_{base}`:
  `build_admin_user_params/0,1`, `build_admin_user_struct/0,1`, `insert_admin_user/0,1,2`,
  plus list variants.

  ### Custom naming with `:as`

  The `:as` option overrides the combined `{variant}_{base}` name:

  ```elixir
  defvariant moderator(params \\\\ %{}), for: :user, as: :mod do
    base_params = %{role: "moderator"}

    Map.merge(base_params, params)
  end
  ```

  This generates `build_mod_struct/0,1`, `insert_mod/0,1,2`, etc.
  — instead of the default `build_moderator_user_struct`.

  ## Sequences

  Generate unique values across builds:

  ```elixir
  sequence("user")                                          # "user0", "user1", ...
  sequence(:email, fn n -> "user\#{n}@example.com" end)     # custom formatter
  sequence(:role, ["admin", "moderator", "user"])           # cycles through list
  sequence(:order, fn n -> "ORD-\#{n}" end, start_at: 1000) # custom start value
  ```

  Reset in test setup: `FactoryMan.Sequence.reset()`

  ## Lazy Evaluation

  Functions in factory params are evaluated at build time. This works in both maps and keyword
  lists:

  ```elixir
  # In maps
  %{
    created_at: fn -> DateTime.utc_now() end,               # 0-arity: called with no args
    display_name: fn user -> "\#{user.username} (User)" end # 1-arity: receives parent map
  }

  # In keyword lists
  [
    created_at: fn -> DateTime.utc_now() end,
    label: fn kw -> "timeout-\#{kw[:timeout]}" end          # 1-arity: receives parent keyword list
  ]
  ```

  > #### Lazy evaluation ordering {: .warning}
  >
  > 1-arity functions receive the map or keyword list **before** lazy evaluation. Don't reference
  > other lazy fields — they'll still be function references, not resolved values.

  ## Embedded Schemas

  Factories for embedded schemas work like regular struct factories but without database
  insertion:

  ```elixir
  defmodule MyApp.Factories.Settings do
    use FactoryMan, extends: MyApp.Factory

    alias MyApp.Users.Settings

    deffactory settings(params \\\\ %{}), struct: Settings do
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

  ## Direct Struct Factories (`body: :struct`)

  For complex factories that need full control over struct construction, set `body: :struct`.
  The factory body returns a struct directly instead of a params map:

  ```elixir
  deffactory invoice(params \\\\ %{}), struct: Invoice, body: :struct do
    customer =
      case params[:customer] do
        %Customer{} = customer -> customer
        _ -> MyApp.Factory.Accounts.insert_customer()
      end

    %Invoice{
      customer: customer,
      total: Map.get(params, :total, Enum.random(100..10_000))
    }
  end
  ```

  This generates the full function family, including `build_invoice_params` (derived from the
  built struct). The `after_build_struct`, `before_insert`, and `after_insert` hooks still run.
  The `before_build_params`, `after_build_params`, and `before_build_struct` hooks are skipped
  since there is no params-to-struct conversion stage.

  `body: :struct` can also be set at the module level with `use FactoryMan, body: :struct`,
  then overridden per-factory with `body: :params` if needed. Non-struct factories in the
  same module are unaffected — their `build_*` functions are always generated.

  ## Cookbook

  ### Building associations

  Let callers pass a prebuilt association, and build one only when they don't:

  ```elixir
  deffactory post(params \\\\ %{}), struct: Post do
    base_params = %{
      title: sequence("post"),
      author: Map.get_lazy(params, :author, fn -> build_author_struct() end)
    }

    Map.merge(base_params, params)
  end
  ```

  `Map.get_lazy/3` only builds the default author when the caller didn't provide one — so
  `build_post_struct(%{author: my_author})` reuses the given struct, and `build_post_struct()`
  builds a fresh one.

  When the schema only needs a foreign key (and the record must exist), insert the association
  and use its ID:

  ```elixir
  deffactory comment(params \\\\ %{}), struct: Comment do
    base_params = %{
      body: "Nice post!",
      post_id: Map.get_lazy(params, :post_id, fn -> insert_post().id end)
    }

    Map.merge(base_params, params)
  end
  ```

  ## Duplicate Option Warnings

  If a child factory module specifies an option that is already defined by its parent with the
  same value, FactoryMan will emit a compile-time warning. This helps catch redundant options
  that were likely copy-pasted from the parent.

  To suppress the warning for a specific module or factory, add
  `suppress_duplicate_option_warning: true` to the options.

  ## Debugging

  Every factory module gets a `__factory_man__/1,2` reflection function showing resolved options:

  ```elixir
  iex> MyApp.Factory.__factory_man__(:opts)
  [repo: MyApp.Repo]

  iex> MyApp.Factories.Users.__factory_man__(:opts, :user)
  [repo: MyApp.Repo, struct: User]
  ```
  """

  # Keys that should not trigger duplicate option warnings
  @duplicate_warning_skip_keys [:extends, :suppress_duplicate_option_warning]

  defmacro __using__(opts \\ []) do
    parent_imports =
      for parent <- extends_chain(opts, __CALLER__) do
        quote do
          import unquote(parent), except: [__factory_man__: 1, __factory_man__: 2]
        end
      end

    quote do
      unquote_splicing(parent_imports)

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
              "module #{inspect(__MODULE__)}",
              __ENV__
            )

            FactoryMan._merge_opts(parent_opts, unquote(opts))
        end

      # Put factory module options into a module attribute that can be read by the child factories
      Module.register_attribute(__MODULE__, :parent_factory_opts, persist: true)

      Module.put_attribute(
        __MODULE__,
        :parent_factory_opts,
        parent_factory_opts |> Keyword.delete(:suppress_duplicate_option_warning)
      )

      @before_compile FactoryMan
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    # `unquote: false` defers the inner unquote fragments so they run in the using module's
    # compile context, where the comprehension variables are bound.
    quote unquote: false do
      @doc """
      FactoryMan reflection.

      - `__factory_man__(:opts)` — the resolved options for this factory module
      - `__factory_man__(:opts, factory_name)` — the merged options for one factory or variant
      """
      def __factory_man__(:opts), do: @parent_factory_opts

      for {factory_man_name, factory_man_opts} <- @factory_man_registry do
        def __factory_man__(:opts, unquote(factory_man_name)), do: unquote(factory_man_opts)
      end
    end
  end

  # Resolves the full ancestor chain ([parent, grandparent, ...]) for `:extends` at compile time.
  # Each ancestor is imported so its helper functions are callable unqualified in the child,
  # matching option inheritance. Imports are not transitive, so the whole chain is needed.
  defp extends_chain(opts, env) when is_list(opts) do
    case Keyword.get(opts, :extends) do
      nil -> []
      parent_ast -> parent_ast |> Macro.expand(env) |> ancestor_chain()
    end
  end

  defp extends_chain(_opts, _env), do: []

  defp ancestor_chain(module) do
    with {:module, _} <- Code.ensure_compiled(module),
         parent when parent != nil <- module.__info__(:attributes)[:parent_factory_opts][:extends] do
      [module | ancestor_chain(parent)]
    else
      _ -> [module]
    end
  end

  @doc """
  Defines a factory that generates test data.

  The `deffactory` macro creates a set of functions for building test data. It works like
  defining a function, where you specify the factory name and a parameter (typically `params`).

  ## Options

  - `:struct` - The struct or Ecto schema module to build. When provided, generates struct,
    params, and insert functions.
  - `:insert?` - Set to `false` to skip generating insert functions (default: `true` when
    repo is configured and struct is insertable)
  - `:body` - What the factory body returns: `:params` (default, a params map) or `:struct`
    (a struct built directly by the body). Params functions are generated either way (derived
    from the struct). Ignored for non-struct factories.
  - `:hooks` - A keyword list of hook functions to apply at different stages (see Hooks section)
  - `:suppress_duplicate_option_warning` - Set to `true` to suppress warnings when this
    factory specifies an option already defined by the module with the same value

  ## Generated Functions

  For a factory named `user` with `struct: User`, the following functions are generated:

  - `build_user_struct/0,1` - Returns an unsaved struct
  - `build_user_params/0,1` - Clean params map derived from the built struct
  - `build_user_string_params/0,1` - Same, with string keys
  - `insert_user/0,1,2` - Inserts into the database (when repo is configured)
  - `build_user_struct_list/1,2` - Builds multiple structs
  - `build_user_params_list/1,2` - Builds multiple params maps
  - `build_user_string_params_list/1,2` - Builds multiple string-keyed params maps
  - `insert_user_list/1,2,3` - Inserts multiple items (when repo is configured)

  For a factory named `greeting` without `struct:`, simplified names are used:

  - `build_greeting/1` - Returns the factory's value
  - `build_greeting_list/2` - Builds multiple items

  ## Examples

      deffactory user(params \\\\ %{}), struct: User do
        base_params = %{
          username: sequence("user"),
          email: sequence(:email, fn n -> "user\#{n}@example.com" end)
        }

        Map.merge(base_params, params)
      end

      iex> MyApp.Factory.build_user_params(%{username: "alice"})
      %{username: "alice", email: "user0@example.com", role: nil, ...}

      iex> MyApp.Factory.insert_user(%{role: "admin"})
      %User{id: 1, username: "user1", email: "user1@example.com", role: "admin"}

  """

  defmacro deffactory(factory_head, opts \\ [], do: block) do
    # Recursively extract factory name and argument information from AST
    extraction = extract_factory_args(factory_head)

    factory_name = extraction.name
    head_ast = extraction.head_ast
    user_var = extraction.user_var
    arg_ast_no_default = extraction.arg_no_default
    has_pattern_match = extraction.has_pattern_match
    has_default = extraction.has_default
    plain_var_ast = extraction.plain_var

    quote bind_quoted: [
            factory_name: factory_name,
            head_ast: Macro.escape(head_ast, unquote: true),
            user_var: Macro.escape(user_var, unquote: true),
            arg_ast_no_default: Macro.escape(arg_ast_no_default, unquote: true),
            has_pattern_match: has_pattern_match,
            has_default: has_default,
            plain_var_ast: Macro.escape(plain_var_ast, unquote: true),
            opts: opts,
            block: Macro.escape(block, unquote: true)
          ] do
      parent_factory_opts = Module.get_attribute(__MODULE__, :parent_factory_opts)

      FactoryMan._warn_duplicate_options(
        parent_factory_opts,
        opts,
        "factory :#{factory_name} in #{inspect(__MODULE__)}",
        __ENV__
      )

      merged_opts = FactoryMan._merge_opts(parent_factory_opts, opts)

      if Keyword.has_key?(merged_opts, :build_struct?) do
        raise ArgumentError,
              "the :build_struct? option has been removed. Params functions are now derived " <>
                "from the built struct, so struct factories always generate struct builders. " <>
                "If you don't want struct functions, omit the :struct option."
      end

      if Keyword.has_key?(merged_opts, :build_params?) do
        raise ArgumentError,
              "the :build_params? option has been renamed to :body. Use `body: :struct` to have " <>
                "the factory body return a struct directly (was build_params?: false), or remove " <>
                "the option for the default params-map body (was build_params?: true)."
      end

      body = Keyword.get(merged_opts, :body, :params)

      if body not in [:params, :struct] do
        raise ArgumentError,
              "invalid :body option: #{inspect(body)}. Expected :params (default) or :struct."
      end

      # Extract hooks - used many times throughout
      hooks = Keyword.get(merged_opts, :hooks, [])

      projections = %{
        head_ast: head_ast,
        plain_var: plain_var_ast,
        user_var: user_var,
        has_pattern_match: has_pattern_match,
        has_default: has_default
      }

      # Generate raw builder functions for non-struct factories only.
      # Non-struct factories use `build_*` / `build_*_list` (no suffix) and can return any value.
      # Struct factories get their `build_*_params` functions derived from the built struct below.
      if is_nil(merged_opts[:struct]) do
        build_fn = :"build_#{factory_name}"

        # Head declaration (simple variable with default if present)
        def unquote({build_fn, [], [head_ast]})

        # Implementation (with pattern matching if needed, no default)
        def unquote({build_fn, [], [arg_ast_no_default]}) do
          unquote(user_var) =
            FactoryMan.get_hook_handler(unquote(hooks), :before_build_params).(unquote(user_var))

          unquote(block)
          |> FactoryMan.evaluate_lazy_attributes()
          |> then(&FactoryMan.get_hook_handler(unquote(hooks), :after_build_params).(&1))
        end

        Code.eval_quoted(
          FactoryMan.Codegen.value_list_fns(build_fn, :"#{build_fn}_list", projections),
          [],
          __ENV__
        )
      end

      if merged_opts[:struct] != nil do
        build_struct_fn = :"build_#{factory_name}_struct"

        # Head declaration (simple variable with default if present)
        def unquote({build_struct_fn, [], [head_ast]})

        if body == :params do
          # Standard: the body returns a params map that is run through the params-stage hooks
          # and lazy evaluation, then converted with struct!/2.
          def unquote({build_struct_fn, [], [arg_ast_no_default]}) do
            unquote(user_var) =
              FactoryMan.get_hook_handler(unquote(hooks), :before_build_params).(
                unquote(user_var)
              )

            unquote(block)
            |> FactoryMan.evaluate_lazy_attributes()
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :after_build_params).(&1))
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :before_build_struct).(&1))
            |> then(&struct!(unquote(merged_opts[:struct]), &1))
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :after_build_struct).(&1))
          end
        else
          # body: :struct — the body returns the struct directly.
          def unquote({build_struct_fn, [], [arg_ast_no_default]}) do
            unquote(block)
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :after_build_struct).(&1))
          end
        end

        Code.eval_quoted(
          FactoryMan.Codegen.map_list_fns(
            build_struct_fn,
            :"#{build_struct_fn}_list",
            projections
          ),
          [],
          __ENV__
        )

        struct_module = merged_opts[:struct]
        repo = merged_opts[:repo]

        # Generate build_*_params and build_*_string_params, derived from the built struct
        Code.eval_quoted(
          FactoryMan.Codegen.params_fns(
            factory_name,
            projections,
            FactoryMan.Codegen.ecto_schema?(struct_module)
          ),
          [],
          __ENV__
        )

        if FactoryMan.Codegen.insertable_ecto_schema?(struct_module, repo) and
             merged_opts[:insert?] != false do
          insert_fn = :"insert_#{factory_name}"

          Code.eval_quoted(
            FactoryMan.Codegen.insert_convenience_fns(insert_fn, projections),
            [],
            __ENV__
          )

          # Implementation - uses plain_var_ast since pattern match variables
          # are only needed in the params builder body
          def unquote(insert_fn)(unquote(plain_var_ast), repo_insert_opts)
              when is_list(repo_insert_opts) do
            unquote(user_var)
            |> unquote(:"build_#{factory_name}_struct")()
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :before_insert).(&1))
            |> unquote(repo).insert!(repo_insert_opts)
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :after_insert).(&1))
          end

          Code.eval_quoted(
            FactoryMan.Codegen.insert_list_fns(insert_fn, :"#{insert_fn}_list", projections),
            [],
            __ENV__
          )
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
        base_params = %{username: sequence("user"), role: "member"}

        Map.merge(base_params, params)
      end

      defvariant admin(params \\\\ %{}), for: :user do
        base_params = %{role: "admin"}

        Map.merge(base_params, params)
      end

      # Generated: build_admin_user_struct/0,1, insert_admin_user/0,1,2, etc.
      # Calling build_admin_user_struct() is equivalent to:
      #   build_user_struct(%{role: "admin"})

  ## Options

  - `:for` - (atom, required) The name of the base factory to wrap (e.g. `:user`)

  - `:as` - Instead of the default `<variant>_<base>` structure used when generating factory
  functions, (e.g. `build_admin_user_struct`), you may specify a custom name to use when
  generating the factory functions (e.g. `as: :admin` -> `build_admin_struct`)

  Variants are registered under their full name, so a variant can itself serve as the base of
  another variant (e.g. `defvariant senior(params \\\\ %{}), for: :admin_user`).
  """

  defmacro defvariant(variant_head, opts, do: block) do
    extraction = extract_factory_args(variant_head)

    variant_name = extraction.name
    head_ast = extraction.head_ast
    user_var = extraction.user_var
    arg_ast_no_default = extraction.arg_no_default
    has_pattern_match = extraction.has_pattern_match
    has_default = extraction.has_default
    plain_var_ast = extraction.plain_var

    base_factory_name = opts[:for] || raise ArgumentError, "defvariant requires the :for option"
    as_name = opts[:as]

    quote bind_quoted: [
            variant_name: variant_name,
            base_factory_name: base_factory_name,
            as_name: as_name,
            head_ast: Macro.escape(head_ast, unquote: true),
            user_var: Macro.escape(user_var, unquote: true),
            arg_ast_no_default: Macro.escape(arg_ast_no_default, unquote: true),
            has_pattern_match: has_pattern_match,
            has_default: has_default,
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

      projections = %{
        head_ast: head_ast,
        plain_var: plain_var_ast,
        user_var: user_var,
        has_pattern_match: has_pattern_match,
        has_default: has_default
      }

      # Generate raw builder variant (non-struct base factories only)
      if is_nil(base_opts[:struct]) do
        build_fn = :"build_#{full_name}"
        base_build_fn = :"build_#{base_factory_name}"

        def unquote({build_fn, [], [head_ast]})

        def unquote({build_fn, [], [arg_ast_no_default]}) do
          unquote(block)
          |> unquote(base_build_fn)()
        end

        Code.eval_quoted(
          FactoryMan.Codegen.value_list_fns(build_fn, :"#{build_fn}_list", projections),
          [],
          __ENV__
        )
      end

      # Generate struct builder variant (if base factory has struct)
      if base_opts[:struct] != nil do
        build_struct_fn = :"build_#{full_name}_struct"

        def unquote({build_struct_fn, [], [head_ast]})

        def unquote({build_struct_fn, [], [arg_ast_no_default]}) do
          unquote(block)
          |> unquote(:"build_#{base_factory_name}_struct")()
        end

        Code.eval_quoted(
          FactoryMan.Codegen.map_list_fns(
            build_struct_fn,
            :"#{build_struct_fn}_list",
            projections
          ),
          [],
          __ENV__
        )

        struct_module = base_opts[:struct]
        repo = base_opts[:repo]

        # Generate build_*_params and build_*_string_params, derived from the variant's struct
        Code.eval_quoted(
          FactoryMan.Codegen.params_fns(
            full_name,
            projections,
            FactoryMan.Codegen.ecto_schema?(struct_module)
          ),
          [],
          __ENV__
        )

        # Generate insert variant -- delegates to base factory's insert
        # (reuses base factory's hooks, repo config, and insert pipeline)
        if FactoryMan.Codegen.insertable_ecto_schema?(struct_module, repo) and
             base_opts[:insert?] != false do
          insert_fn = :"insert_#{full_name}"

          Code.eval_quoted(
            FactoryMan.Codegen.insert_convenience_fns(insert_fn, projections),
            [],
            __ENV__
          )

          # Transform params via variant body, then delegate to base insert
          def unquote(insert_fn)(unquote(arg_ast_no_default), repo_insert_opts)
              when is_list(repo_insert_opts) do
            unquote(block)
            |> unquote(:"insert_#{base_factory_name}")(repo_insert_opts)
          end

          Code.eval_quoted(
            FactoryMan.Codegen.insert_list_fns(insert_fn, :"#{insert_fn}_list", projections),
            [],
            __ENV__
          )
        end
      end

      # Register the variant under its full name so it can itself be used as a defvariant base.
      # The base factory's opts describe the variant's generated functions accurately, since
      # variants delegate to the base pipeline.
      @factory_man_registry {full_name, base_opts}
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
      head_ast: components.head_ast,
      user_var: components.user_var,
      arg_no_default: components.arg_no_default,
      has_pattern_match: components.has_pattern_match,
      has_default: components.has_default,
      plain_var: components.plain_var
    }
  end

  # Catch-all for invalid argument counts
  defp process_arg(args, _name) when is_list(args) do
    raise ArgumentError, """
    Invalid factory definition: expected exactly one argument, got #{length(args)}

    FactoryMan factories must have exactly one parameter (typically `params`).

    Valid examples:
      deffactory user(params \\\\ %{}), struct: User do ... end
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
      has_default: false,
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
        has_default: true,
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
        has_default: true,
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
      - params \\\\ %{}
      - %{key: value} = params
      - %{key: value} = params \\\\ %{key: default}

    If you need a different pattern, please open an issue.
    """
  end

  # Extract variable name from a variable AST node
  defp extract_var_name({var_name, _, _}) when is_atom(var_name), do: var_name

  @doc """
  Evaluate lazy attributes in a map, struct, or keyword list.

  Functions with 0 arity are called with no arguments.
  Functions with 1 arity receive the parent factory (map, struct, or keyword list) as their
  argument.

  Non-map, non-keyword-list values are passed through unchanged.

  ## Examples

      iex> FactoryMan.evaluate_lazy_attributes(
      ...> %{name: "test", timestamp: fn -> System.os_time() end}
      ...> )
      %{name: "test", timestamp: 12345}

      iex> FactoryMan.evaluate_lazy_attributes(
      ...>   %{first: "John", last: fn attrs -> attrs.first <> " Smith" end}
      ...> )
      %{first: "John", last: "John Smith"}

      iex> FactoryMan.evaluate_lazy_attributes(
      ...>   [timeout: 5000, created_at: fn -> DateTime.utc_now() end]
      ...> )
      [timeout: 5000, created_at: ~U[2026-01-01 00:00:00Z]]

      iex> FactoryMan.evaluate_lazy_attributes("plain string")
      "plain string"
  """
  @spec evaluate_lazy_attributes(any) :: any
  def evaluate_lazy_attributes(%{__struct__: record} = factory) do
    struct!(record, factory |> Map.from_struct() |> do_evaluate_lazy_attributes(factory))
  end

  def evaluate_lazy_attributes(attrs) when is_map(attrs) do
    do_evaluate_lazy_attributes(attrs, attrs)
  end

  def evaluate_lazy_attributes(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      resolve_lazy_pairs(attrs, attrs)
    else
      attrs
    end
  end

  def evaluate_lazy_attributes(value), do: value

  defp do_evaluate_lazy_attributes(attrs, parent_factory) do
    resolve_lazy_pairs(attrs, parent_factory) |> Enum.into(%{})
  end

  defp resolve_lazy_pairs(pairs, parent) do
    Enum.map(pairs, fn
      {k, v} when is_function(v, 1) -> {k, v.(parent)}
      {k, v} when is_function(v) -> {k, v.()}
      {_, _} = tuple -> tuple
    end)
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
  Get the configured handler for a `hook`, or fall back to `&FactoryMan.fallback_hook_handler/1`.

  ## Examples

      iex> hooks = [after_insert: &YourProject.Factories.Users.user_after_insert_handler/1]

      iex> FactoryMan.get_hook_handler(hooks, :before_build)
      &FactoryMan.fallback_hook_handler/1

      iex> FactoryMan.get_hook_handler(hooks, :after_insert)
      &YourProject.Factories.Users.user_after_insert_handler/1
  """
  def get_hook_handler(hooks, hook), do: hooks[hook] || (&FactoryMan.fallback_hook_handler/1)

  @doc """
  Merge child factory options into parent options.

  Most options are overridden per-key, but `:hooks` are merged per hook key so that a child
  setting one hook does not discard the parent's other hooks.

  This is a FactoryMan internal function — called from macro-generated code. Use the underscore
  prefix convention to signal that it is not part of the public API.
  """
  def _merge_opts(parent_opts, child_opts) do
    merged_hooks =
      Keyword.merge(Keyword.get(parent_opts, :hooks, []), Keyword.get(child_opts, :hooks, []))

    merged_opts = Keyword.merge(parent_opts, child_opts)

    if merged_hooks == [] do
      merged_opts
    else
      Keyword.put(merged_opts, :hooks, merged_hooks)
    end
  end

  @doc """
  Warn at compile time if child opts contain options that are already defined by the parent with
  the same value.

  This is a FactoryMan internal function — called from macro-generated code. Use the underscore
  prefix convention to signal that it is not part of the public API.
  """
  def _warn_duplicate_options(parent_opts, child_opts, context, env) do
    if Keyword.get(child_opts, :suppress_duplicate_option_warning) != true do
      child_opts
      |> Keyword.drop(@duplicate_warning_skip_keys)
      |> Enum.each(fn {key, value} ->
        if Keyword.has_key?(parent_opts, key) and Keyword.get(parent_opts, key) == value do
          IO.warn(
            """
            FactoryMan: duplicate option in #{context}

            The option `#{inspect(key)}: #{inspect(value)}` is already defined by the parent \
            factory with the same value. This is redundant and can be removed.

            To suppress this warning, add `suppress_duplicate_option_warning: true` to the options.\
            """,
            env
          )
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
