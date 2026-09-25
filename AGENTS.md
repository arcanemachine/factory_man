# FactoryMan - Agent Instructions

## Project Purpose

This is the **FactoryMan repository**, an Elixir library for generating test data. Factories are
defined with `deffactory`, and FactoryMan generates functions for building params, structs, and
database records.

**FactoryMan is the product.** The blog schemas (Users, Authors, Posts, Tags) are just showcase
examples. Do not modify them unless specifically asked.

## Project Structure

```
CHANGELOG.md                  # User-facing changes, per release
CHEATSHEET.cheatmd            # Cheat sheet (ExDoc extra)
COOKBOOK.md                   # Recipes (ExDoc extra)
README.md
usage-rules.md                # Rules for writing factories (shipped in the package)

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
    disable_test.exs
    extends_test.exs
    hooks_test.exs
    insert_targets_test.exs
    lazy_evaluation_test.exs
    sequence_test.exs
    strict_params_test.exs
    variants_test.exs
  factory_man_demo/
    factory_test.exs
    factory/
      child_factory_test.exs  # Main test file
```

## Usage Rules

The rules for writing factories live in `usage-rules.md`, which ships with the package (for
`usage_rules`) and is published on HexDocs. Read it before writing or changing factories, and keep
it current (see "When you complete a task" below). The full API reference is the `FactoryMan`
module documentation.

## Documentation

Each kind of content has one home. Keep them consistent, and avoid duplicating content between them:

- `usage-rules.md` - short, self-contained rules and anti-patterns for writing factories. It is
  copied into consuming projects' agent files, so it cannot rely on links.
- `CHEATSHEET.cheatmd` - tables for lookups (generated functions, options, precedence).
- `lib/factory_man.ex` `@moduledoc` and function docs - the full reference, as shown by
  `h FactoryMan`. Every option and rule is stated here.
- `COOKBOOK.md` - recipes.
- `README.md` - the pitch, installation, a short tour, and links.
- `CHANGELOG.md` - user-facing changes, per release.

## Development Notes

- **Use `MIX_ENV=test` for non-test commands** (e.g. `iex -S mix`, `mix compile`). Factories are
  in `test/support/` and only compiled under the test env. `mix test` sets this automatically.
- Public functions that exist only for macro-generated code or other internal plumbing must use
  `@doc false`. Do not publish API documentation whose purpose is merely to explain that a
  function is internal; keep necessary implementation context in source comments instead.
- When you complete a task:
  1. Review your changes for optimization opportunities
  2. Update relevant documentation (module docs, `usage-rules.md`, `CHEATSHEET.cheatmd`,
     `COOKBOOK.md`, `README.md`, AGENTS.md, CHANGELOG.md) and ensure all docs are consistent with
     the changes made. Any API change updates `usage-rules.md` and `CHEATSHEET.cheatmd`. **Never
     modify old changelog entries.** Only add new ones.
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

