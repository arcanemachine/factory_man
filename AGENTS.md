# FactoryMan - Agent Instructions

## Project Purpose

This is the **FactoryMan repository**, an Elixir library for generating test data. Factories are
defined with `deffactory`, and FactoryMan generates functions for building params, structs, and
database records.

**FactoryMan is the product.** The blog schemas (Users, Authors, Posts, Tags) are just showcase
examples — do not modify them unless specifically asked.

## Project Structure

```
lib/
  factory_man.ex              # Main module — core macro system
  factory_man/
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
    sequence_test.exs
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
  params functions are still generated, derived from the struct
- `body: :struct` is ignored for non-struct factories — their `build_*` functions are always generated
- Without `struct:`, the body can return **any value** (map, keyword list, string, tuple, etc.)
- You must merge `params` yourself — FactoryMan does not auto-merge
- Lazy evaluation (0-arity and 1-arity functions) works in both maps and keyword lists
- Factory names are atoms — the generated functions use that name

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
  before_build_params -> [factory body + lazy eval] -> after_build_params
  -> before_build_struct -> struct!() -> after_build_struct

build_user_params (calls build_user_struct internally):
  -> strip Ecto metadata (Map.from_struct/1 for plain structs)

insert_user (calls build_user_struct internally):
  -> before_insert -> Repo.insert!() -> after_insert
```

### Common Anti-Patterns

- **Don't pass keyword lists as params to struct factories.** Struct factories expect maps: `%{key: value}`, never `[key: value]`
- **Don't forget `Map.merge(base_params, params)`** at the end of every struct/map factory body
- **Don't use `build_user()` for struct factories** — the correct names include the type:
  `build_user_struct()`, `build_user_params()`, `insert_user()`. Non-struct factories use `build_*()` directly.
- **Don't create structs in the factory body** (unless using `body: :struct`). Return a plain map — the generated `build_*_struct` function handles struct conversion
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

**Important:** 1-arity functions receive the map *before* lazy evaluation. Don't reference other
lazy fields from a 1-arity function — they'll still be function references, not resolved values.

### Sequences

```elixir
sequence("user")                                        # "user0", "user1", ...
sequence(:email, fn n -> "user#{n}@example.com" end)    # custom formatter
sequence(:role, ["admin", "user", "guest"])              # cycles through list
sequence(:order, fn n -> "ORD-#{n}" end, start_at: 1000) # custom start
```

Reset in test setup: `FactoryMan.Sequence.reset()`

## Development Notes

- **Use `MIX_ENV=test` for non-test commands** (e.g. `iex -S mix`, `mix compile`) — factories are
  in `test/support/` and only compiled under the test env. `mix test` sets this automatically.
- When you complete a task:
  1. Review your changes for optimization opportunities
  2. Update relevant documentation (module docs, AGENTS.md, CHANGELOG.md) and ensure all docs
     are consistent with the changes made. **Never modify old changelog entries** — only add new ones.
  3. Run `mix format` and verify tests pass (`mix test`, or check the test-watch tmux session if running)
  4. Make a release commit following the existing git history format (see `git log` for examples)
- If asked to work on this project, clarify: FactoryMan library or demo schemas?
- Always use tmux for interactive IEx sessions (see AGENTS.LOCAL.md)
- The root factory for testing is `:user` via `FactoryManDemo.Factory.ChildFactory.build_user_struct/1`

## Database

This project requires a Postgres database. See [AGENTS.LOCAL.md](./AGENTS.LOCAL.md) for setup.

