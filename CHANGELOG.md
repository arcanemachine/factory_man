# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2026-07-03

### Added

- `strict:` option for struct factories: `strict: true` raises an `ArgumentError` when a caller
  passes param keys that are not fields of the `:struct` option's struct, catching typos at the
  factory boundary. Previously a typo surfaced late (`struct!/2`) for merge-style factories and
  never for `body: :struct` factories, whose bodies read params selectively. Use
  `strict: [allow: [...]]` to permit specific non-field keys (e.g. inputs used only to derive
  other fields). Cascades from `use FactoryMan` like other options; ignored for non-struct
  factories (matching `body:`). The check runs at build entry, so params builders, inserts,
  lists, and variants are all covered.

## [0.8.0] - 2026-07-03

### Added

- `assoc/4` accepts an `:on_missing` option: `:build` (default) keeps the existing behavior of
  building the default association; `nil` makes a missing key resolve to `nil`, for
  associations that should only exist when the caller supplies one. Independent of `:on_nil`;
  typically paired with `on_nil: :keep`.

## [0.7.0] - 2026-07-02

### Added

- `insert_<name>_struct/1,2`: inserts an already-built struct through the factory's insert
  pipeline (`before_insert` hook, repo insert with options, `after_insert` hook). Closes a
  consistency hole: modifying a built struct and calling `Repo.insert!/2` directly skips the
  factory's insert hooks, producing records shaped differently from `insert_*` results.
  Variants delegate to their base factory's pipeline. Generated under the same conditions as
  the other insert functions.
- `__factory_man__(:factories)` reflection: lists every factory and variant name registered in
  a module (variants under their full name), in definition order. Enables runtime dispatch —
  selecting and calling factories by name — without string-building function names.
- `FactoryMan.assoc/4` and `FactoryMan.assoc_list/4` (auto-imported by `use FactoryMan`):
  resolve association values from factory params. A missing key builds a default, a struct is
  reused (type-checked against the `:struct` option, which raises on a mismatch), and a params
  map builds the association from those params (merged over `:inherit` defaults). `assoc_list/4`
  applies the same rules per element; `on_nil: :keep` supports optional associations. Replaces
  the hand-written `case`/`Map.get_lazy` patterns previously shown in the docs, which silently
  misbehaved when given a struct of the wrong type.

## [0.6.0] - 2026-07-02

### Added

- Generated factory functions now carry `@doc` attributes, so they show up documented in
  HexDocs, IEx `h/1`, and editor tooltips instead of appearing undocumented.
- Variants are now registered under their full name, so a variant can itself be used as the
  base of another variant (e.g. `defvariant senior(params \\ %{}), for: :admin_user`).
  Previously this raised "base factory not found" at compile time.

### Changed

- **Breaking:** The `build_params?` option is renamed to `body`, with values `:params` (default)
  and `:struct` (the factory body returns a struct directly; formerly `build_params?: false`).
  Since the params unification, params functions are always generated, so the old name's
  "generate params builders?" reading had become misleading — the option only controls what the
  factory body returns. The old key raises a compile-time `ArgumentError`, as does an
  unrecognized `body` value.
- **Breaking:** `params_for_*` and `string_params_for_*` are renamed to `build_*_params` and
  `build_*_string_params`, replacing the former raw params builders. For struct factories,
  `build_*_params` now builds the struct and converts it to a clean map (Ecto metadata stripped
  for schemas, `Map.from_struct/1` for plain structs) instead of returning the factory body's
  raw output. The raw params stage still exists inside `build_*_struct` (hooks and lazy
  evaluation are unchanged) but is no longer a public function. Consequences:
  - Factory bodies of struct factories must return only struct fields (always passed through
    `struct!/2` now).
  - `build_params?: false` factories now also get `build_*_params` (derived from the struct).
  - `build_*_string_params_list` variants are generated (previously `string_params_for_*` had
    no list variant).
  - Non-struct factories are unchanged (`build_*` still returns the body's value verbatim).
- **Breaking:** The `build_struct?` option is removed and now raises a compile-time
  `ArgumentError`. Params functions are derived from the built struct, so "params-only" struct
  factories are no longer expressible — omit the `:struct` option instead.
- **Breaking:** The debug functions `_factory_opts/0` and `_<name>_factory_opts/0` are replaced
  by a single reflection function following the Elixir dunder convention (like `__schema__`):
  `__factory_man__(:opts)` for module options and `__factory_man__(:opts, factory_name)` for a
  factory's (or variant's) merged options.
