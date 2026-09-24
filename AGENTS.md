# FactoryMan - Agent Instructions

## Project Purpose

This is the **FactoryMan repository**, an Elixir library for generating test data. Factories are
defined with `deffactory`, and FactoryMan generates functions for building params, structs, and
database records.

**FactoryMan is the product.** The blog schemas (Users, Authors, Posts, Tags) are just showcase
examples. Do not modify them unless specifically asked.

## Project Structure

```
lib/
  factory_man.ex              # Main module: the core macro system
  factory_man/
    associations.ex           # Association configuration, validation, and value resolution
    codegen.ex                # Shared codegen templates for deffactory/defvariant
    params.ex                 # Ecto struct -> clean params map (build_*_params)
    sequence.ex               # Sequence generation (Agent-based counter)

test/
  test_helper.exs
  support/
    data_case.ex
    factory_man_demo/
      application.ex
      repo.ex
      factory.ex              # Base factory (repo config, hooks)
      factory/
        child_factory.ex      # Child factory (all factory definitions)
      users.ex                # Context modules (not the product)
      users/user.ex           # Demo schemas (not the product)
      authors.ex
      authors/author.ex
      posts.ex
      posts/post.ex
      tags.ex
      tags/tag.ex
      posts_tags/post_tag.ex
      embedded_schema.ex
  factory_man/
    assoc_test.exs
    extends_test.exs
    hooks_test.exs
    lazy_evaluation_test.exs
    sequence_test.exs
    strict_params_test.exs
  factory_man_demo/
    factory_test.exs
    factory/
      child_factory_test.exs  # Main test file
```

## Usage Rules

### Defining Factories

Use `deffactory` to define factories and `defvariant` to define variants of existing factories:

```elixir
# Canonical pattern - always follow this structure:
deffactory name(params \\ %{}), struct: SchemaModule do
  base_params = %{field: "default_value"}

  Map.merge(base_params, params)
end
```

Key rules:
- With `struct:`, the factory body must return a **map** (not a struct) containing only the
  struct's fields, unless using `body: :struct`
- With `body: :struct`, the body returns a **struct** directly (skips `struct!()`);
  params functions are still generated, derived from the struct, and the returned struct is
  lazily evaluated
- `body: :struct` is ignored for non-struct factories; their `build_*` functions are always generated
- Without `struct:`, the body can return **any value** (map, keyword list, string, tuple, etc.)
- You must merge `params` yourself; FactoryMan does not auto-merge
- For Ecto factories, declare associations with `assocs: [field: &build_x_struct/1]`. A builder
  is a 1-arity function, a 2-arity `fn params, factory_params -> ... end` (sees keys declared
  above it resolved), or `{builder, options}` with `default: value` and/or `required: true`. Each
  declared key is resolved before the
  body, so the body always receives it resolved and the final `Map.merge(base_params, params)` is
  always correct. **The builder is the default**: an absent key is built with `%{}` (or `[]` for a
  plural association, or treated as `default:`). Never add a `base_params` default for a declared
  key; it is dead code
- `assocs:` is factory-level only (also on `defvariant`), requires an Ecto schema `struct:`, and
  accepts direct associations only (no embeds, no `:through`). It is evaluated on every build, so
  `default:` values must be literals (`nil`, params maps, lists of params maps); `params` is not in
  scope there. Supplied structs and builder results must be the related schema (a singular
  builder may return `nil`, unless the key is `required: true`)
- `required: true` (singular keys only, not with `default: nil`) raises on a caller's `nil` or a
  builder's `nil`; an absent key still builds. It is checked at resolution, not on the finished
  struct. A variant can add it but not relax a base's
- Imperative resolution uses `FactoryMan.assoc/3,4` and `FactoryMan.assoc_list/3,4` (same rules,
  only option `default:`; no `required:` and no schema check). They return the resolved value and do not modify the params map, so a
  factory that ends in `Map.merge(base_params, params)` must put the value back first (e.g.
  `Map.put(params, :author, author)`) or drop the key
- An explicit `nil` is preserved; a nil list raises. A self-referential or mutually recursive
  default build raises; declare the key with `default: nil` (`default: []` for lists) or pass a
  value
- Unknown `use FactoryMan`, `deffactory`, and `defvariant` options raise
- Helper functions are **not** imported by `use FactoryMan`. Always call them qualified
  (`FactoryMan.assoc(...)`, `FactoryMan.sequence(...)`). Only `deffactory`/`defvariant` are imported.
- Lazy evaluation (0-arity and 1-arity functions) works in both maps and keyword lists
- Factory names are atoms; the generated functions use that name
- Opt-in `strict: true` (or `strict: [allow: [:extra_key]]`) rejects unknown param keys at
  build entry for struct factories; ignored for non-struct factories. Cascades from module level.

### Generated Function Naming

For a factory named `:user` with `struct: User`:

