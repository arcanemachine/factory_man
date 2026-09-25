# FactoryMan Usage Rules

FactoryMan builds test data. Factories are defined with `deffactory` and `defvariant` in a module
that has `use FactoryMan`, and FactoryMan generates the functions that build params, structs, and
database records.

## Defining factories

Always follow this shape:

```elixir
deffactory name(params \\ %{}), struct: SchemaModule do
  base_params = %{field: "default_value"}

  Map.merge(base_params, params)
end
```

- With `struct:`, the body returns a **map** of the struct's fields, not a struct. With
  `body: :struct`, the body returns the struct itself; params functions are still generated, and
  the struct is still lazily evaluated.
- Without `struct:`, the body can return any value (map, keyword list, string, tuple, ...), and
  `body:` is ignored.
- Merge `params` yourself, last: FactoryMan does not merge them for you.
- Struct factories take a **map** of params, never a keyword list.
- Only `deffactory` and `defvariant` are imported. Call helpers qualified: `FactoryMan.sequence/1,2,3`,
  `FactoryMan.assoc/3,4`, `FactoryMan.assoc_list/3,4`.
- Unknown options to `use FactoryMan`, `deffactory`, and `defvariant` raise.

## Generated functions

For `deffactory user(params \\ %{}), struct: User`:

| Function                              | Returns                              |
| ------------------------------------- | ------------------------------------ |
| `build_user_struct/0,1,2`             | `%User{}` in memory (not persisted)  |
| `build_user_params/0,1,2`             | Clean params map derived from struct |
| `build_user_string_params/0,1,2`      | Same, with string keys               |
| `insert_user/0,1,2`                   | `%User{}` inserted into the database |
| `insert_user_struct/1,2`              | Inserts an already-built `%User{}`   |
| `build_user_struct_list/1,2,3`        | List of structs                      |
| `build_user_params_list/1,2,3`        | List of params maps                  |
| `build_user_string_params_list/1,2,3` | List of string-keyed params maps     |
| `insert_user_list/1,2,3`              | List of inserted records             |

- A struct factory has no `build_user/1`. A factory without `struct:` generates only `build_*` and
  `build_*_list`.
- With the default `insert: :ecto`, embedded schemas, plain structs, and modules without a
  `repo:` get no insert functions. `insert: false` removes them.
- A builder's last argument may be options; the only one is `variants:`. `insert_*` takes one
  option list: `:variants` is FactoryMan's, and every other option goes to the insert target
  (`Repo.insert!/2` by default).
- With `:ecto`, `insert_*_struct` raises on a struct that has already been inserted.
- `disable: [family: true]` switches off unused families: `:params`, `:string_params`,
  `:struct_list`, `:params_list`, `:string_params_list`, `:insert_list`, and `:non_struct_list`.
  It cascades per key; `family: false` enables an inherited family again. `build_*_struct` is
  always generated, and inserts are switched off with `insert: false`. The disabled families show
  in `__factory_man__(:opts, name)[:disable]`.

## Insert targets

```elixir
use FactoryMan, repo: MyApp.Repo, insert_via: [search: &MyApp.Factory.index!/2]

deffactory event(params \\ %{}), struct: Event, insert: &MyApp.Factory.publish!/2 do
  Map.merge(%{name: "event"}, params)
end

insert_event()                     # MyApp.Factory.publish!/2, with the insert hooks
insert_event_via_search()          # MyApp.Factory.index!/2, no hooks
insert_event_struct_via_search(event)
```

- `insert:` is the default target, used by `insert_*`, `insert_*_list`, and `insert_*_struct`:
  `:ecto` (default), `false`, or a remote capture of arity 2. A capture works for any struct
  factory, including plain structs and embedded schemas.
- `insert_via: [name: capture]` adds an `insert_*_via_<name>` family (`/0,1,2`, `_list/1,2,3`,
  and `insert_*_struct_via_<name>/1,2`) to every struct factory below it. `name: false` removes
  an inherited target. `ecto` is not a valid name.
- An insert function takes `(struct, opts)` and returns the inserted struct. Write
  `def put!(struct, _opts)` for a store without options. Anonymous functions and local captures
  raise.
- Insert hooks run for the default target only. A target does everything it needs in its own
  function, and does not check whether the struct has already been inserted.
- Set `insert:` and `insert_via:` on struct factories only; on a non-struct factory they raise.

## Variants

```elixir
defvariant admin(params \\ %{}), for: :user do
  Map.merge(%{role: "admin"}, params)
end

defvariant senior(params \\ %{}), for: :user, extends: [:admin] do
  Map.merge(%{title: "Senior admin"}, params)
end

build_admin_user_struct()
build_user_struct(%{}, variants: [:admin, :confirmed])
```

