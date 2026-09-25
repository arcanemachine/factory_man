defmodule FactoryMan do
  @moduledoc """
  An Elixir library for generating test data. Define factories with `deffactory`, and FactoryMan
  generates functions for building params and structs, and inserting records.

  ## Quick Start

  ```elixir
  defmodule MyApp.Factory do
    use FactoryMan, repo: MyApp.Repo

    alias MyApp.Users.User

    deffactory user(params \\\\ %{}), struct: User do
      base_params = %{username: FactoryMan.sequence("user")}

      Map.merge(base_params, params)
    end
  end
  ```

  ## Generated Functions

  For a factory named `:user` with `struct: User` and a params argument that defaults to an empty
  map:

  | Function                              | Returns          | Purpose                              |
  | ------------------------------------- | ---------------- | ------------------------------------ |
  | `build_user_struct/0,1,2`             | `%User{}`        | Struct in memory (not persisted)     |
  | `build_user_params/0,1,2`             | `%{}`            | Clean params map derived from struct |
  | `build_user_string_params/0,1,2`      | `%{"" => ...}`   | Same, with string keys               |
  | `insert_user/0,1,2`                   | `%User{}`        | Built and inserted                   |
  | `build_user_struct_list/1,2,3`        | `[%User{}, ...]` | List of structs                      |
  | `build_user_params_list/1,2,3`        | `[%{}, ...]`     | List of params maps                  |
  | `build_user_string_params_list/1,2,3` | `[%{}, ...]`     | List of string-keyed params maps     |
  | `insert_user_list/1,2,3`              | `[%User{}, ...]` | List of inserted records             |
  | `insert_user_struct/1,2`              | `%User{}`        | Inserts an already-built struct      |

  The insert functions use the default insert target, the repo's `insert!/2`, which requires a
  configured repo and a table-backed Ecto schema (see Insert Targets). Each list item is built
  independently. `insert_user_struct` has no list counterpart.

  Every builder takes options after its params (`build_user_struct/2`, `build_user_struct_list/3`,
  and so on). The only builder option is `variants:` (see Variant Factories). Insert functions take
  one keyword list: FactoryMan uses `:variants`, and every other option is passed to the insert
  target unchanged. The `*_struct` insert forms take no `variants:`, since the struct is already
  built:

  ```elixir
  insert_user(%{username: "alice"}, variants: [:admin], returning: true, prefix: "tenant_a")
  #                                 └─ FactoryMan ───┘  └─ Ecto (Repo.insert!/2) ───────┘
  ```

  Zero-arity builders and inserts require a default argument in the factory head. For struct
  factories, count-only list functions pass `%{}` and are omitted when the head pattern-matches its
  argument. Non-struct count-only list functions require a default argument and use that default.

  What gets generated depends on the factory configuration:

  | Factory configuration    | Value builders | Params builders | Struct builders | Inserts                       |
  | ------------------------ | -------------- | --------------- | --------------- | ----------------------------- |
  | No `struct:` option      | Yes            | No              | No              | No                            |
  | Plain struct             | No             | Yes             | Yes             | With an `insert:` capture     |
  | Table-backed Ecto schema | No             | Yes             | Yes             | Yes, unless `insert: false`   |
  | Embedded schema          | No             | Yes             | Yes             | With an `insert:` capture     |

  Value builders are `build_<name>` and `build_<name>_list`. Any struct factory also gets an
  `insert_<name>_via_<target>` family for each `insert_via:` target. `body: :struct` changes how
  the struct is built, not which functions are generated.

  ### Disabling function families

  `disable:` switches off function families that a test suite does not use. `true` disables a
  family, and `false` enables an inherited one again:

  ```elixir
  use FactoryMan, repo: MyApp.Repo, disable: [string_params: true, insert_list: true]

  deffactory user(params \\\\ %{}), struct: User, disable: [string_params: false] do
    Map.merge(%{username: FactoryMan.sequence("user")}, params)
  end
  ```

  | Key                   | Removes                                                   |
  | --------------------- | --------------------------------------------------------- |
  | `:params`             | `build_*_params/0,1,2` and its list                       |
  | `:string_params`      | `build_*_string_params/0,1,2` and its list                |
  | `:struct_list`        | `build_*_struct_list/1,2,3`                               |
  | `:params_list`        | `build_*_params_list/1,2,3`                               |
  | `:string_params_list` | `build_*_string_params_list/1,2,3`                        |
  | `:insert_list`        | `insert_*_list/1,2,3`, including `insert_via:` target lists |
  | `:non_struct_list`    | A non-struct factory's `build_*_list/1,2,3`                |

  - `:params` and `:string_params` are independent: `build_*_string_params` does not use
    `build_*_params`, so either can be disabled alone.
  - Everything else is always generated. `build_*_struct` cannot be disabled, since every other
    family builds on it, and inserts are switched off with `insert:` and `insert_via:`.
  - `disable:` cascades per key, and variants follow their base factory. `false` on a family that
    is not disabled has no effect.
  - A key for the other kind of factory (`:non_struct_list` on a struct factory, or any other key
    on a non-struct factory) raises when written on the factory itself, whatever its value, and is
    ignored when inherited.
  - A disabled function's name is free: the module can define a function with that name.

  ## Defining Factories

  `deffactory` defines a named factory with one argument and a body. With `struct:` and the default
  `body: :params`, the body returns a map of that struct's fields. With `body: :struct`, it returns
  the struct itself. Without `struct:`, the body can return any value, and the factory generates
  only `build_<name>` and `build_<name>_list`:

  ```elixir
  deffactory search_opts(overrides \\\\ []) do
    Keyword.merge([page: 1, per_page: 20], overrides)
  end
  ```

  The argument can have any name, and can pattern-match (`%{username: _} = params`). Merge the
  params yourself, last, so the caller's values win: FactoryMan does not merge them for you.

  ## Associations

  Declare association builders with `assocs:` (Ecto schema `struct:` only). Each declared key is
  resolved before the body, so the body always receives it resolved, and the final
  `Map.merge(base_params, params)` stays correct:

  ```elixir
  deffactory author(params \\\\ %{}), struct: Author, assocs: [user: &build_user_struct/1] do
    base_params = %{name: "Author of \#{params.user.username}"}

    Map.merge(base_params, params)
  end
  ```

  A builder is a 1-arity function (a local or remote capture, or an anonymous function), a
  2-arity function `(params, factory_params)`, or `{builder, options}`. The builder is the
  default: an absent key is built with `%{}` (a list key with `[]`), so a `base_params` default for
  a declared key is never used.

  | Caller supplies      | Singular association                        | Plural association                      |
  | -------------------- | ------------------------------------------- | --------------------------------------- |
  | Key absent           | Treated as `default:` (`%{}` unless set)    | Treated as `default:` (`[]` unless set) |
  | `nil`                | `nil`                                       | Raise; use `[]`                         |
  | Params map           | Built by the builder                        | Raise                                   |
  | Struct               | Reused unchanged; the builder is not called | Raise                                   |
  | List of maps/structs | Raise                                       | Each item resolved in order             |

  - Keys must be direct associations; embeds and `:through` associations are not supported.
    Supplied structs and builder results must be the related schema (a singular builder may
    return `nil`, unless the key is `required: true`).
  - `default: value` is what an absent key is treated as: `nil` or a params map for a singular
    association, a list of params maps for a plural one. It is evaluated on every build, even when
    the caller supplies the key, so keep it a literal. A record at an association position inside
    `default:` raises.
  - `required: true` (singular keys only, not with `default: nil`) raises when the key resolves to
    `nil`, from the caller, a `before_build_params` hook, or the builder. It does not check the
    finished struct.
  - Keys resolve top to bottom. A 2-arity builder's `factory_params` holds the caller's params with
    the keys declared above it resolved; the current key and the keys below it are hidden, and
    undeclared keys are visible as given. See
    [Chain associations](cookbook.html#chain-associations).
  - A self-referential or mutually recursive default build raises instead of recursing forever.
    This includes recursion that would stop on its own while the key stays absent. Declare such a
    key with `default: nil` (or `default: []`), or pass a value at each level. See
    [Avoid recursive defaults](cookbook.html#avoid-recursive-defaults).
  - `assocs:` is evaluated at build time, like the body, and the factory's `params` variable is not
    in scope there. The declaration is validated when the factory first builds.
  - `assoc/3,4` and `assoc_list/3,4` apply the same rules to one key, for helper functions and
    values computed in the body (without `required:` or the schema check). They return the
    resolved value without changing the params, so put it back (or drop the key) before the final
    merge.

  ## Params Functions

  For struct factories, `build_*_params` and `build_*_string_params` build the struct and convert
  it to a clean map for changesets or controller tests. For Ecto schemas, Ecto metadata,
  autogenerated IDs, and unloaded associations are removed; plain structs are converted with
  `Map.from_struct/1`:

  ```elixir
  build_user_params(%{username: "alice"})         # %{username: "alice", first_name: nil, ...}
  build_user_string_params(%{username: "alice"})  # %{"username" => "alice", ...}
  ```

  Fields whose value is `nil` are kept, so a changeset test sees a `nil` field as given, not as
  absent; `nil` embeds are omitted. `belongs_to` associations are removed, and their foreign key is
  set when the associated record is persisted. Struct values such as `DateTime` are left untouched.

  ## Factory Options

  Options cascade: parent module -> child module -> individual factory.

  **Module-level** (set with `use FactoryMan`): `:repo`, `:extends` (the parent factory module),
  `:hooks`, `:insert`, `:insert_via`, `:disable`, `:body`, `:strict`, and `:struct`.

  **Factory-level** (set with `deffactory`):

  - `:struct` - The struct or Ecto schema to build (enables struct, params, and insert functions)
  - `:body` - What the body returns: `:params` (default) or `:struct`. Ignored for non-struct
    factories.
  - `:assocs` - Association builders (see Associations). Factory-level only.
  - `:strict` - `true`, `false`, or `[allow: [...]]` (see Strict Params). Ignored for non-struct
    factories.
  - `:hooks` - Chained with the module's hooks (see Hooks)
  - `:repo` - Overrides the module's repo
  - `:insert` and `:insert_via` - The default and named insert targets (see Insert Targets)
  - `:disable` - Function families to switch off (see Disabling function families)

  **Variant-level** (set with `defvariant`): `:for`, `:as`, `:extends`, and `:assocs` (see Variant
  Factories). Unknown options raise at every level.

  ## Insert Targets

  An insert target is the function that inserts a built struct. The default target, set with
  `insert:`, is used by `insert_*`, `insert_*_list`, and `insert_*_struct`:

  - `:ecto` (the default) - the repo's `insert!/2`. Generated for a table-backed Ecto schema when
    a repo is configured; otherwise nothing is generated. Written on a factory that cannot be
    inserted with Ecto, it raises.
  - `false` - no default insert functions.
  - A remote capture of arity 2, such as `&MyApp.Factory.put!/2` - generated for any struct
    factory: plain structs, embedded schemas, and Ecto schemas. Anonymous functions and local
    captures raise.

  `insert_via:` adds named targets, each with its own family of functions:

  ```elixir
  use FactoryMan, repo: MyApp.Repo, insert_via: [search: &MyApp.Factory.index!/2]

  deffactory user(params \\\\ %{}), struct: User do
    Map.merge(%{username: FactoryMan.sequence("user")}, params)
  end

  insert_user()                        # MyApp.Repo.insert!/2, with the insert hooks
  insert_user_via_search()             # MyApp.Factory.index!/2
  insert_user_via_search_list(3)
  insert_user_struct_via_search(user)
  ```

  An insert function receives the built struct and the caller's options (without `:variants`),
  and returns the inserted struct. A store that takes no options ignores them:
  `def index!(struct, _opts)`.

  - `insert:` and `insert_via:` cascade like other options. `insert_via:` merges by name: a lower
    level adds a target, replaces the inherited target of the same name, or removes it with
    `name: false` (removing a target that is not inherited raises). The name `ecto` is reserved.
  - `insert: false` removes the default family only; `insert_via:` targets remain.
    `disable: [insert_list: true]` removes the list functions of both.
  - The insert hooks (`before_insert`, `after_insert`) run for the default target, not for
    `insert_via:` targets. A target that needs more steps does them in its own function.
  - Captures and targets do not run the `:ecto` insert's already-inserted check (see Hook
    Pipeline).
  - A target receives the struct with any built associations still in place. The `:ecto` insert
    cascades them; a capture or target stores them only if its function does. An
    `after_build_struct` hook applies to every family.
  - Variants get their base factory's targets, building through the variant.
  - Both options apply to struct factories only: written on a non-struct factory they raise, and
    inherited ones are ignored.

  The [Cookbook](cookbook.html#insert-into-other-stores) has recipes for inserting into other
  stores.

  ## Strict Params

  `strict: true` catches params that a factory silently ignores. It runs two checks:

  1. **Unknown keys**, when building starts (before hooks and the body): every key must be a key
     of the `:struct` option's struct, which includes virtual fields and association keys.
  2. **Ignored or changed params**, after the body and its lazy values (before
     `after_build_params`): every field in the params that entered the body (after
     `before_build_params` and `assocs:`) must come out of the body with the same value, compared
     with `==`. A plain map has been kept when each of its keys has been kept, including when the
     body builds a struct such as an embed from it. Function values and association keys are not
     checked.

  ```elixir
  deffactory user(params \\\\ %{}), struct: User, strict: true do
    %{username: "default"}
  end

  build_user_struct(%{username: "alice"})
  # ** (ArgumentError) strict factory :user in MyApp.Factory ignored or changed params it was given:
  #
  #      :username - given "alice", built "default"
  #    ...
  ```

  Both checks cover every derived function. The second check runs in the base factory's body, so
  it sees what the variants pass on; a variant body that drops a caller's key is not checked.

  `strict: [allow: [...]]` exempts keys from both checks: a key that is not a field may be passed
  (e.g. an input used only to derive other fields), and a field may be changed by the body:

  ```elixir
  deffactory invoice(params \\\\ %{}), struct: Invoice, strict: [allow: [:line_item_count]] do
    {count, params} = Map.pop(params, :line_item_count, 1)

    Map.merge(%{total: count * 100}, params)
  end
  ```

  Set it once in a base factory (`use FactoryMan, strict: true`); a factory can override it. It is
  ignored for non-struct factories.

  ## Hooks

  Hooks transform data at specific stages. Every stage has a `before` and an `after` hook.

  ### Hook Pipeline

  ```text
  build_user_struct:
    params validation → before_build_params → assocs: resolution
    → [factory body + lazy eval] → strict params check → after_build_params
    → before_build_struct → struct!() → after_build_struct

  build_user_params (calls build_user_struct internally):
    → strip Ecto metadata (or Map.from_struct/1 for plain structs)

  insert_user (calls build_user_struct internally):
    → before_insert → Repo.insert!() → after_insert
  ```

  - The insert hooks belong to the default insert target's functions (`insert_*`,
    `insert_*_list`, and `insert_*_struct`). `insert_via:` targets run no hooks.
  - With `body: :struct`, the params-stage hooks (`before_build_params`, `after_build_params`, and
    `before_build_struct`) are skipped; `assocs:` are resolved after params validation, and the
    returned struct is lazily evaluated.
  - For non-struct factories, `build_*` runs `before_build_params`, the body with lazy evaluation,
    then `after_build_params`.
  - `insert_user_struct/1,2` runs the insert pipeline on an already-built struct (it does not
    resolve associations). Use it after modifying a built struct, so records are shaped the same
    way however they were built; a raw `Repo.insert!/2` skips the insert hooks. With the `:ecto`
    insert, it raises on a struct that has already been inserted (or deleted). To insert a copy on
    purpose, mark it as built first: `Ecto.put_meta(struct, state: :built)`.

  ### Hook Reference

  | Hook                   | Receives     | Returns      | When to Use                                                     |
  | ---------------------- | ------------ | ------------ | --------------------------------------------------------------- |
  | `:before_build_params` | params (map) | params (map) | Transform or inject params before the factory body runs         |
  | `:after_build_params`  | params (map) | params (map) | Modify params after the factory body (e.g. add computed fields) |
  | `:before_build_struct` | params (map) | params (map) | Last chance to modify params before `struct!()` is called       |
  | `:after_build_struct`  | struct       | struct       | Transform the struct after creation (e.g. set virtual fields)   |
  | `:before_insert`       | struct       | struct       | Modify the struct just before it is inserted                    |
  | `:after_insert`        | struct       | struct       | Post-process after insertion (e.g. reset associations)          |

  A hook is a 1-arity remote capture such as `&__MODULE__.my_hook/1`, or a list of them, run in
  order (`after_insert: [&M.reset/1, &M.log/1]`). Hooks are compiled into the generated functions,
  so anything else, such as an anonymous function, raises at compile time. See the
  [Cookbook](cookbook.html#use-hooks-for-cross-cutting-behavior) for recipes.

  ### Hook Order

  Hooks can be set at three levels, and a hook set at a lower level is chained with the hooks it
  inherits instead of replacing them:

  1. **Parent module** - `use FactoryMan, hooks: [...]`
  2. **Child module** - `use FactoryMan, extends: Parent, hooks: [...]` (any number of levels)
  3. **Individual factory** - `deffactory name(params), hooks: [...]`

  The order is onion-style, like middleware: the parent wraps the child. For a `before_*` hook
  the parent's runs first, and for an `after_*` hook the parent's runs last.

  To place a hook (or a list of hooks) explicitly, pass `{hook, placement}`:

  | Placement         | Runs                                  | Default for       |
  | ----------------- | ------------------------------------- | ----------------- |
  | `:after_parent`   | After the inherited hooks             | `before_*` hooks  |
  | `:before_parent`  | Before the inherited hooks            | `after_*` hooks   |
  | `:replace_parent` | Instead of all of the inherited hooks | -                 |

  "Parent" means everything inherited for that hook name, from every level above. Each level is
  resolved against the list built so far. For example, with `after_insert`:

  ```elixir
  # Parent module:       after_insert: &P.hook/1                      -> [P]
  # Child module:        after_insert: {&C.hook/1, :after_parent}     -> [P, C]
  # Factory:             after_insert: &F.hook/1                      -> [F, P, C]
  ```

  Each hook receives the previous hook's result. The same hook set at two levels runs twice. On a
  module with no parent, a placement behaves like a plain hook. To switch off the inherited hooks
  for one factory, use `hooks: [after_insert: {[], :replace_parent}]`; an empty list with any
  other placement raises. Unknown hook names and a hook name set twice at one level raise.

  ## Factory Inheritance

  A child module inherits its parent's options (repo, hooks, insert targets, `strict:`, ...) and
  can call the parent's helper functions unqualified (here, a `generate_username/0` defined in
  `MyApp.Factory`). Chains can be any length:

  ```elixir
  defmodule MyApp.Factory.Accounts do
    use FactoryMan, extends: MyApp.Factory

    deffactory user(params \\\\ %{}), struct: User do
      Map.merge(%{username: generate_username()}, params)
    end
  end
  ```

  ## Variant Factories (`defvariant`)

  A variant is a preprocessor for a base factory: its body runs first, on the caller's params,
  and passes the result to the base factory:

  ```elixir
  defvariant admin(params \\\\ %{}), for: :user do
    Map.merge(%{role: "admin"}, params)
  end

  build_admin_user_struct()   # same as build_user_struct(%{role: "admin"})
  ```

  - Its functions are named `{variant}_{base}` (`build_admin_user_struct`, `insert_admin_user`,
    ...), with the base factory's full family. `as: :mod` renames them (`build_mod_struct`); the
    variant is still listed as `:admin` in `variants:` and `extends:`.
  - `for:` must name a factory. A variant is defined after its base factory, in the same module,
    and variant names are unique per factory.
  - Params last (`Map.merge(%{role: "admin"}, params)`) makes the variant's values defaults, which
    the caller can override. Params first (`Map.merge(params, %{banned: true})`) forces them: they
    win over the caller and over later variants. See
    [Choose defaults or forced values](cookbook.html#choose-defaults-or-forced-values).

  ### Combining variants with `variants:`

  Every generated function of a factory takes a `variants:` option, which applies several
  variants in one build:

  ```elixir
  build_user_struct(%{}, variants: [:admin, :confirmed])
  insert_user(%{}, variants: [:admin], returning: true)
  ```

  List variants by their `defvariant` name (`:admin`, not `:admin_user`). For variants that merge
  params last, the caller's params win, then a later variant wins over an earlier one. The chain
  runs from the last variant to the base factory, so a later variant's values reach an earlier one
  as params. A variant's own functions count the variant as the first in the list:
  `build_admin_user_struct(params, variants: [:confirmed])` is
  `build_user_struct(params, variants: [:admin, :confirmed])`. An unknown variant name raises and
  lists the known variants.

  ### Building on other variants with `extends:`

  A variant builds on other variants of the same factory with `extends:`, and wins over them:

  ```elixir
  defvariant senior(params \\\\ %{}), for: :user, extends: [:admin] do
    Map.merge(%{title: "Senior admin"}, params)
  end
  ```

  A listed variant brings the variants it extends, and each variant is applied once, at its first
  position in the list, so a variant wins over the variants it extends whatever the list order. A
  variant is defined after the variants it extends. A variant whose body is just `params` gives a
  recurring combination a name.

  ## Sequences

  ```elixir
  FactoryMan.sequence("user")                                          # "user0", "user1", ...
  FactoryMan.sequence(:email, fn n -> "user\#{n}@example.com" end)     # custom formatter
  FactoryMan.sequence(:role, ["admin", "moderator", "user"])           # cycles through list
  FactoryMan.sequence(:order, fn n -> "ORD-\#{n}" end, start_at: 1000) # custom start value
  ```

  `FactoryMan.Sequence.reset/0` clears every counter, for every test. Tests that run at the same
  time share the counters, so in async tests reset only the sequence names that test uses:
  `FactoryMan.Sequence.reset(:invoice_number)`.

  ## Lazy Evaluation

  Functions in a body's map or keyword list are evaluated at build time. Other values are passed
  through unchanged:

  ```elixir
  %{
    created_at: fn -> DateTime.utc_now() end,               # 0-arity: called with no args
    display_name: fn user -> "\#{user.username} (User)" end # 1-arity: receives the parent map
  }
  ```

  > #### Lazy evaluation ordering {: .warning}
  >
  > Lazy values are resolved in two passes: the 0-arity functions first, then the 1-arity ones.
  > A 1-arity function therefore sees plain values and resolved 0-arity values, but not another
  > 1-arity field, which is still a function reference when it runs.

  ## Embedded Schemas

  A factory for an embedded schema generates the struct and params builders. It has no table, so
  it gets insert functions only from an `insert:` capture or `insert_via:` targets:

  ```elixir
  deffactory settings(params \\\\ %{}), struct: MyApp.Users.Settings do
    Map.merge(%{theme: "dark", notifications: true}, params)
  end
  ```

  ## Direct Struct Factories (`body: :struct`)

  With `body: :struct`, the body returns the struct itself, for factories that need full control
  over construction. The full function family is still generated, including `build_*_params`, and
  lazy values in the struct are resolved. It can be set at the module level and overridden per
  factory:

  ```elixir
  deffactory invoice(params \\\\ %{}), struct: Invoice, body: :struct do
    %Invoice{total: Map.get(params, :total, 100), customer: build_customer_struct()}
  end
  ```

  ## Cookbook

  The [Cookbook](cookbook.html) is a practical progression from a first factory through realistic
  defaults, variants, associations, suite organization, hooks, strict params, insert targets, and
  advanced presets.

  ## Reflection and Debugging

  Every factory module gets a `__factory_man__/1,2` reflection function:

  ```elixir
  iex> MyApp.Factory.__factory_man__(:opts)
  [disable: [], insert_via: [], insert: :ecto, repo: MyApp.Repo]

  iex> MyApp.Factories.Users.__factory_man__(:opts, :user)
  [disable: [], insert_via: [], insert: :ecto, repo: MyApp.Repo, struct: User]

  iex> MyApp.Factories.Users.__factory_man__(:factories)
  [:user, :admin_user]

  iex> MyApp.Factories.Users.__factory_man__(:variants, :user)
  [:admin]
  ```

  - `:opts` shows the resolved options, including each hook name's list in run order, the
    resolved `insert:` and `insert_via:`, and the disabled families (`disable:`). `assocs:` is code evaluated at build time, so it does not
    appear.
  - `:factories` lists every factory and variant in the module (variants under their full name),
    for runtime dispatch without building function names from strings.
  - `:variants` lists a factory's variants by the names that `variants:` and `extends:` accept.
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

      # One `{factory, variant, full_name, chain}` entry per variant. `chain` lists the full names
      # of the variants it runs, the variants it extends first.
      Module.register_attribute(__MODULE__, :factory_man_variant_defs, accumulate: true)

      # One `{{name, arity}, source}` entry per generated function, to name both sources when two
      # would share a name
      Module.register_attribute(__MODULE__, :factory_man_generated, accumulate: true)

      parent_opts =
        case unquote(opts)[:extends] do
          nil -> []
          extends -> extends.__info__(:attributes)[:parent_factory_opts] || []
        end

      # Resolved against an empty parent for a root module too, so every module stores its hooks
      # as lists of functions in run order
      parent_factory_opts =
        FactoryMan._merge_opts(
          parent_opts,
          unquote(opts),
          "use FactoryMan in #{inspect(__MODULE__)}"
        )

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
      - `__factory_man__(:variants, factory_name)` - the names of a factory's variants, as
        accepted by the `variants:` option, in definition order
      """
      def __factory_man__(:opts), do: @parent_factory_opts

      @factory_man_names @factory_man_registry |> Enum.map(&elem(&1, 0)) |> Enum.reverse()
      def __factory_man__(:factories), do: @factory_man_names

      for {factory_man_name, factory_man_opts} <- @factory_man_registry do
        def __factory_man__(:opts, unquote(factory_man_name)), do: unquote(factory_man_opts)
      end

      @factory_man_variants Enum.reverse(@factory_man_variant_defs)
      @factory_man_variant_full_names Enum.map(@factory_man_variants, &elem(&1, 2))

      for factory_man_name <- @factory_man_names,
          factory_man_name not in @factory_man_variant_full_names do
        def __factory_man__(:variants, unquote(factory_man_name)) do
          unquote(for {^factory_man_name, variant, _, _} <- @factory_man_variants, do: variant)
        end
      end

      # Maps a variant name to the steps of its chain. The generated functions look up the
      # `variants:` option here at runtime.
      if @factory_man_names != [] do
        for {factory_man_factory, factory_man_variant, _, factory_man_chain} <-
              @factory_man_variants do
          defp __factory_man_variant_chain__(
                 unquote(factory_man_factory),
                 unquote(factory_man_variant)
               ) do
            unquote(FactoryMan._chain_steps_ast(factory_man_chain))
          end
        end

        defp __factory_man_variant_chain__(factory_name, variant_name) do
          FactoryMan._raise_unknown_variant!(__MODULE__, factory_name, variant_name)
        end
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
  - `:insert` - The default insert target: `:ecto` (default, the repo's `insert!/2`), `false`
    (no default insert functions), or a remote capture of arity 2 such as
    `&MyApp.Factory.put!/2`. Overrides the module-level value.
  - `:insert_via` - Named insert targets, each generating an `insert_*_via_<name>` family:
    `name: capture` adds or replaces a target, and `name: false` removes an inherited one.
  - `:disable` - Function families to switch off, as `family: true` (or `family: false` to
    enable an inherited one again). See Disabling function families in the module documentation.
  - `:body` - What the factory body returns: `:params` (default, a params map) or `:struct`
    (a struct built directly by the body). Params functions are generated either way (derived
    from the struct), and lazy values are resolved either way. Ignored for non-struct factories.
  - `:hooks` - A keyword list of hook functions to apply at different stages, chained with the
    module's hooks (see Hooks)
  - `:repo` - Overrides the module-level repo for this factory
  - `:assocs` - A keyword list mapping Ecto association keys to builders, resolved before the
    body. Requires an Ecto schema `struct:`. See Associations in the module documentation.
  - `:strict` - `true` raises on param keys that are not fields of the `:struct` option's struct,
    and on params the body ignores or changes. `[allow: [...]]` does the same, except for the
    listed keys (see Strict Params). Ignored for non-struct factories.

  ## Generated Functions

  A struct factory generates the `build_*_struct`, `build_*_params`, `build_*_string_params`, and
  insert families, and a factory without `struct:` generates `build_*` and `build_*_list`. See
  Generated Functions in the module documentation for the full list and the rules that decide
  which are generated.

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
        [:struct, :insert, :insert_via, :disable, :body, :hooks, :strict, :repo, :assocs],
        subject
      )

      FactoryMan._validate_hooks!(opts, subject)
      FactoryMan._validate_insert!(opts, subject)
      FactoryMan._validate_disable!(opts, subject)

      parent_factory_opts = Module.get_attribute(__MODULE__, :parent_factory_opts)

      merged_opts = FactoryMan._merge_opts(parent_factory_opts, opts, subject)

      source = {:factory, factory_name}

      FactoryMan._check_disable_kind!(opts, merged_opts[:struct] != nil, subject)

      disable = merged_opts[:disable]

      body = Keyword.get(merged_opts, :body, :params)

      if body not in [:params, :struct] do
        raise ArgumentError,
              "invalid :body option: #{inspect(body)}. Expected :params (default) or :struct."
      end

      # Compile-time parse of :strict into `false` (disabled) or a list of allowed keys
      strict = FactoryMan._parse_strict!(Keyword.get(merged_opts, :strict, false))

      # A strict factory compares the params that enter the body against the body's result, so
      # the entering params are bound to a variable before the body runs
      params_check =
        if strict do
          {Macro.var(:factory_man_entering_params, FactoryMan), strict, factory_name}
        end

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
        FactoryMan._reject_insert_opts!(opts, subject)

        build_fn = :"build_#{factory_name}"

        FactoryMan.Codegen.claim_head!(__MODULE__, build_fn, head_ast, source)

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

        FactoryMan.Codegen.define(
          FactoryMan.Codegen.variants_fn(build_fn, factory_name, factory_name, [], build_fn),
          __ENV__,
          source
        )

        if not FactoryMan._disabled?(disable, :non_struct_list) do
          FactoryMan.Codegen.define(
            FactoryMan.Codegen.value_list_fns(build_fn, :"#{build_fn}_list", projections),
            __ENV__,
            source
          )
        end
      end

      if merged_opts[:struct] != nil do
        build_struct_fn = :"build_#{factory_name}_struct"

        FactoryMan.Codegen.claim_head!(__MODULE__, build_struct_fn, head_ast, source)

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

              unquote(FactoryMan.Codegen.bind_entering_params(params_check, user_var))

              unquote(
                FactoryMan.Codegen.build_struct_pipeline(
                  block,
                  hooks,
                  merged_opts[:struct],
                  params_check
                )
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

              unquote(FactoryMan.Codegen.bind_entering_params(params_check, user_var))

              unquote(
                quote(do: FactoryMan.evaluate_lazy_attributes(unquote(block)))
                |> FactoryMan.Codegen.check_params_used(params_check, merged_opts[:struct])
                |> FactoryMan.Codegen.hook_pipe(hooks, :after_build_struct)
              )
            end)
          end
        end

        FactoryMan.Codegen.define(
          FactoryMan.Codegen.variants_fn(
            build_struct_fn,
            factory_name,
            factory_name,
            [],
            build_struct_fn
          ),
          __ENV__,
          source
        )

        if not FactoryMan._disabled?(disable, :struct_list) do
          FactoryMan.Codegen.define(
            FactoryMan.Codegen.map_list_fns(
              build_struct_fn,
              :"#{build_struct_fn}_list",
              projections
            ),
            __ENV__,
            source
          )
        end

        struct_module = merged_opts[:struct]

        # Generate build_*_params and build_*_string_params, derived from the built struct
        FactoryMan.Codegen.define(
          FactoryMan.Codegen.params_fns(
            factory_name,
            projections,
            FactoryMan.Codegen.ecto_schema?(struct_module),
            disable
          ),
          __ENV__,
          source
        )

        # The default target (`insert:`) generates the `insert_*` family, which runs the insert
        # hooks. Each named target (`insert_via:`) generates an `insert_*_via_<target>` family,
        # which calls the target's function without hooks. The insert itself lives in
        # insert_*_struct; insert_* only adds the build step in front of it.
        for {target_name, target} <-
              FactoryMan._insert_targets!(opts, merged_opts, subject) do
          {insert_fn, insert_struct_fn} =
            FactoryMan.Codegen.insert_names(factory_name, target_name)

          FactoryMan.Codegen.define(
            FactoryMan.Codegen.insert_fns(
              insert_fn,
              build_struct_fn,
              insert_struct_fn,
              target,
              projections,
              not FactoryMan._disabled?(disable, :insert_list)
            ),
            __ENV__,
            source
          )

          FactoryMan.Codegen.define(
            FactoryMan.Codegen.insert_struct_fns(
              insert_struct_fn,
              insert_fn,
              struct_module,
              target,
              if(is_nil(target_name), do: hooks, else: []),
              FactoryMan.Codegen.insert_struct_doc(
                struct_module,
                target,
                factory_name,
                is_nil(target_name)
              )
            ),
            __ENV__,
            source
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

      # Generated: build_admin_user_struct/0,1,2, insert_admin_user/0,1,2, etc.
      # Calling build_admin_user_struct() is equivalent to:
      #   build_user_struct(%{role: "admin"})

  ## Options

  - `:for` - (atom, required) The name of the base factory to wrap (e.g. `:user`). It must name
  a factory; a variant builds on other variants with `:extends`.

  - `:extends` - A list of variants of the same factory to build on (e.g. `extends: [:admin]`).
  They run before this variant's body, so this variant wins over them. Each must be defined
  earlier in the module.

  - `:as` - Instead of the default `<variant>_<base>` structure used when generating factory
  functions, (e.g. `build_admin_user_struct`), you may specify a custom name to use when
  generating the factory functions (e.g. `as: :admin` -> `build_admin_struct`)

  - `:assocs` - Association builders resolved before the variant body, with the same shape as
  the `deffactory` option. The base factory reuses the resolved structs, so a variant can build
  an association differently from its base. Requires a base factory with an Ecto schema `struct:`.
  The base still enforces its own `required: true`, so a variant can add `required:` to a key but
  cannot relax it: a variant `default: nil` on a key the base requires raises on every default
  build.

  Variants are listed by their name (e.g. `:admin`) in `extends:` and in the `variants:` option
  of the generated functions (see Variant Factories in the module documentation).
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

    _validate_opts!(opts, [:for, :as, :assocs, :extends], "defvariant #{variant_name}")
    {assocs_ast, opts} = pop_assocs(opts)

    base_factory_name =
      opts[:for] ||
        raise ArgumentError,
              "defvariant #{variant_name} requires the :for option, naming its base factory " <>
                "(e.g. `for: :user`)"

    as_name = opts[:as]
    extends = Keyword.get(opts, :extends, [])

    unless is_list(extends) and Enum.all?(extends, &is_atom/1) do
      raise ArgumentError,
            "defvariant #{variant_name}: extends: must be a list of variant names, " <>
              "got: #{inspect(extends)}"
    end

    caller_module = __CALLER__.module

    quote bind_quoted: [
            variant_name: variant_name,
            base_factory_name: base_factory_name,
            as_name: as_name,
            extends: extends,
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
      # A variant builds on a factory; it builds on other variants with `extends:`
      FactoryMan._validate_variant!(
        @factory_man_variant_defs,
        base_factory_name,
        variant_name,
        extends
      )

      # Look up the base factory's registered metadata
      base_entry =
        @factory_man_registry
        |> Enum.find(fn {name, _opts} -> name == base_factory_name end)

      if is_nil(base_entry) do
        raise ArgumentError,
              "defvariant #{variant_name}: base factory :#{base_factory_name} not found. " <>
                "Define deffactory #{base_factory_name}(...) before this defvariant, in the same " <>
                "module (a variant cannot be defined in another module than its base factory)."
      end

      {_base_name, base_opts} = base_entry

      source = {:variant, variant_name, base_factory_name}

      disable = base_opts[:disable]

      # Variant function names combine variant + base: e.g. :admin + :user = :admin_user
      # The :as option overrides this combined name.
      full_name = as_name || :"#{variant_name}_#{base_factory_name}"

      @factory_man_variant_defs {
        base_factory_name,
        variant_name,
        full_name,
        FactoryMan._variant_chain(@factory_man_variant_defs, base_factory_name, extends) ++
          [full_name]
      }

      # A variant's associations resolve before the variant body. The base factory then reuses
      # the resolved structs, and runs its own strict check after every variant body.
      association_step =
        FactoryMan._association_step(
          assocs_ast,
          user_var,
          base_opts[:struct],
          caller_module,
          full_name
        )

      if association_step do
        defp unquote(FactoryMan._assocs_fn(full_name))(), do: unquote(assocs_ast)
      end

      # The variant's step (its associations, then its body) returns the params for the next
      # step. Every chain that includes the variant runs this step.
      defp unquote(FactoryMan._variant_step_fn(full_name))(unquote(arg_ast_no_default)) do
        unquote(association_step)

        unquote(block)
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

        FactoryMan.Codegen.claim_head!(__MODULE__, build_fn, head_ast, source)

        @doc "Builds a value from the `:#{variant_name}` variant of the `:#{base_factory_name}` factory."
        def unquote({build_fn, [], [head_ast]})

        def unquote(build_fn)(unquote(plain_var_ast)) do
          unquote(build_fn)(unquote(user_var), [])
        end

        FactoryMan.Codegen.define(
          FactoryMan.Codegen.variants_fn(
            build_fn,
            full_name,
            base_factory_name,
            [variant_name],
            :"build_#{base_factory_name}"
          ),
          __ENV__,
          source
        )

        if not FactoryMan._disabled?(disable, :non_struct_list) do
          FactoryMan.Codegen.define(
            FactoryMan.Codegen.value_list_fns(build_fn, :"#{build_fn}_list", projections),
            __ENV__,
            source
          )
        end
      end

      # Generate struct builder variant (if base factory has struct)
      if base_opts[:struct] != nil do
        build_struct_fn = :"build_#{full_name}_struct"

        FactoryMan.Codegen.claim_head!(__MODULE__, build_struct_fn, head_ast, source)

        @doc "Builds a `#{inspect(base_opts[:struct])}` struct from the `:#{variant_name}` variant of the `:#{base_factory_name}` factory (in memory, not persisted)."
        def unquote({build_struct_fn, [], [head_ast]})

        def unquote(build_struct_fn)(unquote(plain_var_ast)) do
          unquote(build_struct_fn)(unquote(user_var), [])
        end

        FactoryMan.Codegen.define(
          FactoryMan.Codegen.variants_fn(
            build_struct_fn,
            full_name,
            base_factory_name,
            [variant_name],
            :"build_#{base_factory_name}_struct"
          ),
          __ENV__,
          source
        )

        if not FactoryMan._disabled?(disable, :struct_list) do
          FactoryMan.Codegen.define(
            FactoryMan.Codegen.map_list_fns(
              build_struct_fn,
              :"#{build_struct_fn}_list",
              projections
            ),
            __ENV__,
            source
          )
        end

        struct_module = base_opts[:struct]

        # Generate build_*_params and build_*_string_params, derived from the variant's struct
        FactoryMan.Codegen.define(
          FactoryMan.Codegen.params_fns(
            full_name,
            projections,
            FactoryMan.Codegen.ecto_schema?(struct_module),
            disable
          ),
          __ENV__,
          source
        )

        # The variant's insert families build through the variant, then insert through the base
        # factory's insert_*_struct functions (its targets, hooks, and repo)
        for {target_name, target} <- FactoryMan._insert_targets!([], base_opts, nil) do
          {insert_fn, insert_struct_fn} = FactoryMan.Codegen.insert_names(full_name, target_name)

          {_base_insert_fn, base_insert_struct_fn} =
            FactoryMan.Codegen.insert_names(base_factory_name, target_name)

          FactoryMan.Codegen.define(
            FactoryMan.Codegen.insert_fns(
              insert_fn,
              build_struct_fn,
              base_insert_struct_fn,
              target,
              projections,
              not FactoryMan._disabled?(disable, :insert_list)
            ),
            __ENV__,
            source
          )

          FactoryMan.Codegen.define(
            FactoryMan.Codegen.insert_struct_delegate_fns(
              insert_struct_fn,
              insert_fn,
              struct_module,
              target,
              base_insert_struct_fn,
              FactoryMan.Codegen.insert_struct_doc(
                struct_module,
                target,
                base_factory_name,
                is_nil(target_name)
              )
            ),
            __ENV__,
            source
          )
        end
      end

      # Register the variant under its full name. The base factory's opts describe the variant's
      # generated functions accurately, since variants delegate to the base pipeline.
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

  @doc false
  def _variant_step_fn(full_name), do: :"__factory_man_variant_step_#{full_name}__"

  # Checks `for:` and `extends:` against the variants defined so far (`defs`, newest first)
  @doc false
  def _validate_variant!(defs, factory_name, variant_name, extends) do
    subject = "defvariant #{variant_name}"

    case Enum.find(defs, &(elem(&1, 2) == factory_name)) do
      {factory, name, _full_name, _chain} ->
        raise ArgumentError,
              "#{subject}: for: must name a factory, and #{inspect(factory_name)} is a variant. " <>
                "Build on it with for: #{inspect(factory)}, extends: [#{inspect(name)}]"

      nil ->
        :ok
    end

    known = for {^factory_name, name, _, _} <- Enum.reverse(defs), do: name

    if variant_name in known do
      raise ArgumentError,
            "#{subject}: factory #{inspect(factory_name)} already has a variant named " <>
              "#{inspect(variant_name)}"
    end

    case extends -- known do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "#{subject}: unknown variants #{inspect(unknown)} in extends: for factory " <>
                "#{inspect(factory_name)}. Known variants: #{inspect(known)}. A variant must be " <>
                "defined before the variants that extend it."
    end
  end

  # The full names of the variants that `variant_names` run, in order. Each name brings the
  # variants it extends first, and each variant appears once, where it first appears, so a
  # variant always comes after the variants it extends.
  @doc false
  def _variant_chain(defs, factory_name, variant_names) do
    variant_names
    |> Enum.flat_map(fn variant_name ->
      Enum.find_value(defs, fn
        {^factory_name, ^variant_name, _full_name, chain} -> chain
        _ -> nil
      end)
    end)
    |> Enum.uniq()
  end

  @doc false
  def _chain_steps_ast(chain) do
    for full_name <- chain do
      step = Macro.var(_variant_step_fn(full_name), nil)

      quote do: {unquote(full_name), &(unquote(step) / 1)}
    end
  end

  @doc false
  def _raise_unknown_variant!(module, factory_name, variant_name) do
    raise ArgumentError,
          "unknown variant #{inspect(variant_name)} for factory #{inspect(factory_name)} in " <>
            "#{inspect(module)}. Known variants: " <>
            "#{inspect(module.__factory_man__(:variants, factory_name))}. List a variant by the " <>
            "name in its defvariant (e.g. :admin), not by its generated function name."
  end

  # Runs the steps of the named variants, then the base factory's builder. A variant's body
  # merges its defaults under the params it receives, so the last variant runs first: its values
  # reach the earlier variants as params, and win.
  @doc false
  def _build_with_variants(_module, _name, _root, [], params, _chain_fun, base_fun) do
    base_fun.(params)
  end

  def _build_with_variants(module, name, root, variant_names, params, chain_fun, base_fun) do
    steps =
      variant_names
      |> Enum.flat_map(&chain_fun.(root, &1))
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.reverse()

    FactoryMan.Associations.track_factory(module, name, root, fn ->
      steps
      |> Enum.reduce(params, fn {_full_name, step}, params -> step.(params) end)
      |> base_fun.()
    end)
  end

  @doc false
  def _variants_opt!(opts, function) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError,
            "expected options for #{function} to be a keyword list, got: #{inspect(opts)}"
    end

    case Keyword.keys(opts) -- [:variants] do
      [] ->
        opts |> Keyword.get(:variants, []) |> validate_variant_names!(function)

      unknown ->
        raise ArgumentError,
              "unknown options #{inspect(unknown)} for #{function}. Allowed options: [:variants]"
    end
  end

  # `insert_*` takes one option list: `:variants` is FactoryMan's, and the rest belong to the repo
  @doc false
  def _pop_variants!(opts, function) do
    {variants, repo_insert_opts} = Keyword.pop(opts, :variants, [])

    {validate_variant_names!(variants, function), repo_insert_opts}
  end

  defp validate_variant_names!(variants, function) do
    if is_list(variants) and Enum.all?(variants, &is_atom/1) do
      variants
    else
      raise ArgumentError,
            "expected variants: for #{function} to be a list of variant names, " <>
              "got: #{inspect(variants)}"
    end
  end

  @doc false
  def _reject_struct_variants!(insert_opts, insert_struct_function, insert_function) do
    if Keyword.has_key?(insert_opts, :variants) do
      raise ArgumentError,
            "#{insert_struct_function} inserts a struct that has already been built, so it does " <>
              "not take variants:. Use #{insert_function} to build with variants and insert."
    end
  end

  @doc false
  def _ensure_not_inserted!(struct, insert_struct_function) do
    case struct.__meta__.state do
      :built ->
        struct

      state ->
        raise ArgumentError,
              "#{insert_struct_function} expects a struct that has not been inserted, got a " <>
                "%#{inspect(struct.__struct__)}{} whose Ecto metadata state is #{inspect(state)}. " <>
                "To insert it again on purpose (e.g. into another prefix), mark it as built " <>
                "first: Ecto.put_meta(struct, state: :built)"
    end
  end

  # The insert targets a struct factory generates functions for, as `{target_name, target}`:
  # `nil` names the default target (`insert:`), which is `{:ecto, repo}` or a capture, and the
  # `insert_via:` targets follow. `own_opts` are the options written on the factory itself, since
  # only an explicit `insert: :ecto` raises when it cannot generate anything.
  @doc false
  def _insert_targets!(own_opts, merged_opts, subject) do
    default_target =
      case Keyword.fetch!(merged_opts, :insert) do
        false -> []
        :ecto -> ecto_target!(own_opts, merged_opts, subject)
        capture -> [{nil, capture}]
      end

    default_target ++ merged_opts[:insert_via]
  end

  defp ecto_target!(own_opts, merged_opts, subject) do
    struct_module = merged_opts[:struct]
    repo = merged_opts[:repo]

    reason =
      cond do
        not FactoryMan.Codegen.ecto_schema?(struct_module) -> "it is not an Ecto schema"
        struct_module.__schema__(:source) == nil -> "it is an embedded schema"
        is_nil(repo) -> "no repo is configured"
        true -> nil
      end

    cond do
      is_nil(reason) ->
        [{nil, {:ecto, repo}}]

      own_opts[:insert] == :ecto ->
        raise ArgumentError,
              "#{subject} sets insert: :ecto, but it cannot be inserted with Ecto (#{reason}). " <>
                "Set a repo, use insert: false, or pass a capture."

      true ->
        []
    end
  end

  # Only struct factories have insert functions, so insert options written on a non-struct
  # factory are a mistake. Inherited ones are ignored, like `body:` and `strict:`.
  @doc false
  def _reject_insert_opts!(own_opts, subject) do
    case Enum.find([:insert, :insert_via], &Keyword.has_key?(own_opts, &1)) do
      nil ->
        :ok

      option ->
        raise ArgumentError,
              "#{subject} sets #{option}:, but only struct factories have insert functions."
    end
  end

  # Two generated functions with one name and arity would silently merge into one function, so
  # every generated function claims its name first. `Module.defines?/2` also catches a
  # hand-written function defined earlier in the module.
  @doc false
  def _claim_names!(module, names, source) do
    for name_arity <- names, Module.defines?(module, name_arity) do
      {name, arity} = name_arity
      generated = Module.get_attribute(module, :factory_man_generated)

      message =
        case List.keyfind(generated, name_arity, 0) do
          {_name_arity, other_source} ->
            "#{describe_source(other_source)} and #{describe_source(source)} in " <>
              "#{inspect(module)} both generate #{name}/#{arity}. Rename one" <>
              if(variant_source?(source) or variant_source?(other_source),
                do: ", or use as: on the variant.",
                else: "."
              )

          nil ->
            "#{describe_source(source)} in #{inspect(module)} generates #{name}/#{arity}, " <>
              "which is already defined in the module. Rename one."
        end

      raise ArgumentError, message
    end

    Enum.each(names, &Module.put_attribute(module, :factory_man_generated, {&1, source}))
  end

  defp describe_source({:factory, name}), do: "factory :#{name}"
  defp describe_source({:variant, variant, base}), do: "variant :#{variant} of :#{base}"

  defp variant_source?(source), do: match?({:variant, _variant, _base}, source)

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
    hint =
      cond do
        is_list(params) and Keyword.has_key?(params, :variants) ->
          " Options go in the second argument, after the params: (%{}, variants: [...])."

        is_list(params) and params != [] and Keyword.keyword?(params) ->
          " Struct factories take a map: pass %{...} instead of a keyword list."

        true ->
          ""
      end

    raise ArgumentError,
          "expected a params map for factory :#{factory_name}, got: #{inspect(params)}.#{hint}"
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
              "Allowed keys: #{inspect(Enum.sort(allowed))}. Fix the key, or list it in " <>
              "strict: [allow: [...]] if the factory uses it."
    end

    params
  end

  def _validate_params!(params, _strict, _struct_module, _factory_name), do: params

  # A strict factory's body must keep every field it receives: each field in the params that
  # entered the body must come out of it with the same value (see `kept?/2`). Function values,
  # which lazy evaluation replaces, and association keys, which a body may resolve imperatively,
  # are not checked.
  @doc false
  def _check_params_used!(result, entering, allow, struct_module, module, factory_name)
      when is_map(result) and is_map(entering) do
    skipped = allow ++ association_keys(struct_module)
    fields = Map.keys(struct_module.__struct__()) -- [:__struct__, :__meta__ | skipped]

    problems =
      entering
      |> Enum.filter(fn {key, value} -> key in fields and not is_function(value) end)
      |> Enum.flat_map(fn {key, value} ->
        case Map.fetch(result, key) do
          {:ok, built} -> if kept?(value, built), do: [], else: [{key, value, {:ok, built}}]
          :error -> [{key, value, :error}]
        end
      end)

    if problems != [] do
      details =
        problems
        |> Enum.sort()
        |> Enum.map_join("\n", fn
          {key, value, {:ok, built}} ->
            "  #{inspect(key)} - given #{inspect(value)}, built #{inspect(built)}"

          {key, value, :error} ->
            "  #{inspect(key)} - given #{inspect(value)}, missing from the result"
        end)

      raise ArgumentError, """
      strict factory #{inspect(factory_name)} in #{inspect(module)} ignored or changed params it was given:

      #{details}

      Merge params into the body's result (e.g. `Map.merge(base_params, params)`). If the factory \
      changes these keys on purpose, list them in `strict: [allow: [...]]`.\
      """
    end

    result
  end

  # `struct!/2` also accepts a keyword list, so a body may return one
  def _check_params_used!(result, entering, allow, struct_module, module, factory_name)
      when is_list(result) and is_map(entering) do
    if Keyword.keyword?(result),
      do:
        _check_params_used!(Map.new(result), entering, allow, struct_module, module, factory_name)

    result
  end

  def _check_params_used!(result, _entering, _allow, _struct_module, _module, _factory_name),
    do: result

  # A plain map from the caller has been kept when each of its keys has been kept, so a body may
  # add defaults to a map field, or build a struct (e.g. an embed) from it. Other values must be
  # equal (`==`).
  defp kept?(given, built) when is_map(given) and not is_struct(given) and is_map(built) do
    built = if is_struct(built), do: Map.from_struct(built), else: built

    Enum.all?(given, fn {key, value} ->
      case Map.fetch(built, key) do
        {:ok, built_value} -> kept?(value, built_value)
        :error -> false
      end
    end)
  end

  defp kept?(given, built), do: given == built

  defp association_keys(struct_module) do
    if function_exported?(struct_module, :__schema__, 1),
      do: struct_module.__schema__(:associations),
      else: []
  end

  # Parses `:strict` into `false` (disabled) or a list of allowed keys
  @doc false
  def _parse_strict!(false), do: false
  def _parse_strict!(true), do: []

  def _parse_strict!([allow: allow] = strict) when is_list(allow) do
    if Enum.all?(allow, &is_atom/1) do
      allow
    else
      raise ArgumentError,
            "invalid :strict option: #{inspect(strict)}. Allowed keys must be atoms."
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

    _validate_opts!(
      opts,
      [:repo, :extends, :hooks, :body, :strict, :insert, :insert_via, :disable, :struct],
      subject
    )

    _validate_hooks!(opts, subject)
    _validate_insert!(opts, subject)
    _validate_disable!(opts, subject)
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
    {funs, placement} = split_hook(hook_name, value)

    unless Enum.all?(
             funs,
             &(is_function(&1, 1) and Function.info(&1, :type) == {:type, :external})
           ) do
      raise ArgumentError,
            "invalid hook #{inspect(hook_name)} for #{subject}: #{inspect(value)}. " <>
              "Expected a 1-arity remote capture such as `&MyModule.my_hook/1`, a list of " <>
              "them, or either one as `{hooks, placement}`."
    end

    if placement not in @hook_placements do
      raise ArgumentError,
            "invalid placement #{inspect(placement)} for hook #{inspect(hook_name)} for " <>
              "#{subject}. Expected one of: #{inspect(@hook_placements)}."
    end

    # An empty list only has an effect when it replaces the inherited hooks
    if funs == [] and placement != :replace_parent do
      raise ArgumentError,
            "empty hook list for #{inspect(hook_name)} for #{subject} has no effect. " <>
              "To switch off the inherited hooks, use `{[], :replace_parent}`."
    end
  end

  # Normalizes a hook value into its list of functions and its placement
  defp split_hook(_hook_name, {funs, placement}) when is_list(funs), do: {funs, placement}
  defp split_hook(_hook_name, {fun, placement}), do: {[fun], placement}

  defp split_hook(hook_name, funs) when is_list(funs),
    do: {funs, Keyword.fetch!(@hook_default_placements, hook_name)}

  defp split_hook(hook_name, fun),
    do: {[fun], Keyword.fetch!(@hook_default_placements, hook_name)}

  # Insert functions are compiled into the generated functions as remote calls, like hooks, so
  # only remote captures of arity 2 are accepted
  @doc false
  def _validate_insert!(opts, subject) do
    case Keyword.fetch(opts, :insert) do
      {:ok, insert} when insert in [false, :ecto] ->
        :ok

      {:ok, insert} ->
        unless insert_capture?(insert) do
          raise ArgumentError,
                "invalid :insert option for #{subject}: #{inspect(insert)}. Expected false, " <>
                  ":ecto, or a remote capture of arity 2 (e.g. &MyApp.Factory.put!/2)."
        end

      :error ->
        :ok
    end

    targets = Keyword.get(opts, :insert_via, [])

    unless is_list(targets) and Keyword.keyword?(targets) do
      raise ArgumentError,
            "expected :insert_via for #{subject} to be a keyword list of target names and " <>
              "remote captures of arity 2, got: #{inspect(targets)}"
    end

    if Keyword.has_key?(targets, :ecto) do
      raise ArgumentError,
            "invalid insert_via: target :ecto for #{subject}. The name :ecto is reserved for the " <>
              "built-in Ecto insert. Use another name."
    end

    target_names = Keyword.keys(targets)

    case target_names -- Enum.uniq(target_names) do
      [] ->
        :ok

      duplicates ->
        raise ArgumentError,
              "duplicate insert_via: targets #{inspect(Enum.uniq(duplicates))} for #{subject}"
    end

    for {target_name, capture} <- targets, capture != false and not insert_capture?(capture) do
      raise ArgumentError,
            "invalid insert_via: target #{inspect(target_name)} for #{subject}: " <>
              "#{inspect(capture)}. Expected a remote capture of arity 2 (e.g. " <>
              "&MyApp.Factory.index!/2), or false to remove an inherited target."
    end

    :ok
  end

  # Each `disable:` key and the kind of factory it applies to. The struct family and the insert
  # functions are not keys: every other family builds on `build_*_struct`, and inserts are switched
  # off with `insert:` and `insert_via:`.
  @disable_keys [
    params: :struct,
    string_params: :struct,
    struct_list: :struct,
    params_list: :struct,
    string_params_list: :struct,
    insert_list: :struct,
    non_struct_list: :non_struct
  ]

  @doc false
  def _validate_disable!(opts, subject) do
    disable = Keyword.get(opts, :disable, [])

    unless is_list(disable) and Keyword.keyword?(disable) do
      raise ArgumentError,
            "expected :disable for #{subject} to be a keyword list of function families and " <>
              "booleans (e.g. disable: [string_params: true]), got: #{inspect(disable)}"
    end

    for {key, value} <- disable do
      cond do
        key == :struct ->
          raise ArgumentError,
                "invalid disable: key :struct for #{subject}. Every other function family " <>
                  "builds on build_*_struct, so it cannot be disabled."

        key == :insert ->
          raise ArgumentError,
                "invalid disable: key :insert for #{subject}. Switch the insert functions off " <>
                  "with insert: false (or insert_via: [name: false] for a target)."

        not Keyword.has_key?(@disable_keys, key) ->
          raise ArgumentError,
                "unknown disable: key #{inspect(key)} for #{subject}. Allowed keys: " <>
                  "#{inspect(Keyword.keys(@disable_keys))}"

        not is_boolean(value) ->
          raise ArgumentError,
                "invalid disable: value for #{inspect(key)} for #{subject}: #{inspect(value)}. " <>
                  "Expected true (disable) or false (enable again)."

        true ->
          :ok
      end
    end

    :ok
  end

  # A `disable:` key for the other kind of factory is a mistake when written on the factory
  # itself. Inherited ones are ignored, since a module holds both kinds of factories.
  @doc false
  def _check_disable_kind!(own_opts, struct?, subject) do
    kind = if struct?, do: :struct, else: :non_struct

    case for(
           {key, _value} <- Keyword.get(own_opts, :disable, []),
           Keyword.fetch!(@disable_keys, key) != kind,
           do: key
         ) do
      [] ->
        :ok

      keys ->
        raise ArgumentError,
              "#{subject} sets disable: #{inspect(keys)}, which only " <>
                if(struct?, do: "non-struct factories have.", else: "struct factories have.")
    end
  end

  @doc false
  def _disabled?(disable, key), do: Keyword.get(disable, key, false)

  defp insert_capture?(value) do
    is_function(value, 2) and Function.info(value, :type) == {:type, :external}
  end

  @doc false
  def _merge_opts(parent_opts, child_opts, subject) do
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

    # Parent targets have already been resolved into the active targets. A child target adds a
    # target, replaces the inherited one of the same name, or removes it with `false`.
    merged_targets =
      child_opts
      |> Keyword.get(:insert_via, [])
      |> Enum.reduce(Keyword.get(parent_opts, :insert_via, []), fn
        {target_name, false}, targets ->
          unless Keyword.has_key?(targets, target_name) do
            raise ArgumentError,
                  "#{subject} removes insert target #{inspect(target_name)}, which does not " <>
                    "exist. Inherited targets: #{inspect(Keyword.keys(targets))}."
          end

          Keyword.delete(targets, target_name)

        {target_name, capture}, targets ->
          if Keyword.has_key?(targets, target_name) do
            Keyword.replace!(targets, target_name, capture)
          else
            targets ++ [{target_name, capture}]
          end
      end)

    # Parent `disable:` holds only the disabled families. A child key set to `true` adds a
    # family, and `false` removes it.
    disabled =
      child_opts
      |> Keyword.get(:disable, [])
      |> Enum.reduce(Keyword.get(parent_opts, :disable, []), fn {key, value}, disabled ->
        Keyword.put(disabled, key, value)
      end)

    merged_disable = for {key, _kind} <- @disable_keys, disabled[key] == true, do: {key, true}

    merged_opts =
      parent_opts
      |> Keyword.merge(child_opts)
      |> Keyword.delete(:hooks)
      |> Keyword.put_new(:insert, :ecto)
      |> Keyword.put(:insert_via, merged_targets)
      |> Keyword.put(:disable, merged_disable)

    if merged_hooks == [] do
      merged_opts
    else
      Keyword.put(merged_opts, :hooks, merged_hooks)
    end
  end

  defp place_hook(inherited, _hook_name, nil = _child_value), do: inherited

  defp place_hook(inherited, hook_name, child_value) do
    case split_hook(hook_name, child_value) do
      {funs, :before_parent} -> funs ++ inherited
      {funs, :after_parent} -> inherited ++ funs
      {funs, :replace_parent} -> funs
    end
  end

  @doc """
  Generates a sequence of strings.

  The sequence name is used as the beginning of the string. For example, if you
  do `FactoryMan.sequence("joe")`, you will get back `"joe0"`, then `"joe1"`, and so on.

  ## Example

      deffactory user(params \\\\ %{}), struct: User do
        Map.merge(%{username: FactoryMan.sequence("joe")}, params)
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

      deffactory user(params \\\\ %{}), struct: User do
        Map.merge(%{email: FactoryMan.sequence(:email, fn n -> "me-\#{n}@foo.com" end)}, params)
      end

  ## Example with a list

      deffactory user(params \\\\ %{}), struct: User do
        Map.merge(%{name: FactoryMan.sequence(:name, ["Joe", "Mike", "Sarah"])}, params)
      end
  """

  @spec sequence(any, (integer -> any) | nonempty_list) :: any
  def sequence(name, formatter), do: FactoryMan.Sequence.next(name, formatter)

  @doc """
  Returns the next value in a named sequence using a formatter function.

  `:start_at` sets the initial counter when the named sequence does not yet exist. It does not change
  an existing counter. List formatters are supported by `sequence/2`, not `sequence/3`.

  ## Example

      deffactory price(params \\\\ %{}), struct: Price do
        Map.merge(%{cents: FactoryMan.sequence(:cents, fn n -> n end, start_at: 600)}, params)
      end
  """

  @spec sequence(any, (integer -> any), start_at: non_neg_integer) :: any
  def sequence(name, formatter, opts), do: FactoryMan.Sequence.next(name, formatter, opts)
end