| Function                            | Returns     | Purpose                              |
| ----------------------------------- | ----------- | ------------------------------------ |
| `build_user_struct/0,1`             | `%User{}`   | Struct in memory (not persisted)     |
| `build_user_params/0,1`             | `%{}`       | Clean params map derived from struct |
| `build_user_string_params/0,1`      | `%{"" => }` | Same, with string keys               |
| `insert_user/0,1,2`                 | `%User{}`   | Inserted into database               |
| `build_user_struct_list/1,2`        | `[%User{}]` | List of structs                      |
| `build_user_params_list/1,2`        | `[%{}, ...]`| List of params maps                  |
| `build_user_string_params_list/1,2` | `[%{}, ...]`| List of string-keyed params maps     |
| `insert_user_list/1,2,3`            | `[%User{}]` | List of inserted records             |
| `insert_user_struct/1,2`            | `%User{}`   | Inserts an already-built struct      |

For a factory **without** `struct:` option, simplified names are used: `build_*/0,1` and
`build_*_list/1,2` (no `_params` suffix).

For **embedded schemas**, `insert_*` functions are automatically skipped.

### Hook Pipeline

```
build_user_struct:
  params validation -> before_build_params -> assocs: resolution
  -> [factory body + lazy eval] -> after_build_params
  -> before_build_struct -> struct!() -> after_build_struct

build_user_params (calls build_user_struct internally):
  -> strip Ecto metadata (Map.from_struct/1 for plain structs)

insert_user (calls build_user_struct internally):
  -> before_insert -> Repo.insert!() -> after_insert
```

Hooks chain across levels (parent module -> child module -> factory) in onion order, like
middleware: a parent's `before_*` hooks run first, its `after_*` hooks run last. Place a hook
explicitly with `{hook, :before_parent | :after_parent | :replace_parent}`. Hooks must be 1-arity
remote captures (`&__MODULE__.my_hook/1`); anything else (e.g. an anonymous function) raises. Switch
off an inherited hook with `{&Function.identity/1, :replace_parent}`. Reflection
(`__factory_man__(:opts, name)`) shows each hook name's resolved list in run order.

### Common Anti-Patterns

- **Don't pass keyword lists as params to struct factories.** Struct factories expect maps: `%{key: value}`, never `[key: value]`. A non-map raises at the factory boundary
- **Don't forget `Map.merge(base_params, params)`** at the end of every struct/map factory body
- **Don't use `build_user()` for struct factories.** The correct names include the type:
  `build_user_struct()`, `build_user_params()`, `insert_user()`. Non-struct factories use `build_*()` directly.
- **Don't create structs in the factory body** (unless using `body: :struct`). Return a plain map; the generated `build_*_struct` function handles struct conversion
- **Don't define factories outside of modules that `use FactoryMan`**

### Lazy Evaluation

0-arity functions are evaluated at build time. 1-arity functions receive the parent map or
keyword list:

```elixir
%{
  created_at: fn -> DateTime.utc_now() end,           # 0-arity: called with no args
  display_name: fn user -> "#{user.username} (User)" end  # 1-arity: receives parent map
}
```

**Important:** lazy values are resolved in two passes: the 0-arity functions first, then the
1-arity ones. A 1-arity function sees plain and resolved 0-arity values, but not another 1-arity
field, which is still a function reference when it runs.

### Sequences

```elixir
FactoryMan.sequence("user")                                        # "user0", "user1", ...
FactoryMan.sequence(:email, fn n -> "user#{n}@example.com" end)    # custom formatter
FactoryMan.sequence(:role, ["admin", "user", "guest"])              # cycles through list
FactoryMan.sequence(:order, fn n -> "ORD-#{n}" end, start_at: 1000) # custom start
```

Reset in test setup: `FactoryMan.Sequence.reset()`

## Development Notes

- **Use `MIX_ENV=test` for non-test commands** (e.g. `iex -S mix`, `mix compile`). Factories are
  in `test/support/` and only compiled under the test env. `mix test` sets this automatically.
- Public functions that exist only for macro-generated code or other internal plumbing must use
  `@doc false`. Do not publish API documentation whose purpose is merely to explain that a
  function is internal; keep necessary implementation context in source comments instead.
- When you complete a task:
  1. Review your changes for optimization opportunities
  2. Update relevant documentation (module docs, AGENTS.md, CHANGELOG.md) and ensure all docs
     are consistent with the changes made. **Never modify old changelog entries.** Only add new ones.
  3. Run `mix format` and verify tests pass (`mix test`, or check the test-watch tmux session if running)
  4. Make a release commit following the existing git history format (see `git log` for examples):
     `chore: release vX.Y.Z`, bumping `@version` in `mix.exs`, the dependency version in
     `README.md`, and the CHANGELOG heading (`## [X.Y.Z] - YYYY-MM-DD`)
  5. Tag the release commit with a lightweight tag: `git tag vX.Y.Z <release-commit>`. The user
     pushes the commits and tags and publishes to Hex
- If asked to work on this project, clarify: FactoryMan library or demo schemas?
- If a local agent file exists, follow its instructions
- The root factory for testing is `:user` via `FactoryManDemo.Factory.ChildFactory.build_user_struct/1`

## Database

This project requires a Postgres database. If a local agent file exists, follow its setup instructions.

