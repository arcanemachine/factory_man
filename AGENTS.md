# FactoryMan - Agent Instructions

## Project Purpose

This is the **FactoryMan repository**, an Elixir testing factory library.

**FactoryMan is the product.** The blog schemas (Users, Authors, Posts, Tags) are just showcase
examples — do not modify them unless specifically asked.

## Project Structure

```
lib/
  factory_man.ex              # THE MAIN LIBRARY - core macro system
  factory_man/
    sequence.ex               # Sequence generation (Agent-based counter)

test/
  support/
    factory_man_demo/
      factory.ex              # Base factory (repo config, hooks)
      factory/
        child_factory.ex      # Child factory (all factory definitions)
      users/user.ex           # Demo schemas (not the product)
      authors/author.ex
      posts/post.ex
      tags/tag.ex
      posts_tags/post_tag.ex
      embedded_schema.ex
      repo.ex
      application.ex
    data_case.ex
  factory_man/
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
- The factory body must return a **map** (not a struct), unless using `params?: false`
- With `params?: false`, the body returns a **struct** directly (skips params builder + `struct!()`)
- You must merge `params` yourself — FactoryMan does not auto-merge
- The parameter is always a map (`%{}`), never a keyword list
- Factory names are atoms — the generated functions use that name

### Generated Function Naming

For a factory named `:user` with `struct: User`:

| Function                    | Returns     | Purpose                          |
| --------------------------- | ----------- | -------------------------------- |
| `build_user_params/0,1`     | `%{}`       | Plain map (for changesets, APIs)  |
| `build_user_struct/0,1`     | `%User{}`   | Struct in memory (not persisted)  |
| `insert_user!/1,2`          | `%User{}`   | Inserted into database            |
| `build_user_params_list/1,2`| `[%{}, ...]`| List of params maps               |
| `build_user_struct_list/1,2`| `[%User{}]` | List of structs                   |
| `insert_user_list!/1,2,3`   | `[%User{}]` | List of inserted records          |

For a factory **without** `struct:` option, only `build_*_params` and `build_*_params_list` are
generated.

For **embedded schemas**, `insert_*` functions are automatically skipped.

### Hook Pipeline

```
build_user_params:
  before_build_params -> [factory body + lazy eval] -> after_build_params

build_user_struct (calls build_user_params internally):
  -> before_build_struct -> struct!() -> after_build_struct

insert_user! (calls build_user_struct internally):
  -> before_insert -> Repo.insert!() -> after_insert
```

### Common Anti-Patterns

- **Don't pass keyword lists as params.** Always use maps: `%{key: value}`, never `[key: value]`
- **Don't forget `Map.merge(base_params, params)`** at the end of every factory body
- **Don't use `build_user()` or `insert_user!()`** — the correct names include the type:
  `build_user_struct()`, `build_user_params()`, `insert_user!()`
- **Don't create structs in the factory body** (unless using `params?: false`). Return a plain map — FactoryMan calls `struct!()` for you
- **Don't define factories outside of modules that `use FactoryMan`**

### Lazy Evaluation

0-arity functions are evaluated at build time. 1-arity functions receive the parent map:

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

- **ALWAYS use `MIX_ENV=test` for factory work** — factories are in `test/support/`
- **Run tests:** `MIX_ENV=test mix test`
- This is NOT a blog application — it's a factory library with blog schemas as examples
- If asked to work on "the project", clarify: FactoryMan library or demo schemas?
- Always use tmux for interactive IEx sessions (see AGENTS.LOCAL.md)
- The root factory for testing is `:user` via `FactoryManDemo.Factory.ChildFactory.build_user_struct/1`

## Database

This project requires a Postgres database. See [AGENTS.LOCAL.md](./AGENTS.LOCAL.md) for setup.

