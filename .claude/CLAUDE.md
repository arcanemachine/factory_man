# FactoryMan - Instructions for Claude

## Project Purpose

This is the **FactoryMan repository**, an Elixir testing factory library.

**FactoryMan is the product.** The blog schemas (Users, Authors, Posts, Tags) are just showcase examples.

## What is FactoryMan?

A macro-based testing factory library located in `/workspace/projects/factory_man/lib/factory_man.ex` that:
- Generates `build_<name>/1` functions to create test data structs in memory
- Generates `insert_<name>!/1` functions to build and insert into database (when repo configured)
- Supports lifecycle hooks: `:before_build`, `:after_build`, `:before_insert`, `:after_insert`
- Allows factory inheritance via `:extends` option
- Integrates with Ecto repositories

## Project Structure

```
lib/
  factory_man.ex              # THE MAIN LIBRARY - core macro system
  factory_man_demo/           # Example schemas (demo content, not the product)
    users/user.ex
    authors/author.ex
    posts/post.ex
    tags/tag.ex
    posts_tags/post_tag.ex

test/support/
  factory.ex              # Base factory with repo and hooks
  child_factory.ex        # Child factory extending base, contains all factory definitions
```

## Example Domain (Demo Content)

The blog system demonstrates FactoryMan with realistic relationships:

- **User** (username) → has_one **Author**
- **Author** (name) → has_many **Posts**
- **Post** (title, content) ↔ **Tag** (many-to-many via posts_tags)

These schemas exist to showcase how FactoryMan handles:
- Simple attributes
- One-to-one and one-to-many associations
- Many-to-many relationships with join tables
- Complex nested data building

## Key Demonstrations

1. **Base Factory Pattern** (`test/support/factory_man_demo/factory.ex`):
   - Configures repo integration
   - Sets up `after_insert_handler` that resets associations to `NotLoaded` (mimics raw DB queries)

2. **Factory Inheritance** (`test/support/factory_man_demo/child_factory.ex`):
   - Uses `extends: FactoryManDemo.Factory` to inherit base factory config
   - Contains all factory definitions (user, author, lazy_user, etc.)
   - Demonstrates defaults, custom parameter overrides, hooks, and lazy evaluation

3. **Hook System**:
   - `before_build_handler` - modifies data before struct creation
   - `after_insert_handler` - processes data after database insertion

## Database Connection Setup

This project requires a Postgres database. See [AGENTS.LOCAL.md](./AGENTS.LOCAL.md) for local setup instructions.

## Working with Persistent IEx Sessions

### Using tmux for Interactive Sessions

The workspace includes tmux at `tmux`. **Always use tmux for persistent IEx sessions** - don't try to run IEx commands directly with bash piping.

For tmux commands and IEx session setup, see [AGENTS.LOCAL.md](./AGENTS.LOCAL.md).

## Macro Implementation (`lib/factory_man.ex:222-285`)

**API:** `factory(name, do: block)` - supports single expression OR multi-block syntax

**How it works:**
- Parses block to extract `build do` and `hooks do` sections
- Backwards compatible: single expression treated as build block
- Escapes build body AST with `Macro.escape(body, unquote: true)`
- Merges factory-level hooks with module-level hooks (factory takes precedence)
- Injects `var!(params)` for parameter access (params is ALWAYS a map)
- Generates: `build_{name}/1`, `insert_{name}!/1`, `_build_{name}_without_hooks/1` (private)

**Hook flow:** before_build → body → after_build → repo.insert! → before_insert → after_insert

**Old syntax (still works):**
```elixir
factory :user do
  %User{username: Map.get(params, :username, "default")}
end
```

**New multi-block syntax:**
```elixir
factory :user do
  build do
    %User{username: Map.get(params, :username, "default")}
  end

  hooks do
    [after_build: fn user -> %{user | username: String.upcase(user.username)} end]
  end
end
```

**Usage:** `FactoryManDemo.ChildFactory.build_user(%{username: "alice"})`

## Important Notes for Claude

- **The module documentation in `lib/factory_man.ex` may be out of date** - the API is actively being changed
- This is NOT a blog application - it's a factory library demonstration
- Don't "improve" the demo schemas unless specifically asked - they're examples
- The interesting code is in `lib/factory_man.ex` and `test/support/`
- If asked to work on "the project", clarify whether they mean FactoryMan library or the demo schemas
- Always use tmux for interactive IEx sessions
- **ALWAYS use `MIX_ENV=test` for factory work** - factories are in `test/support/`
- **Testing factories: Use :user factory (FactoryManDemo.ChildFactory.build_user/1) - it's the root factory that others depend on**
- **Don't create new factories - only work with existing ones**

## Project Task Tracking

- **AGENTS.TODO.md** - Contains ongoing todo items and session notes
  - Check this file at the start of each session for context
  - Update with accomplishments and next steps when finishing work