- A variant preprocesses params, then delegates to its base factory. Its functions are named
  `{variant}_{base}` (e.g. `build_admin_user_struct`), or by `as:`.
- `for:` must name a factory. Build on other variants of the same factory with `extends:`, and
  define a variant after the variants it extends, in the same module as its base factory.
- Combine variants in one build with `variants: [...]`, listing variants by their `defvariant` name
  (`:admin`, not `:admin_user`).
- Precedence: the caller's params win, then a later variant wins over an earlier one, and a variant
  wins over the variants it extends. This holds for variants that merge params last.
- A variant that merges params first (`Map.merge(params, %{banned: true})`) forces its values: it
  wins over the caller and over later variants. Use it only for presets whose name is a promise.
- A variant that only sets values needs no body: `defvariant admin, for: :user, defaults:
  %{role: "admin"}`. `defaults:` loses to the caller, `force:` wins over the caller, and a variant
  with only `extends:` names a combination. Add `:factory_man` to `import_deps` in
  `.formatter.exs` so `mix format` leaves them without parentheses.
- List a factory's variant names with `__factory_man__(:variants, factory_name)`.

## Associations

- Declare associations with `assocs: [author: &build_user_struct/1]` (Ecto schema `struct:`
  only; direct associations only, no embeds or `:through`).
- **The builder is the default**: an absent key is built with `%{}` (`[]` for a list). Never put a
  default for a declared key in `base_params`; it is never used.
- The body always receives declared keys resolved, so `Map.merge(base_params, params)` stays
  correct.
- Builder forms: a 1-arity function; a 2-arity `fn params, factory_params -> ... end` that sees the
  keys declared above it resolved; or `{builder, default: value, required: true}`.
- `default:` is evaluated on every build, so keep it a literal (`nil`, a params map, or a list of
  params maps). `params` is not in scope in `assocs:`.
- `required: true` (singular keys only) raises on a caller's or builder's `nil`.
- A caller's explicit `nil` is kept; a `nil` list raises. A self-referential default build raises;
  declare such a key with `default: nil` (or `default: []`).
- `FactoryMan.assoc/3,4` and `FactoryMan.assoc_list/3,4` resolve one key imperatively and do not
  change `params`: put the resolved value back (`Map.put(params, :author, author)`) or drop the key
  before the final merge.
- `build_*_params` sets a `belongs_to` foreign key only when the associated record is inserted. For
  a real foreign key, pass an inserted record, or use a variant whose builder inserts.

## Strict params

- `strict: true` raises on unknown keys (before the body) and on params the body ignores or
  changes (after the body). Set it once in the base factory: `use FactoryMan, strict: true`.
- `strict: [allow: [:key]]` exempts keys from both checks: a non-field key may be passed, and a
  field may be changed by the body.
- A plain map field is kept when each key the caller gave is kept. Function values and association
  keys are not checked.
- Strict is ignored for non-struct factories. The ignored-params check runs in the base factory,
  not in variant bodies.

## Hooks

- A hook is a 1-arity remote capture (`&__MODULE__.my_hook/1`) or a list of them. Anonymous
  functions and local captures raise.
- Hook names: `before_build_params`, `after_build_params`, `before_build_struct`,
  `after_build_struct`, `before_insert`, `after_insert`.
- Hooks chain across levels (parent module, child module, factory) in onion order: a parent's
  `before_*` hooks run first, its `after_*` hooks run last.
- Place hooks with `{hook, :before_parent | :after_parent | :replace_parent}`. Switch off the
  inherited hooks with `{[], :replace_parent}`.

## Lazy values and sequences

- In a body's map or keyword list, a 0-arity function is called at build time, and a 1-arity
  function receives the parent map. 0-arity functions resolve first, so a 1-arity function sees
  plain and 0-arity values, but not another 1-arity field.
- Use a lazy `fn -> ... end` for a value that should only be computed when the caller does not
  supply one.
- `FactoryMan.sequence("user")` gives `"user0"`, `"user1"`, ...; `sequence(name, formatter)` and
  `sequence(name, list)` format or cycle. `FactoryMan.Sequence.reset/0` resets every counter for
  every running test; in async tests use `reset/1` with the test's own names.

## Anti-patterns

- A keyword list as params to a struct factory.
- A factory body that forgets `Map.merge(base_params, params)`.
- `build_user()` for a struct factory (use `build_user_struct()`, `build_user_params()`, or
  `insert_user()`).
- A struct returned from a body without `body: :struct`.
- A `base_params` default for a key declared in `assocs:`.
- Factories defined outside a module that uses `FactoryMan`.
- `Repo.insert!/2` on a built struct instead of `insert_*_struct`, which skips the insert hooks.
- An `insert:` or `insert_via:` function of arity 1, or one that returns something other than the
  inserted struct.