- Internal refactor: `deffactory` and `defvariant` now generate their shared function families
  (list builders, `params_for_*`/`string_params_for_*`, insert convenience/list functions) from
  common templates in an internal codegen module, removing ~200 lines of drifted duplication.
- **Breaking (edge case):** variant list convenience functions (`build_<variant>_list/1` and
  `build_<variant>_params_list/1`) are now generated under the same conditions as their
  `deffactory` counterparts — when the factory head has a default argument — and call the item
  builder with its actual default instead of always passing `%{}`. Variants of factories whose
  argument has no default no longer get the 1-arity list convenience.
- Duplicate option warnings are now emitted with `IO.warn` instead of `Logger.warning`, so they
  carry file/line attribution and are caught by `--warnings-as-errors`.
- Test suite cleanup: removed tests made redundant by the params unification, retitled the
  stale "params_for" section, and added coverage for `build_*_string_params_list`, embedded
  schema params, and inherited `after_insert` hooks running on child-module inserts.
- Documentation restructured: the README is now a short onboarding tour (installation, quick
  tour, how it works, which function to use, project structure), and the `FactoryMan` moduledoc
  is the full reference — ending the near-total duplication between the two. Hooks and variants
  moved up in the reference; added a mermaid diagram of the generated-function pipeline and a
  cookbook section (building associations). The README install snippet now recommends
  `only: [:dev, :test]`.

### Fixed

- An unescaped interpolation in the moduledoc's hooks example baked a compile-time timestamp
  into the published docs; the example now renders `System.os_time()` literally as intended.

- Variant list builders no longer crash for variants of non-struct factories with non-map
  defaults (e.g. `defvariant loud(name \\ "world"), for: :greeting`). Previously
  `build_loud_greeting_list(2)` passed `%{}` to the variant body.

- Module-level hooks now merge per hook key across `extends:`, as documented. Previously a child
  module that set any `hooks:` option replaced the parent module's hooks wholesale, silently
  dropping parent hooks for other keys.

- Helper functions are now actually inherited via `extends:`, as documented. Child factory
  modules import all public functions from the full ancestor chain, so helpers like
  `generate_username()` can be called unqualified. Previously this only worked with explicit
  qualification (e.g. `MyApp.Factory.generate_username()`) despite the documentation showing
  otherwise. Note: a child module that defines a factory with the same name as one in a parent
  module will now get a compile-time import conflict error.

## [0.5.0] - 2026-06-15

### Changed

- **Breaking:** Generated insert functions no longer include a trailing `!`. For example,
  `insert_user!/0,1,2` is now `insert_user/0,1,2` and `insert_user_list!/1,2,3` is now
  `insert_user_list/1,2,3`. This aligns the API with other factory libraries and removes the
  implication that a non-bang variant exists.

## [0.4.1] - 2026-03-11

### Fixed

- `build_params?: false` no longer raises when used on non-struct factories (or inherited from a
  parent module). Non-struct factories always generate their `build_*` functions regardless of this
  option. Previously, the compile-time validation predated barebones factories and incorrectly
  rejected this combination.

## [0.4.0] - 2026-03-10

### Changed

- **Breaking:** Non-struct factories now generate `build_*/0,1` and `build_*_list/1,2` instead of
  `build_*_params/0,1` and `build_*_params_list/1,2`. The `_params` suffix was misleading for
  factories that can return any value. Struct factories are unchanged.

## [0.3.2] - 2026-03-10

### Added

- `params_for_*` and `string_params_for_*` functions for Ecto schema factories. These build a
  struct then strip Ecto metadata (`__meta__`, autogenerated IDs, `NotLoaded` associations,
  `belongs_to` structs), returning a clean map for changesets or controller tests. Foreign keys
  are set automatically for persisted `belongs_to` associations.
- Unlike ExMachina's `params_for`, nil values are preserved (not silently dropped) and
  `string_params_for` leaves struct values like `DateTime` untouched (not converted to maps).

## [0.3.1] - 2026-03-10

### Added

- Factory bodies can now return arbitrary values (strings, keyword lists, tuples, nil, etc.),
  not just maps. Factories without `:struct` are no longer restricted to returning maps.
- Lazy evaluation now works in keyword lists — 0-arity and 1-arity function values are resolved
  at build time, matching the existing behavior for maps and structs.

### Fixed

- `build_*_params_list/1` (single-arity convenience) now calls the factory with its actual default
  argument instead of always passing `%{}`. Previously, factories with non-map defaults would crash
  when using the list builder without explicit arguments.

## [0.3.0] - 2026-03-10

### Changed

