# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-03-09

### Added

- `:as` option for `defvariant` to customize the generated function name. By default, variant
  functions are named `{variant}_{base}` (e.g. `build_admin_user_struct`). The `:as` option
  overrides this combined name (e.g. `as: :mod` generates `build_mod_struct` instead of
  `build_moderator_user_struct`).

## [0.2.0] - 2026-03-08

### Added

- `params?: false` option for `deffactory`. When set, the factory body returns a struct directly
  instead of a params map. No `build_*_params` functions are generated. Useful for complex
  factories that need full control over struct construction (e.g. resolving associations from
  other factories, conditional logic). Can be set at module level or factory level.
- `defvariant` macro for defining variant factories that wrap a base factory. The variant body
  is a preprocessor: it transforms caller params before delegating to the base factory. Generates
  the full set of named functions (e.g. `build_admin_user_struct/0,1`, `insert_admin_user!/0,1,2`).
- Compile-time validation: `params?: false` without `struct:` raises `ArgumentError`
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
