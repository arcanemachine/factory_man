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

  The diagram shows the build pipeline with `body: :params`. Declared `assocs:` are resolved
  after `before_build_params` and before the factory body. Each function shown has a
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

  **Associations**: declare association builders with the `assocs:` option (see the
  [Cookbook](cookbook.html)):

  ```elixir
  deffactory author(params \\\\ %{}), struct: Author, assocs: [user: &build_user_struct/1] do
    base_params = %{name: "Author of \#{params.user.username}"}

    Map.merge(base_params, params)
  end
  ```

  Each declared key is resolved before the body, so the body always receives it resolved, and
  the canonical `Map.merge(base_params, params)` ending is always correct. The builder is the
  default: an absent key is built with `%{}`, so a `base_params` default for a declared key is
  never used.

  A builder is any 1-arity function (captures, local or remote, and anonymous functions),
  a 2-arity function that also receives the factory params (see Chaining below), or
  `{builder, options}` with either or both of:

  - `default: value` - what an absent key is treated as.
  - `required: true` - the key must resolve to a non-nil value: a caller's `nil`, or a builder
    that returns `nil`, raises. An absent key still builds. Singular associations only, and not
    together with `default: nil`.

  | Caller supplies | Singular association | Plural association |
  | --- | --- | --- |
  | Key absent | Treated as `default:` (`%{}` unless set) | Treated as `default:` (`[]` unless set) |
  | `nil` | `nil` | Raise; use `[]` |
  | Params map | Built by the builder | Raise |
  | Struct | Reused unchanged; the builder is not called | Raise |
  | List of maps/structs | Raise | Each item resolved in order |

  Supplied structs and builder results must be the related schema, which Ecto provides (a builder
  for a singular association may return `nil`, unless the key is `required: true`). Keys must be direct associations of an Ecto
  schema `struct:`; embeds and `:through` associations are not supported. `default:` is `nil` or a
  params map for a singular association, and a list of params maps for a plural one.

  `assocs:` is evaluated at build time, on every build, like the factory body, so it can hold
  local captures and anonymous functions. The factory's `params` variable is not in scope there.
  Any side effect in a `default:` value (an insert, a query, a sequence) therefore happens even
  when the caller supplies the key; keep defaults to literals. A record at an association position
  inside `default:` is rejected. The declaration is validated when the factory first builds.

  **Chaining**: keys resolve top to bottom. A 2-arity builder receives `(params, factory_params)`,
  where `factory_params` holds the caller's params with every key declared above resolved. The
  current key and the keys declared below it are hidden; undeclared keys are visible as given.

  **Recursion**: a self-referential or mutually recursive default build (e.g. a user whose
  `mentor` builder builds a user) raises instead of recursing forever. Declare such a key with
  `default: nil` (`default: []` for a list), or pass a value (a required key can only be passed a
  value). The guard also rejects recursion that would stop on its own while the key stays absent;
  supply the key at each level instead.

  **`required: true`** is checked when the key resolves, which includes a `nil` set by a
  `before_build_params` hook. It does not check the finished struct: a body that puts `nil` back
  afterwards is not caught.

  **Imperative resolution**: `assoc/3,4` and `assoc_list/3,4` apply the same rules to one key of a
  params map (without `required:` or the schema check), for plain helper functions, values
  computed in the body, and builders. They return
  the resolved value and do not modify the params map, so put it back (or drop the key) before a
  final `Map.merge(base_params, params)`.

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
  - `:hooks` - Hooks applied to all factories in the module, chained with inherited hooks

  **Factory-level** (set with `deffactory`):

  - `:struct` - Ecto schema module (enables struct, params, and insert functions)
  - `:insert?` - Set to `false` to skip insert functions
  - `:body` - What the factory body returns: `:params` (default, a params map) or `:struct`
    (a struct built directly by the body). Params functions are generated either way (derived
    from the struct), and lazy values are resolved either way. Ignored for non-struct factories.
  - `:hooks` - Chained with the module-level hooks (see Hook Order below)
  - `:repo` - Overrides the module-level repo for this factory
  - `:assocs` - Keyword list mapping Ecto association keys to builders (see Associations above).
    Factory-level only.
  - `:strict` - Reject unknown param keys at the factory boundary (see Strict Params below)

  `:body` and `:strict` cascade from the module level and are ignored by non-struct factories.
  `:assocs` is factory-level only, because association keys belong to a single schema, and it
  requires an Ecto schema `struct:`. Unknown options raise.

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
    params validation → before_build_params → assocs: resolution
    → [factory body + lazy eval] → after_build_params
    → before_build_struct → struct!() → after_build_struct

  build_user_params (calls build_user_struct internally):
    → strip Ecto metadata (or Map.from_struct/1 for plain structs)

  insert_user (calls build_user_struct internally):
    → before_insert → Repo.insert!() → after_insert
  ```

  With `body: :struct`, `assocs:` are resolved after params validation and before the body, and
  the struct the body returns is lazily evaluated. Params-stage hooks remain skipped. A variant
  resolves its own `assocs:` before its body, then delegates to the base builder, which reuses the
  resolved structs. `insert_*_struct` receives an already-built struct and does not resolve
  associations.

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

  A hook is a 1-arity remote capture such as `&__MODULE__.my_hook/1` or `&MyApp.Hooks.my_hook/1`.
  Hooks are compiled into the generated functions, so anything that is not a remote capture, such
  as an anonymous function (`fn ... end`), raises at compile time.

  ### Hook Order

  Hooks can be set at three levels, and a hook set at a lower level is chained with the hooks it
  inherits instead of replacing them:

  1. **Parent module** - `use FactoryMan, hooks: [...]`
  2. **Child module** - `use FactoryMan, extends: Parent, hooks: [...]` (any number of levels)
  3. **Individual factory** - `deffactory name(params), hooks: [...]`

  The order is onion-style, like middleware: the parent wraps the child. For a `before_*` hook
  the parent's runs first, and for an `after_*` hook the parent's runs last. A parent's
  `after_insert` that resets associations therefore sees the final struct, after any factory
  `after_insert`.

  To place a hook explicitly, pass `{hook, placement}`:

  | Placement         | Runs                                  | Default for       |
  | ----------------- | ------------------------------------- | ----------------- |
  | `:after_parent`   | After the inherited hooks             | `before_*` hooks  |
  | `:before_parent`  | Before the inherited hooks            | `after_*` hooks   |
  | `:replace_parent` | Instead of all of the inherited hooks | -                 |

  A plain hook uses the default placement for its hook name. "Parent" means everything inherited
  for that hook name, from every level above. Each level is resolved against the list built so
  far. For example, with `after_insert`:

  ```elixir
  # Parent module:       after_insert: &P.hook/1                      -> [P]
  # Child module:        after_insert: {&C.hook/1, :after_parent}     -> [P, C]
  # Factory:             after_insert: &F.hook/1                      -> [F, P, C]
  ```

  Each hook receives the previous hook's result. The same hook set at two levels runs twice. On
  a module with no parent, a placement behaves like a plain hook. To switch off an inherited hook
  for one factory, replace it with an identity function:
  `hooks: [after_insert: {&Function.identity/1, :replace_parent}]`.

  `__factory_man__(:opts)` and `__factory_man__(:opts, name)` show each hook name's resolved list,
  in run order. Unknown hook names, a hook name set twice at one level, and invalid hook values
  raise.

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

  `assocs:` is code evaluated at build time, so it does not appear in `:opts`. `:factories` lists
  every factory and variant registered in the module (variants under their full name), which
  enables runtime dispatch without string-building function names:

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

      FactoryMan._validate_module_opts!(unquote(opts), __MODULE__)

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

      # Each variant's root factory, so the recursion guard treats a variant and its base as one
      Module.register_attribute(__MODULE__, :factory_man_variant_roots, accumulate: true)

      parent_opts =
        case unquote(opts)[:extends] do
          nil -> []
          extends -> extends.__info__(:attributes)[:parent_factory_opts] || []
        end

      # Resolved against an empty parent for a root module too, so every module stores its hooks
      # as lists of functions in run order
      parent_factory_opts = FactoryMan._merge_opts(parent_opts, unquote(opts))

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
  - `:hooks` - A keyword list of hook functions to apply at different stages, chained with the
    module's hooks (see Hooks section)
  - `:repo` - Overrides the module-level repo for this factory
  - `:assocs` - A keyword list mapping Ecto association keys to builders: a 1-arity function, a
    2-arity function `(params, factory_params)`, or `{builder, options}` with `default: value`
    and/or `required: true`. Each key is resolved before the body, which always receives it
    resolved; an absent key is built with `%{}` (or treated as `default:`). Evaluated on every build; `params` is not in scope. Requires
    an Ecto schema `struct:`. Direct associations only. See the Associations section in the
    module documentation.
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
    {assocs_ast, opts} = pop_assocs(opts)

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
            assocs_ast: Macro.escape(assocs_ast, unquote: true),
            block: Macro.escape(block, unquote: true)
          ] do
      FactoryMan._reject_non_literal_assocs!(opts)

      subject = "factory :#{factory_name} in #{inspect(caller_module)}"

      FactoryMan._validate_opts!(
        opts,
        [:struct, :insert?, :body, :hooks, :strict, :repo, :assocs],
        subject
      )

      FactoryMan._validate_hooks!(opts, subject)

      parent_factory_opts = Module.get_attribute(__MODULE__, :parent_factory_opts)

      merged_opts = FactoryMan._merge_opts(parent_factory_opts, opts)

      body = Keyword.get(merged_opts, :body, :params)

      if body not in [:params, :struct] do
        raise ArgumentError,
              "invalid :body option: #{inspect(body)}. Expected :params (default) or :struct."
      end

      # Compile-time parse of :strict into `false` (disabled) or a list of allowed extra keys
      strict = FactoryMan._parse_strict!(Keyword.get(merged_opts, :strict, false))

      # Extract hooks - used many times throughout
      hooks = Keyword.get(merged_opts, :hooks, [])

      association_step =
        FactoryMan._association_step(
          assocs_ast,
          user_var,
          merged_opts[:struct],
          caller_module,
          factory_name
        )

      if association_step do
        defp unquote(FactoryMan._assocs_fn(factory_name))(), do: unquote(assocs_ast)
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
          FactoryMan.Associations.track_factory(__MODULE__, unquote(factory_name), fn ->
            unquote(user_var) =
              unquote(FactoryMan.Codegen.hook_pipe(user_var, hooks, :before_build_params))

            unquote(
              FactoryMan.Codegen.hook_pipe(
                quote(do: FactoryMan.evaluate_lazy_attributes(unquote(block))),
                hooks,
                :after_build_params
              )
            )
          end)
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
            FactoryMan.Associations.track_factory(__MODULE__, unquote(factory_name), fn ->
              FactoryMan._validate_params!(
                unquote(user_var),
                unquote(strict),
                unquote(merged_opts[:struct]),
                unquote(factory_name)
              )

              unquote(user_var) =
                unquote(FactoryMan.Codegen.hook_pipe(user_var, hooks, :before_build_params))

              unquote(association_step)

              unquote(
                FactoryMan.Codegen.build_struct_pipeline(block, hooks, merged_opts[:struct])
              )
            end)
          end
        else
          # body: :struct: the body returns the struct directly.
          def unquote({build_struct_fn, [], [arg_ast_no_default]}) do
            FactoryMan.Associations.track_factory(__MODULE__, unquote(factory_name), fn ->
              FactoryMan._validate_params!(
                unquote(user_var),
                unquote(strict),
                unquote(merged_opts[:struct]),
                unquote(factory_name)
              )

              unquote(association_step)

              unquote(
                FactoryMan.Codegen.hook_pipe(
                  quote(do: FactoryMan.evaluate_lazy_attributes(unquote(block))),
                  hooks,
                  :after_build_struct
                )
              )
            end)
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

  - `:assocs` - Association builders resolved before the variant body, with the same shape as
  the `deffactory` option. The base factory reuses the resolved structs, so a variant can build
  an association differently from its base. Requires a base factory with an Ecto schema `struct:`.
  The base still enforces its own `required: true`, so a variant can add `required:` to a key but
  cannot relax it: a variant `default: nil` on a key the base requires raises on every default
  build.

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

    _validate_opts!(opts, [:for, :as, :assocs], "defvariant #{variant_name}")
    {assocs_ast, opts} = pop_assocs(opts)
    base_factory_name = opts[:for] || raise ArgumentError, "defvariant requires the :for option"
    as_name = opts[:as]
    caller_module = __CALLER__.module

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
            caller_module: caller_module,
            assocs_ast: Macro.escape(assocs_ast, unquote: true),
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

      root_name =
        Enum.find_value(@factory_man_variant_roots, base_factory_name, fn
          {^base_factory_name, root} -> root
          _ -> nil
        end)

      @factory_man_variant_roots {full_name, root_name}

      # A variant's associations resolve before the variant body. The base factory then reuses
      # the resolved structs. The base's strict check runs first, so a bad key fails before
      # anything is built.
      association_step =
        if assocs_ast do
          quote do
            FactoryMan._validate_params!(
              unquote(user_var),
              unquote(FactoryMan._parse_strict!(Keyword.get(base_opts, :strict, false))),
              unquote(base_opts[:struct]),
              unquote(base_factory_name)
            )

            unquote(
              FactoryMan._association_step(
                assocs_ast,
                user_var,
                base_opts[:struct],
                caller_module,
                full_name
              )
            )
          end
        end

      if association_step do
        defp unquote(FactoryMan._assocs_fn(full_name))(), do: unquote(assocs_ast)
      end

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
          FactoryMan.Associations.track_factory(
            __MODULE__,
            unquote(full_name),
            unquote(root_name),
            fn ->
              unquote(block)
              |> unquote(base_build_fn)()
            end
          )
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
          FactoryMan.Associations.track_factory(
            __MODULE__,
            unquote(full_name),
            unquote(root_name),
            fn ->
              unquote(association_step)

              unquote(block)
              |> unquote(:"build_#{base_factory_name}_struct")()
            end
          )
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

          # Build through the variant, then insert through the base factory's pipeline
          @doc "Builds the corresponding struct and inserts it. `repo_insert_opts` are passed to the repo's `insert!/2`."
          def unquote(insert_fn)(unquote(plain_var_ast), repo_insert_opts)
              when is_list(repo_insert_opts) do
            unquote(user_var)
            |> unquote(build_struct_fn)()
            |> unquote(:"insert_#{base_factory_name}_struct")(repo_insert_opts)
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

  # `assocs:` is code, not a compile-time value: it may hold local captures and anonymous
  # functions, so it is popped from the options AST and compiled into its own function.
  defp pop_assocs(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: Keyword.pop(opts, :assocs), else: {nil, opts}
  end

  defp pop_assocs(opts), do: {nil, opts}

  @doc false
  def _reject_non_literal_assocs!(opts) do
    if is_list(opts) and Keyword.keyword?(opts) and Keyword.has_key?(opts, :assocs) do
      raise ArgumentError, "assocs: must be written directly in the deffactory/defvariant call"
    end
  end

  @doc false
  def _assocs_fn(factory_name), do: :"__factory_man_assocs_#{factory_name}__"

  # The step that resolves declared associations into the params variable, or `nil` without
  # `assocs:`. Validation of the declaration itself happens at build time.
  @doc false
  def _association_step(nil, _user_var, _schema, _module, _factory_name), do: nil

  def _association_step(_assocs_ast, user_var, schema, module, factory_name) do
    FactoryMan.Associations.validate_schema!(schema, module, factory_name)

    quote do
      unquote(user_var) =
        FactoryMan.Associations.resolve_assocs!(
          unquote(user_var),
          unquote(_assocs_fn(factory_name))(),
          unquote(schema),
          unquote(module),
          unquote(factory_name)
        )
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
  Resolve one association from a params map.

  Reads `key` from `params` and resolves it with the same rules as the `assocs:` option (there is
  no `required:` option here):

  | Caller supplies | Result |
  | --- | --- |
  | key absent | treated as `default:` (`%{}` unless set), then resolved |
  | `nil` | `nil` |
  | params map | built with `build_fun` |
  | a struct | reused unchanged, `build_fun` not called |

  Use it where `assocs:` does not fit: an association resolved from a value computed in the body,
  a plain helper function, or inside a builder. `params` is not modified; put the result back, or
  drop the key, before a final `Map.merge(base_params, params)`.

  Unlike `assocs:`, the result is not checked against a schema. A default build that starts
  again inside itself raises, as it does for `assocs:` (see Recursion in the module
  documentation).

  ## Options

  - `:default` - what an absent key is treated as: `nil` or a params map (default: `%{}`). It is
    evaluated on every call, even when the key is present, so keep it literal.

  ## Examples

      FactoryMan.assoc(params, :author, &build_user_struct/1)
      FactoryMan.assoc(params, :editor, &build_user_struct/1, default: nil)
      FactoryMan.assoc(params, :author, &build_user_struct(Map.merge(%{role: "writer"}, &1)))
  """
  @spec assoc(map(), atom(), (map() -> any()), keyword()) :: any()
  def assoc(params, key, build_fun, opts \\ []) do
    FactoryMan.Associations.resolve_key(params, key, build_fun, opts, :one)
  end

  @doc """
  Resolve a list association from a params map.

  Reads `key` from `params`. An absent key is treated as `default:` (`[]` unless set). An explicit
  `nil` raises (use `[]` for no associated values). Each list item must be a params map (built with
  `build_fun`, which must not return `nil`) or a struct (reused unchanged); order is preserved.

  Like `assoc/3,4`, results are not checked against a schema, and a default build that starts
  again inside itself raises.

  ## Options

  - `:default` - what an absent key is treated as: a list of params maps (default: `[]`). It is
    evaluated on every call, even when the key is present, so keep it literal.

  ## Examples

      FactoryMan.assoc_list(params, :tags, &build_tag_struct/1)
      FactoryMan.assoc_list(params, :tags, &build_tag_struct/1, default: [%{name: "elixir"}])
  """
  @spec assoc_list(map(), atom(), (map() -> any()), keyword()) :: list()
  def assoc_list(params, key, build_fun, opts \\ []) do
    FactoryMan.Associations.resolve_key(params, key, build_fun, opts, :many)
  end

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

  # Parses `:strict` into `false` (disabled) or a list of allowed extra keys
  @doc false
  def _parse_strict!(false), do: false
  def _parse_strict!(true), do: []

  def _parse_strict!([allow: allow] = strict) when is_list(allow) do
    if Enum.all?(allow, &is_atom/1) do
      allow
    else
      raise ArgumentError,
            "invalid :strict option: #{inspect(strict)}. Allowed extra keys must be atoms."
    end
  end

  def _parse_strict!(other) do
    raise ArgumentError,
          "invalid :strict option: #{inspect(other)}. " <>
            "Expected true, false (default), or [allow: [keys]]."
  end

  @doc false
  def _validate_module_opts!(opts, module) do
    if is_list(opts) and Keyword.has_key?(opts, :assocs) do
      raise ArgumentError,
            "invalid module option :assocs in #{inspect(module)}. Association keys belong to " <>
              "a single schema, so assocs: is set per factory, not per module."
    end

    subject = "use FactoryMan in #{inspect(module)}"

    _validate_opts!(opts, [:repo, :extends, :hooks, :body, :strict, :insert?, :struct], subject)
    _validate_hooks!(opts, subject)
  end

  @doc false
  def _validate_opts!(opts, allowed, subject) do
    unless is_list(opts) and Keyword.keyword?(opts) do
      raise ArgumentError,
            "expected options for #{subject} to be a keyword list, got: #{inspect(opts)}"
    end

    case Keyword.keys(opts) -- allowed do
      [] ->
        opts

      unknown ->
        raise ArgumentError,
              "unknown options #{inspect(unknown)} for #{subject}. " <>
                "Allowed options: #{inspect(allowed)}"
    end
  end

  # Each hook name and where a plain hook function runs relative to the inherited hooks. The
  # parent wraps the child: its `before_*` hooks run first and its `after_*` hooks run last.
  @hook_default_placements [
    before_build_params: :after_parent,
    after_build_params: :before_parent,
    before_build_struct: :after_parent,
    after_build_struct: :before_parent,
    before_insert: :after_parent,
    after_insert: :before_parent
  ]

  @hook_placements [:before_parent, :after_parent, :replace_parent]

  @doc false
  def _validate_hooks!(opts, subject) do
    hooks = Keyword.get(opts, :hooks, [])

    unless is_list(hooks) and Keyword.keyword?(hooks) do
      raise ArgumentError,
            "expected :hooks for #{subject} to be a keyword list, got: #{inspect(hooks)}"
    end

    hook_names = Keyword.keys(hooks)

    case Enum.uniq(hook_names) -- Keyword.keys(@hook_default_placements) do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "unknown hooks #{inspect(unknown)} for #{subject}. " <>
                "Allowed hooks: #{inspect(Keyword.keys(@hook_default_placements))}"
    end

    case hook_names -- Enum.uniq(hook_names) do
      [] ->
        :ok

      duplicates ->
        raise ArgumentError,
              "duplicate hooks #{inspect(Enum.uniq(duplicates))} for #{subject}. " <>
                "Set each hook once per level."
    end

    Enum.each(hooks, fn {hook_name, value} -> validate_hook!(hook_name, value, subject) end)
  end

  # Hooks are compiled into the generated functions as remote calls, so only remote captures are
  # accepted. Other functions (anonymous functions, local captures) have no code form to compile.
  defp validate_hook!(hook_name, value, subject) do
    {fun, placement} = split_hook(hook_name, value)

    unless is_function(fun, 1) and Function.info(fun, :type) == {:type, :external} do
      raise ArgumentError,
            "invalid hook #{inspect(hook_name)} for #{subject}: #{inspect(value)}. " <>
              "Expected a 1-arity remote capture such as `&MyModule.my_hook/1`, " <>
              "or `{capture, placement}`."
    end

    if placement not in @hook_placements do
      raise ArgumentError,
            "invalid placement #{inspect(placement)} for hook #{inspect(hook_name)} for " <>
              "#{subject}. Expected one of: #{inspect(@hook_placements)}."
    end
  end

  defp split_hook(_hook_name, {fun, placement}), do: {fun, placement}
  defp split_hook(hook_name, fun), do: {fun, Keyword.fetch!(@hook_default_placements, hook_name)}

  @doc false
  def _merge_opts(parent_opts, child_opts) do
    parent_hooks = Keyword.get(parent_opts, :hooks, [])
    child_hooks = Keyword.get(child_opts, :hooks, [])

    # Parent hooks have already been resolved into lists of functions in run order. Each child
    # hook is placed relative to the inherited list.
    merged_hooks =
      Enum.flat_map(Keyword.keys(@hook_default_placements), fn hook_name ->
        inherited = Keyword.get(parent_hooks, hook_name, [])

        case place_hook(inherited, hook_name, child_hooks[hook_name]) do
          [] -> []
          resolved -> [{hook_name, resolved}]
        end
      end)

    merged_opts = parent_opts |> Keyword.merge(child_opts) |> Keyword.delete(:hooks)

    if merged_hooks == [] do
      merged_opts
    else
      Keyword.put(merged_opts, :hooks, merged_hooks)
    end
  end

  defp place_hook(inherited, _hook_name, nil = _child_value), do: inherited

  defp place_hook(inherited, hook_name, child_value) do
    case split_hook(hook_name, child_value) do
      {fun, :before_parent} -> [fun | inherited]
      {fun, :after_parent} -> inherited ++ [fun]
      {fun, :replace_parent} -> [fun]
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