- **Breaking:** Renamed `params?` option to `build_params?` for consistency with `build_struct?`

## [0.2.2] - 2026-03-10

### Added

- Duplicate option warnings: FactoryMan now emits a compile-time `Logger.warning` when a child
  factory module or `deffactory` specifies an option that is already defined by the parent with
  the same value. Helps catch redundant copy-pasted options.
- `suppress_duplicate_option_warning: true` option to silence the warning at module or factory
  level when the duplication is intentional. This option does not propagate to child modules.

## [0.2.1] - 2026-03-09

### Added

- `:as` option for `defvariant` to customize the generated function name. By default, variant
  functions are named `{variant}_{base}` (e.g. `build_admin_user_struct`). The `:as` option
  overrides this combined name (e.g. `as: :mod` generates `build_mod_struct` instead of
  `build_moderator_user_struct`).

## [0.2.0] - 2026-03-08

### Added

- `build_params?: false` option for `deffactory`. When set, the factory body returns a struct directly
  instead of a params map. No `build_*_params` functions are generated. Useful for complex
  factories that need full control over struct construction (e.g. resolving associations from
  other factories, conditional logic). Can be set at module level or factory level.
- `defvariant` macro for defining variant factories that wrap a base factory. The variant body
  is a preprocessor: it transforms caller params before delegating to the base factory. Generates
  the full set of named functions (e.g. `build_admin_user_struct/0,1`, `insert_admin_user!/0,1,2`).
- Compile-time validation: `build_params?: false` without `struct:` raises `ArgumentError`
- Compile-time validation: `defvariant` referencing undefined base factory raises `ArgumentError`

### Fixed

- Flaky "circular sequence cycles through values" test that depended on test ordering. Added
  `FactoryMan.Sequence.reset()` to ensure predictable starting position.

## [0.1.1] - 2026-03-07

### Fixed

- Factory-level hooks were being flattened into top-level options instead of staying nested under
  the `:hooks` key. This caused `_factory_opts()` and `_<name>_factory_opts()` debug functions to
  return a polluted keyword list with hook keys (e.g. `:after_insert`) mixed in alongside
  configuration keys (e.g. `:repo`, `:struct`). Hooks now stay properly nested.
- Fixed several inaccurate examples in moduledoc and README (e.g. `build_api_payload()` corrected
  to `build_api_payload_params()`, missing `Map.merge` calls in examples)

### Changed

- Replaced `List.pop_at` with `Enum.at` in `FactoryMan.Sequence` for list-based sequences
  (avoids constructing an unused remainder list)
- Reorganized demo factory definitions into logical sections: core, lazy evaluation, sequences,
  factory options, and parameter patterns
- Removed redundant demo factories (`params_only`, `with_custom_param_name`) and renamed
  `with_after_build_params_hook` to `hooked`
- Refactored test suite: reorganized into `describe` blocks by feature, removed ~21 redundant
  tests, fixed misleading test names and broken assertions. 69 tests remain (was 90), all
  meaningful.
- Added Dialyzer configuration (`plt_add_apps: [:ex_unit]`). Zero warnings.
- Expanded hooks documentation with pipeline diagram, reference table, precedence rules, and
  practical examples
- Added lazy evaluation ordering warning explaining that 1-arity lazy functions receive the
  pre-evaluation map
- Rewrote AGENTS.md with usage rules, canonical patterns, and anti-patterns

## [0.1.0] - 2026-02-08

### Added

- Initial alpha release
- `deffactory` macro for defining factories
- Automatic struct building with `build_*_struct` functions
- Database insertion with `insert_*!` functions
- Params-only factories without database dependency (i.e. only has `build_*_params` and `build_*_params_list`)
- Sequence generation for unique values
- Lazy evaluation for computed attributes
- Factory inheritance via `:extends` option
- Hooks system for custom transformations
- List factories for bulk data creation (`*_list` variants)
- Support for embedded schemas (Build struct, but do not attempt to generate `insert_*` functions)

[0.9.0]: https://github.com/arcanemachine/factory_man/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/arcanemachine/factory_man/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/arcanemachine/factory_man/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/arcanemachine/factory_man/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/arcanemachine/factory_man/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/arcanemachine/factory_man/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/arcanemachine/factory_man/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/arcanemachine/factory_man/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/arcanemachine/factory_man/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/arcanemachine/factory_man/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/arcanemachine/factory_man/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/arcanemachine/factory_man/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/arcanemachine/factory_man/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/arcanemachine/factory_man/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/arcanemachine/factory_man/releases/tag/v0.1.0
