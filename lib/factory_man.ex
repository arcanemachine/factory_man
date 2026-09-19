defmodule FactoryMan do
  @moduledoc """
  An Elixir library for generating test data. Define factories with `deffactory`, and FactoryMan
  generates functions for building params and structs, and inserting database records.

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

  For a factory named `:user` with `struct: User` and a plain params argument that defaults to an empty
  map, the following functions are available. Insert functions require a configured repo, a table-backed
  Ecto schema, and `insert?` not set to `false`.

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
  | `insert_user_struct/1,2`            | `%User{}`        | Inserts an already-built struct      |

  Builders and `insert_user` accept factory params. `insert_user_struct` takes an existing `%User{}`
  instead. Insert functions also accept repo options. Each list item is built independently.

  Zero-arity builders and inserts require a default argument in the factory head. For struct
  factories, count-only list functions pass `%{}` and are omitted when the head pattern-matches its
  argument. Non-struct count-only list functions require a default argument and use that default.

  What gets generated depends on the factory configuration:

  | Factory configuration    | Value builders | Params builders | Struct builders | Inserts            |
  | ------------------------ | -------------- | --------------- | --------------- | ------------------ |
  | No `struct:` option      | Yes            | No              | No              | No                 |
  | Plain struct             | No             | Yes             | Yes             | No                 |
  | Table-backed Ecto schema | No             | Yes             | Yes             | Yes, when enabled  |
  | Embedded schema          | No             | Yes             | Yes             | No                 |

  Value builders use `build_<name>` and `build_<name>_list`. Params builders include atom-keyed and
  string-keyed functions. Inserts require a configured repo and `insert?` not set to `false`. Setting
  `body: :struct` changes how the struct is built, not which function families are generated.

  The diagram shows the build pipeline with `body: :params`. Configured `:associations` are
  normalized after `before_build_params` and before the factory body. Each function shown has a
  list counterpart that builds every item independently. `insert_user_struct`, not shown, starts at the
  insert pipeline and has no list counterpart:

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

  The `deffactory` macro defines a named factory with one argument and a body. With `struct:` and
  the default `body: :params`, return a plain map containing only fields of that struct. With
  `body: :struct`, return the struct directly. Without `struct:`, the body can return any value.

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
  # Struct factory: generates build_user_params, build_user_struct, insert_user, etc.
  deffactory user(params \\\\ %{}), struct: User do
    base_params = %{username: "user-\#{System.os_time()}"}
    Map.merge(base_params, params)
  end

  # Non-struct factory: generates build_api_payload and build_api_payload_list only
  deffactory api_payload(params \\\\ %{}) do
    %{action: "create", data: params}
  end
  ```

  | Factory type                  | Generated functions                                           |
  | ----------------------------- | ------------------------------------------------------------- |
  | `struct: User` (`:user`)      | `build_user_params`, `build_user_struct`, `insert_user`, etc. |
  | No `struct:` (`:api_payload`) | `build_api_payload`, `build_api_payload_list`                 |

  Non-struct factories use simplified names (`build_*` instead of `build_*_params`) because
  they can return any value: maps, strings, keyword lists, tuples, nil, etc.:

  ```elixir
  deffactory greeting(name \\\\ "world") do
    "Hello, \#{name}!"
  end

  deffactory search_opts(overrides \\\\ []) do
    Keyword.merge([page: 1, per_page: 20], overrides)
  end
  ```

  Lazy evaluation works in keyword lists the same way it does in maps. 0-arity and 1-arity
  functions are resolved at build time. Non-map, non-keyword-list values are passed through
  unchanged.

  **Associations**: configure nested params with the `:associations` option (see the
  [Cookbook](cookbook.html)):

  ```elixir
  deffactory author(params \\\\ %{}), struct: Author, associations: [user: :user] do
    base_params = %{
      name: "Test Author",
      user: build_user_struct()
    }

    Map.merge(base_params, params)
  end
  ```

  The association key is resolved only when supplied by the caller. A nested params map becomes
  the associated struct, while an existing struct is reused. Missing keys continue to use the
  factory's ordinary `base_params` defaults.

  Association targets are factory names, not schema names:

  - `associations: [user: :user]` references a factory registered in the current module.
  - `associations: [user: {MyApp.AccountFactory, :user}]` references another factory module.
  - Registered variants can be targets using their full registered names.

  Ecto supplies the related schema and cardinality. Factory references are checked at runtime,
  including when the caller omits an association key. A same-module target may therefore be
  declared later in the module. The atom shorthand does not search imported or ancestor modules;
  use an explicit module tuple for those factories.

  | Caller value | Singular association | Plural association |
  | --- | --- | --- |
  | Key absent | Leave absent; body defaults apply | Leave absent; body defaults apply |
  | Params map | Build through the configured factory | Raise |
  | Correct struct | Reuse unchanged | Raise; supply a list |
  | `nil` | Preserve nil | Raise; use `[]` |
  | List of maps/structs | Raise | Resolve each member in order |

  Wrong struct types, invalid list members, and incorrectly typed builder results raise. Only
  configured keys are normalized. Direct Ecto associations are supported; embeds and through
  associations are not. Normalization calls struct builders, not insert functions.

  Factory defaults remain ordinary Elixir expressions: eager default builders run even when
  overridden. Use existing lazy attributes when a default should only be built if retained.
  FactoryMan does not automatically build omitted relationships or prevent recursion caused by
  mutually recursive default builders.

  **Imperative resolution**: `assoc/3,4` and `assoc_list/3,4` resolve one association from a
  params map, for associations that must be inserted or whose params depend on an association
  resolved earlier in the same body. `resolve_assoc/2,3` and `resolve_assoc_list/2,3` are their
  value forms, for helpers that already hold the value. An explicit `nil` is preserved by all of
  them, as it is by `:associations`.

  These helpers return the resolved value and do not modify the params map. A factory that ends
  in `Map.merge(base_params, params)` must put the resolved value back first, or the merge
  restores the caller's raw input over it. See the [Cookbook](cookbook.html) for the ways to do
  that, and for the full input table.

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

  `belongs_to` associations are removed from the output. If the association is persisted, its
  foreign key is set instead. Ordinary fields retain nil values, but nil embeds are omitted. Struct
  values such as `DateTime` are left untouched.

  ## Factory Options

  Options cascade: parent module -> child module -> individual factory.

  **Module-level** (set with `use FactoryMan`):

  - `:repo` - Ecto repo for database operations
  - `:extends` - Parent factory module to inherit configuration from
  - `:hooks` - Hooks applied to all factories in the module

  **Factory-level** (set with `deffactory`):

  - `:struct` - Ecto schema module (enables struct, params, and insert functions)
  - `:insert?` - Set to `false` to skip insert functions
  - `:body` - What the factory body returns: `:params` (default, a params map) or `:struct`
    (a struct built directly by the body). Params functions are generated either way (derived
    from the struct), and lazy values are resolved either way. Ignored for non-struct factories.
  - `:hooks` - Merged with module-level hooks
  - `:associations` - Keyword list mapping Ecto association keys to FactoryMan factories. Use an
    atom for a same-module factory or `{FactoryModule, :factory}` across modules. Ecto supplies
    the associated schema and cardinality; caller-provided nested params are normalized before the
    factory body runs. Factory-level only.
  - `:strict` - Reject unknown param keys at the factory boundary (see Strict Params below)

  `:body` and `:strict` cascade from the module level and are ignored by non-struct factories.
  `:associations` is factory-level only, because association keys belong to a single schema, and
  it requires an Ecto-backed struct factory.

  ## Strict Params

  Factories can silently ignore misspelled param keys: merge-style bodies surface the typo late
  (in `struct!/2`, with an unhelpful message), and `body: :struct` bodies, which read params
  selectively, never surface it at all. Opt in to `strict: true` to reject unknown keys up
  front:

  ```elixir
  deffactory user(params \\\\ %{}), struct: User, strict: true do
    base_params = %{username: FactoryMan.sequence("user")}

    Map.merge(base_params, params)
  end

  build_user_struct(%{usernme: "typo"})
  # ** (ArgumentError) unknown params [:usernme] for strict factory :user ...
  ```

  The check runs when building starts, before hooks and the factory body, against the keys of
  the `:struct` option's struct (which includes virtual fields and association keys). All derived
  functions (params builders, inserts, lists, and variants of the factory) are covered.

  When a factory intentionally accepts keys that are not struct fields (e.g. an input used only
  to derive other fields), allow them explicitly:

  ```elixir
  deffactory invoice(params \\\\ %{}), struct: Invoice, strict: [allow: [:line_item_count]],
    body: :struct do
    %Invoice{total: Map.get(params, :line_item_count, 1) * 100}
  end
  ```

  Like other options, `:strict` can be set module-wide with `use FactoryMan, strict: true` and
  overridden per-factory (e.g. `strict: false`). Non-struct factories have no reference field
  set, so the option is ignored for them.

  ## Hooks

  Transform data at specific stages. Every factory action has both a `before` and `after` hook.

  ### Hook Pipeline

  Each generated function uses a subset of the pipeline. The full flow for `insert_user` is:

  ```text
  build_user_struct:
    params validation → before_build_params → configured association normalization
    → [factory body + lazy eval] → after_build_params
    → before_build_struct → struct!() → after_build_struct

  build_user_params (calls build_user_struct internally):
    → strip Ecto metadata (or Map.from_struct/1 for plain structs)

  insert_user (calls build_user_struct internally):
    → before_insert → Repo.insert!() → after_insert
  ```

  With `body: :struct`, configured associations are normalized after params validation and before
  the body, and the struct the body returns is lazily evaluated. Params-stage hooks remain
  skipped. Variants preprocess input before delegating to the
  base builder, which performs normalization. `insert_*_struct` receives an already-built struct
  and does not run association normalization.

  For non-struct factories, `build_*` runs `before_build_params`, the factory body with lazy
  evaluation, then `after_build_params`.

  `insert_user_struct/1,2` runs the same `before_insert` → insert → `after_insert` pipeline on
  an already-built struct. Use it after modifying a built struct, so records are shaped
  consistently no matter how they were constructed. A raw `Repo.insert!/2` would skip the
  insert hooks.

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

  1. **Parent module** - `use FactoryMan, hooks: [...]`
  2. **Child module** - `use FactoryMan, extends: Parent, hooks: [...]`
  3. **Individual factory** - `deffactory name(params), hooks: [...]`

  ### Examples

  **Reset associations after insert:**

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

  Inheritance chains are unlimited; a child factory can itself be extended.

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
    base_params = %{username: FactoryMan.sequence("user"), role: "member"}

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
  instead of the default `build_moderator_user_struct`.

  ## Sequences

  Generate sequential values or cycle through a list:

  ```elixir
  FactoryMan.sequence("user")                                          # "user0", "user1", ...
  FactoryMan.sequence(:email, fn n -> "user\#{n}@example.com" end)     # custom formatter
  FactoryMan.sequence(:role, ["admin", "moderator", "user"])           # cycles through list
  FactoryMan.sequence(:order, fn n -> "ORD-\#{n}" end, start_at: 1000) # custom start value
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
  > Lazy values are resolved in two passes: the 0-arity functions first, then the 1-arity ones.
  > A 1-arity function therefore sees plain values and resolved 0-arity values, but not another
  > 1-arity field, which is still a function reference when it runs.

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

  Embedded schemas generate `build_*_struct`, `build_*_params`, and `build_*_string_params`, plus
  their matching `*_list` functions. They do not generate insert functions.

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
  built struct). Lazy values in the returned struct are resolved as they are in a params body.
  The `after_build_struct`, `before_insert`, and `after_insert` hooks still run. The
  `before_build_params`, `after_build_params`, and `before_build_struct` hooks are skipped
  since there is no params-to-struct conversion stage.

  `body: :struct` can also be set at the module level with `use FactoryMan, body: :struct`,
  then overridden per-factory with `body: :params` if needed. Non-struct factories in the
  same module are unaffected; their `build_*` functions are always generated.

  ## Cookbook

  A practical progression from a first factory through realistic defaults, variants,
  associations, suite organization, hooks, strict params, and advanced presets lives in the
  [Cookbook](cookbook.html) guide.

  ## Reflection and Debugging

  Every factory module gets a `__factory_man__/1,2` reflection function:

  ```elixir
  iex> MyApp.Factory.__factory_man__(:opts)
  [repo: MyApp.Repo]

  iex> MyApp.Factories.Users.__factory_man__(:opts, :user)
  [repo: MyApp.Repo, struct: User]

  iex> MyApp.Factories.Users.__factory_man__(:factories)
  [:user, :admin_user]
  ```

  `:factories` lists every factory and variant registered in the module (variants under their
  full name), which enables runtime dispatch without string-building function names:

  ```elixir
  def build_any(factory_module, factory_name, params) do
    if factory_name not in factory_module.__factory_man__(:factories) do
      raise ArgumentError, "unknown factory \#{inspect(factory_name)}"
    end

    apply(factory_module, :"build_\#{factory_name}_struct", [params])
  end
  ```
  """

  defmacro __using__(opts \\ []) do
    parent_imports =
      for parent <- extends_chain(opts, __CALLER__) do
        quote do
          import unquote(parent), except: [__factory_man__: 1, __factory_man__: 2]
        end
      end

    quote do
      unquote_splicing(parent_imports)

      if Keyword.has_key?(unquote(opts), :associations) do
        raise ArgumentError,
              "invalid module option :associations in #{inspect(__MODULE__)}. Association keys " <>
                "belong to a single schema, so :associations is set per factory, not per module."
      end

      # Only the definition macros are imported, since they read as DSL keywords. Helper functions
      # (assoc/3,4, assoc_list/3,4, sequence/1,2,3, ...) are deliberately not imported: they are called with the
      # FactoryMan. prefix so their origin is explicit and generic names cannot collide (e.g.
      # with Ecto.assoc/2).
      import unquote(__MODULE__),
        only: [
          deffactory: 2,
          deffactory: 3,
          defvariant: 3
        ]

      Module.register_attribute(__MODULE__, :factory_man_registry, accumulate: true)

      parent_factory_opts =
        case unquote(opts)[:extends] do
          nil ->
            # Use opts from current factory only
            unquote(opts)

          extends ->
            # Extend base factory opts
            parent_opts = extends.__info__(:attributes)[:parent_factory_opts] || []

            FactoryMan._merge_opts(parent_opts, unquote(opts))
        end

      # Put factory module options into a module attribute that can be read by the child factories
      Module.register_attribute(__MODULE__, :parent_factory_opts, persist: true)

      Module.put_attribute(__MODULE__, :parent_factory_opts, parent_factory_opts)

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

      - `__factory_man__(:opts)` - the resolved options for this factory module
      - `__factory_man__(:opts, factory_name)` - the merged options for one factory or variant
      - `__factory_man__(:factories)` - all factory and variant names registered in this
        module (variants under their full name), in definition order
      """
      def __factory_man__(:opts), do: @parent_factory_opts

      @factory_man_names @factory_man_registry |> Enum.map(&elem(&1, 0)) |> Enum.reverse()
      def __factory_man__(:factories), do: @factory_man_names

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
    from the struct), and lazy values are resolved either way. Ignored for non-struct factories.
  - `:hooks` - A keyword list of hook functions to apply at different stages (see Hooks section)
  - `:associations` - A keyword list mapping Ecto association keys to FactoryMan factories. Use
    `:user` for a factory in the current module or `{FactoryModule, :user}` for a cross-module
    factory. Ecto supplies the associated schema and cardinality; caller-provided nested params
    are normalized into associated structs before the body. Missing keys remain untouched so
    `base_params` continues to provide defaults. Direct associations are supported; embeds and
    `:through` associations are not.
  - `:strict` - Set to `true` to raise on param keys that are not fields of the `:struct`
    option's struct, or `[allow: [...]]` to permit specific extra keys (see the Strict Params
    section). Ignored for non-struct factories.

  ## Generated Functions

  For a factory named `user` with `struct: User` and a plain params argument that defaults to an
  empty map, the following functions are generated. Insert functions require a configured repo, a table-backed
  Ecto schema, and `insert?` not set to `false`.

  - `build_user_struct/0,1` - Returns an unsaved struct
  - `build_user_params/0,1` - Clean params map derived from the built struct
  - `build_user_string_params/0,1` - Same, with string keys
  - `insert_user/0,1,2` - Inserts into the database (when repo is configured)
  - `build_user_struct_list/1,2` - Builds multiple structs
  - `build_user_params_list/1,2` - Builds multiple params maps
  - `build_user_string_params_list/1,2` - Builds multiple string-keyed params maps
  - `insert_user_list/1,2,3` - Inserts multiple items (when repo is configured)
  - `insert_user_struct/1,2` - Inserts an already-built struct through the insert pipeline

  For a factory named `greeting` without `struct:`, simplified names are used:

  - `build_greeting/1` - Returns the factory's value
  - `build_greeting_list/2` - Builds multiple items

  With a default argument in the factory head, `build_greeting/0` and `build_greeting_list/1` are
  also generated.

  ## Examples

      deffactory user(params \\\\ %{}), struct: User do
        base_params = %{
          username: FactoryMan.sequence("user"),
          email: FactoryMan.sequence(:email, fn n -> "user\#{n}@example.com" end)
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
    caller_module = __CALLER__.module

    quote bind_quoted: [
            factory_name: factory_name,
            head_ast: Macro.escape(head_ast, unquote: true),
            user_var: Macro.escape(user_var, unquote: true),
            arg_ast_no_default: Macro.escape(arg_ast_no_default, unquote: true),
            has_pattern_match: has_pattern_match,
            has_default: has_default,
            plain_var_ast: Macro.escape(plain_var_ast, unquote: true),
            caller_module: caller_module,
            opts: opts,
            block: Macro.escape(block, unquote: true)
          ] do
      parent_factory_opts = Module.get_attribute(__MODULE__, :parent_factory_opts)

      merged_opts = FactoryMan._merge_opts(parent_factory_opts, opts)

      body = Keyword.get(merged_opts, :body, :params)

      if body not in [:params, :struct] do
        raise ArgumentError,
              "invalid :body option: #{inspect(body)}. Expected :params (default) or :struct."
      end

      # Compile-time parse of :strict into `false` (disabled) or a list of allowed extra keys
      strict =
        case Keyword.get(merged_opts, :strict, false) do
          false ->
            false

          true ->
            []

          [allow: allow] when is_list(allow) ->
            if Enum.all?(allow, &is_atom/1) do
              allow
            else
              raise ArgumentError,
                    "invalid :strict option: [allow: #{inspect(allow)}]. " <>
                      "Allowed extra keys must be atoms."
            end

          other ->
            raise ArgumentError,
                  "invalid :strict option: #{inspect(other)}. " <>
                    "Expected true, false (default), or [allow: [keys]]."
        end

      # Extract hooks - used many times throughout
      hooks = Keyword.get(merged_opts, :hooks, [])

      # `:associations` is factory-level only: association keys belong to one schema, so
      # inheriting them from a module would apply another factory's keys to this struct.
      association_specs =
        FactoryMan.Associations.compile_specs!(
          caller_module,
          factory_name,
          merged_opts[:struct],
          Keyword.get(opts, :associations, [])
        )

      association_step =
        if association_specs == [] do
          nil
        else
          quote do
            unquote(user_var) =
              FactoryMan.Associations.normalize_params!(
                unquote(user_var),
                unquote(Macro.escape(association_specs)),
                unquote(caller_module),
                unquote(factory_name)
              )
          end
        end

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
        @doc "Builds a value from the `:#{factory_name}` factory."
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
        @doc "Builds a `#{inspect(merged_opts[:struct])}` struct from the `:#{factory_name}` factory (in memory, not persisted)."
        def unquote({build_struct_fn, [], [head_ast]})

        if body == :params do
          # Standard: the body returns a params map that is run through the params-stage hooks
          # and lazy evaluation, then converted with struct!/2.
          def unquote({build_struct_fn, [], [arg_ast_no_default]}) do
            FactoryMan._validate_params!(
              unquote(user_var),
              unquote(strict),
              unquote(merged_opts[:struct]),
              unquote(factory_name)
            )

            unquote(user_var) =
              FactoryMan.get_hook_handler(unquote(hooks), :before_build_params).(
                unquote(user_var)
              )

            unquote(association_step)

            unquote(block)
            |> FactoryMan.evaluate_lazy_attributes()
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :after_build_params).(&1))
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :before_build_struct).(&1))
            |> then(&struct!(unquote(merged_opts[:struct]), &1))
            |> then(&FactoryMan.get_hook_handler(unquote(hooks), :after_build_struct).(&1))
          end
        else
          # body: :struct: the body returns the struct directly.
          def unquote({build_struct_fn, [], [arg_ast_no_default]}) do
            FactoryMan._validate_params!(
              unquote(user_var),
              unquote(strict),
              unquote(merged_opts[:struct]),
              unquote(factory_name)
            )

            unquote(association_step)

            unquote(block)
            |> FactoryMan.evaluate_lazy_attributes()
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
          # are only needed in the params builder body. The insert pipeline itself lives in
          # insert_*_struct; this function only adds the build step in front of it.
          @doc "Builds the corresponding struct and inserts it. `repo_insert_opts` are passed to the repo's `insert!/2`."
          def unquote(insert_fn)(unquote(plain_var_ast), repo_insert_opts)
              when is_list(repo_insert_opts) do
            unquote(user_var)
            |> unquote(:"build_#{factory_name}_struct")()
            |> unquote(:"insert_#{factory_name}_struct")(repo_insert_opts)
          end

          Code.eval_quoted(
            FactoryMan.Codegen.insert_list_fns(insert_fn, :"#{insert_fn}_list", projections),
            [],
            __ENV__
          )

          # Insert an already-built struct through the factory's insert pipeline
          Code.eval_quoted(
            FactoryMan.Codegen.insert_struct_fns(
              :"insert_#{factory_name}_struct",
              struct_module,
              repo,
              hooks,
              factory_name
            ),
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
        base_params = %{username: FactoryMan.sequence("user"), role: "member"}

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

        @doc "Builds a value from the `:#{variant_name}` variant of the `:#{base_factory_name}` factory."
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

        @doc "Builds a `#{inspect(base_opts[:struct])}` struct from the `:#{variant_name}` variant of the `:#{base_factory_name}` factory (in memory, not persisted)."
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
          @doc "Builds the corresponding struct and inserts it. `repo_insert_opts` are passed to the repo's `insert!/2`."
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

          # Insert an already-built struct, delegating to the base factory's pipeline, since a
          # variant's preprocessor has no role once the struct is built
          Code.eval_quoted(
            FactoryMan.Codegen.insert_struct_delegate_fns(
              :"insert_#{full_name}_struct",
              struct_module,
              :"insert_#{base_factory_name}_struct",
              base_factory_name
            ),
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

  # Extracts the factory name and argument AST projections from the factory head
  # (e.g. `user(params \\ %{})`). Handles: params, params \\ %{}, %{key: val} = params,
  # and variations.
  defp extract_factory_args({name, _, [arg_ast]}) when is_atom(name) do
    Map.put(parse_arg_ast(arg_ast), :name, name)
  end

  defp extract_factory_args({name, _, args}) when is_atom(name) and is_list(args) do
    raise ArgumentError, """
    Invalid factory definition: expected exactly one argument, got #{length(args)}

    FactoryMan factories must have exactly one parameter (typically `params`).

    Valid examples:
      deffactory user(params \\\\ %{}), struct: User do ... end
      deffactory author(%{name: name} = params), struct: Author do ... end
    """
  end

  # Parses the single argument's AST into the projections used by the code generators:
  #
  # - :head_ast - argument as written for bodiless heads (default kept, pattern dropped)
  # - :user_var - the argument variable, for referencing in wrapper bodies
  # - :arg_no_default - argument for implementation clauses (pattern kept, default dropped)
  # - :has_pattern_match / :has_default - gate which convenience arities are generated
  # - :plain_var - the argument variable AST as written

  # Pattern match with default - %{key: val} = params \\ %{}
  defp parse_arg_ast({:\\, _, [{:=, _, [_pattern, var_ast]} = pattern, default]}) do
    %{
      # For function head, use just the variable with default (no pattern match)
      head_ast: {:\\, [], [plain_var(var_ast), default]},
      user_var: plain_var(var_ast),
      # Keep the full pattern for implementation
      arg_no_default: pattern,
      has_pattern_match: true,
      has_default: true,
      plain_var: var_ast
    }
  end

  # Variable with default - params \\ %{}
  defp parse_arg_ast({:\\, _, [var_ast, _default]} = ast) do
    %{
      # Keep the full \\ expression for head
      head_ast: ast,
      user_var: plain_var(var_ast),
      arg_no_default: var_ast,
      has_pattern_match: false,
      has_default: true,
      plain_var: var_ast
    }
  end

  # Pattern match without default - %{key: val} = params
  defp parse_arg_ast({:=, _, [_pattern, var_ast]} = ast) do
    %{
      # Use just the var for head (no destructuring)
      head_ast: plain_var(var_ast),
      user_var: plain_var(var_ast),
      # Keep the full pattern for implementation
      arg_no_default: ast,
      has_pattern_match: true,
      has_default: false,
      plain_var: var_ast
    }
  end

  # Simple variable - params
  defp parse_arg_ast({var_name, _, _} = ast) when is_atom(var_name) do
    %{
      head_ast: ast,
      user_var: plain_var(ast),
      arg_no_default: ast,
      has_pattern_match: false,
      has_default: false,
      plain_var: ast
    }
  end

  # Catch-all for unsupported patterns
  defp parse_arg_ast(ast) do
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

  # The bare variable from a variable AST node, stripped of any context metadata
  defp plain_var({var_name, _, _}) when is_atom(var_name), do: Macro.var(var_name, nil)

  @doc """
  Resolve one association from a factory's params.

  Reads `key` from the `params` map and resolves it:

  | Caller supplies | Result |
  | --- | --- |
  | key absent | builds with `:inherit` as params (or `nil` with `default: nil`) |
  | `nil` | `nil` |
  | params map | builds, merged over `:inherit` |
  | a struct | reused as-is (checked against `:struct`) |

  An explicit `nil` always resolves to `nil`. A factory that needs a value regardless can say so
  locally: `FactoryMan.assoc(params, :author, &build_author_struct/1) || build_author_struct()`.

  For ordinary Ecto factory associations, prefer the `:associations` factory option.

  `build_fun` is any 1-arity function that receives params for a new associated value.

  ## Options

  - `:struct` - validate supplied structs and builder results against this module.
  - `:inherit` - params merged below a supplied params map before building (default: `%{}`).
  - `:default` - what an absent key resolves to: `:build` (default) or `nil`.

  ## Examples

      FactoryMan.assoc(params, :author, &build_author_struct/1, struct: Author)
      FactoryMan.assoc(params, :editor, &build_author_struct/1, default: nil)
      FactoryMan.assoc(params, :author, &build_author_struct/1, inherit: %{role: "writer"})
  """
  @spec assoc(map(), atom(), (map() -> any()), keyword()) :: any()
  def assoc(params, key, build_fun, opts \\ []) do
    FactoryMan.Associations.resolve_key(params, key, build_fun, opts)
  end

  @doc """
  Resolve a list association from a factory's params.

  Reads `key` from the `params` map. An absent key resolves to `[]`, and an explicit `nil` raises
  (use `[]` for no associated values). Each list item must be a params map or an existing struct;
  mixed lists are supported and preserve their order.

  ## Options

  - `:struct` - validate supplied structs and builder results against this module.
  - `:inherit` - params merged below each supplied params map before building (default: `%{}`).

  ## Examples

      FactoryMan.assoc_list(params, :tags, &build_tag_struct/1, struct: Tag)
  """
  @spec assoc_list(map(), atom(), (map() -> any()), keyword()) :: list()
  def assoc_list(params, key, build_fun, opts \\ []) do
    FactoryMan.Associations.resolve_list_key(params, key, build_fun, opts)
  end

  @doc """
  Resolve one association value.

  The value form of `assoc/3,4`, for helpers that already hold a value rather than a params map:
  a params map is passed to `build_fun`, an existing struct is reused without calling the builder,
  and `nil` resolves to `nil`.

  ## Options

  - `:struct` - validate supplied structs and builder results against this module.
  - `:inherit` - params merged below a supplied params map before building (default: `%{}`).

  ## Examples

      FactoryMan.resolve_assoc(%{name: "Ann"}, &build_author_struct/1)
      FactoryMan.resolve_assoc(author_or_params, &build_author_struct/1, struct: Author)
  """
  @spec resolve_assoc(any(), (map() -> any()), keyword()) :: any()
  def resolve_assoc(value, build_fun, opts \\ []) do
    FactoryMan.Associations.resolve(value, build_fun, opts)
  end

  @doc """
  Resolve a list of association values.

  The value form of `assoc_list/3,4`. Each item must be a params map or an existing struct; `nil`
  (as the list itself or as an item) raises.

  ## Options

  - `:struct` - validate supplied structs and builder results against this module.
  - `:inherit` - params merged below each supplied params map before building (default: `%{}`).

  ## Examples

      FactoryMan.resolve_assoc_list(
        [%{body: "a"}, existing_comment],
        &build_comment_struct/1,
        struct: Comment
      )
  """
  @spec resolve_assoc_list(any(), (map() -> any()), keyword()) :: list()
  def resolve_assoc_list(values, build_fun, opts \\ []),
    do: FactoryMan.Associations.resolve_list(values, build_fun, opts)

  @doc false
  @spec evaluate_lazy_attributes(any) :: any
  def evaluate_lazy_attributes(%{__struct__: record} = factory) do
    independent = factory |> Map.from_struct() |> resolve_independent_pairs()
    parent = struct!(record, independent)

    struct!(record, resolve_derived_pairs(independent, parent))
  end

  def evaluate_lazy_attributes(attrs) when is_map(attrs) do
    independent = resolve_independent_pairs(attrs)
    parent = Map.new(independent)

    independent |> resolve_derived_pairs(parent) |> Map.new()
  end

  def evaluate_lazy_attributes(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      independent = resolve_independent_pairs(attrs)

      resolve_derived_pairs(independent, independent)
    else
      attrs
    end
  end

  def evaluate_lazy_attributes(value), do: value

  # First pass: the values that do not depend on anything else in the factory.
  defp resolve_independent_pairs(pairs) do
    Enum.map(pairs, fn
      {k, v} when is_function(v) and not is_function(v, 1) -> {k, v.()}
      {_, _} = pair -> pair
    end)
  end

  # Second pass: the derived values, which read the results of the first pass.
  defp resolve_derived_pairs(pairs, parent) do
    Enum.map(pairs, fn
      {k, v} when is_function(v, 1) -> {k, v.(parent)}
      {_, _} = pair -> pair
    end)
  end

  @doc false
  def fallback_hook_handler(value), do: value

  @doc false
  def get_hook_handler(hooks, hook), do: hooks[hook] || (&FactoryMan.fallback_hook_handler/1)

  @doc false
  def _validate_params!(params, _strict, _struct_module, factory_name) when not is_map(params) do
    raise ArgumentError,
          "expected a params map for factory :#{factory_name}, got: #{inspect(params)}"
  end

  def _validate_params!(params, false = _strict, _struct_module, _factory_name),
    do: params

  def _validate_params!(params, strict, struct_module, factory_name)
      when is_map(params) and is_list(strict) do
    allowed = (Map.keys(struct_module.__struct__()) -- [:__struct__, :__meta__]) ++ strict
    unknown = Map.keys(params) -- allowed

    if unknown != [] do
      raise ArgumentError,
            "unknown params #{inspect(Enum.sort(unknown))} for strict factory " <>
              ":#{factory_name} (struct #{inspect(struct_module)}). " <>
              "Allowed keys: #{inspect(Enum.sort(allowed))}"
    end

    params
  end

  def _validate_params!(params, _strict, _struct_module, _factory_name), do: params

  @doc false
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
  Generates a sequence of strings.

  The sequence name is used as the beginning of the string. For example, if you
  do `FactoryMan.sequence("joe")`, you will get back `"joe0"`, then `"joe1"`, and so on.

  ## Example

      def user_factory do
        %{
          username: FactoryMan.sequence("joe")
        }
      end

  If you want to customize the returned string you can use `sequence/2`.
  """

  @spec sequence(String.t()) :: String.t()
  def sequence(name), do: FactoryMan.Sequence.next(name)

  @doc """
  Returns the next value in a named sequence.

  A formatter function receives the current counter. A list cycles through its items. Returned
  values are not guaranteed to be unique.

  ## Example with a formatter function

      def user_factory do
        %{
          email: FactoryMan.sequence(:email, fn n -> "me-\#{n}@foo.com" end)
        }
      end

  ## Example with a list

      def user_factory do
        %{
          name: FactoryMan.sequence(:name, ["Joe", "Mike", "Sarah"])
        }
      end
  """

  @spec sequence(any, (integer -> any) | nonempty_list) :: any
  def sequence(name, formatter), do: FactoryMan.Sequence.next(name, formatter)

  @doc """
  Returns the next value in a named sequence using a formatter function.

  `:start_at` sets the initial counter when the named sequence does not yet exist. It does not change
  an existing counter. List formatters are supported by `sequence/2`, not `sequence/3`.

  ## Example

      def money_factory do
        %{
          cents: FactoryMan.sequence(:cents, fn n -> "\#{n}" end, start_at: 600)
        }
      end
  """

  @spec sequence(any, (integer -> any), start_at: non_neg_integer) :: any
  def sequence(name, formatter, opts), do: FactoryMan.Sequence.next(name, formatter, opts)
end
