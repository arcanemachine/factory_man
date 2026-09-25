# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.19.0] - Unreleased

### Added

- Variants without a body: `defvariant admin, for: :user, defaults: %{role: "admin"}`.
  `defaults:` is merged under the caller's params and `force:` over them, and a variant with only
  `extends:` names a combination (`defvariant banned_admin, for: :user, extends: [:admin,
  :banned]`). Both options are evaluated on every build. With `assocs:`, the values are merged
  before the associations resolve.
- `.formatter.exs` exports `locals_without_parens` for `defvariant/2`. Add `:factory_man` to
  `import_deps` (which needs the dependency in `:dev`) to keep variants without a body free of
  parentheses.

### Changed

- A key in a `body: :params` result that is not a field of the struct raises an `ArgumentError`
  that names the factory, the keys, and the fix, instead of the `KeyError` from `struct!/2`.

## [0.18.0] - 2026-09-25

### Added

- `disable:` switches off generated function families that a test suite does not use:
  `use FactoryMan, disable: [string_params: true, insert_list: true]`. The keys are `:params`,
  `:string_params`, `:struct_list`, `:params_list`, `:string_params_list`, `:insert_list` (which
  includes the `insert_via:` target lists), and `:non_struct_list`. It cascades per key, a lower
  level enables an inherited family again with `false`, and variants follow their base factory. A
  disabled function's name is free for a hand-written function.
- `__factory_man__(:opts)` and `__factory_man__(:opts, name)` include the resolved `disable:`,
  which lists the disabled families (`[]` by default).

### Changed

- `build_*_string_params` converts the built struct itself instead of calling
  `build_*_params`, so either family can be disabled alone. The result is unchanged.

## [0.17.0] - 2026-09-25

### Added

- `insert:` chooses the default insert target, used by `insert_*`, `insert_*_list`, and
  `insert_*_struct`: `:ecto` (the default, the repo's `insert!/2`), `false`, or a remote capture
  of arity 2 such as `&MyApp.Factory.put!/2`. A capture is called with the built struct and the
  caller's options, and works for any struct factory, including plain structs and embedded
  schemas. The insert hooks run around it.
- `insert_via:` adds named insert targets: `insert_via: [search: &MyApp.Factory.index!/2]`
  generates `insert_user_via_search/0,1,2`, `insert_user_via_search_list/1,2,3`, and
  `insert_user_struct_via_search/1,2` for every struct factory and variant. Targets run no hooks.
  Lower levels add a target, replace an inherited one by name, or remove it with `name: false`.
- `__factory_man__(:opts)` and `__factory_man__(:opts, name)` include the resolved `insert:` and
  `insert_via:`.

### Changed

- **Breaking:** `insert?:` is replaced by `insert:`. Replace `insert?: false` with
  `insert: false`.
- **Breaking:** two generated functions with the same name and arity (e.g. from a variant
  `admin` of `user` and a factory `admin_user`), or a generated function with the name of a
  function defined earlier in the module, raise at compile time, naming both sources. Before,
  they only produced compiler warnings, and the second definition joined the first.
- `FactoryMan.Params` is internal and no longer has published documentation. The generated
  `build_*_params` and `build_*_string_params` functions are the public interface.
- The module documentation is reorganized into a reference, with recipes moved to the Cookbook.

## [0.16.0] - 2026-09-24

### Added

- The `variants:` option combines variants when building: `build_user_struct(params, variants:
  [:admin, :confirmed])`. Every generated function of a factory accepts it, including a variant's
  own functions (the variant counts as the first in the list). The caller's params win, then later
  variants win over earlier ones, for variants that merge params last.
- `defvariant` accepts `extends:`, a list of variants of the same factory that the variant builds
  on: `defvariant senior(params \\ %{}), for: :user, extends: [:admin]`. A variant wins over the
  variants it extends. A variant that only extends others names a combination.
- `__factory_man__(:variants, factory_name)` lists a factory's variants, as `variants:` accepts
  them.
- A hook can be a list of remote captures, run in order: `after_insert: [&M.a/1, &M.b/1]`. A
  placement applies to the whole list: `{[&M.a/1, &M.b/1], :before_parent}`.
  `{[], :replace_parent}` switches off the inherited hooks for a hook name.
- `usage-rules.md`, the rules for writing factories, shipped in the package for
  [`usage_rules`](https://hex.pm/packages/usage_rules), and a cheat sheet in the documentation.

### Changed

- **Breaking:** `strict: true` also checks that the factory body keeps the params it receives. A
  field given to the body must come out of it with the same value, so a body that forgets
  `Map.merge(base_params, params)`, or a `body: :struct` body that never reads a key, raises.
  A plain map has been kept when each of its keys has been kept. Function values and association
  keys are not checked. Keys in `strict: [allow: [...]]` are exempt from both strict checks.
- **Breaking:** `for:` on `defvariant` must name a factory. A variant builds on another variant
  with `extends:` instead, so a variant of a variant is renamed: `defvariant senior(...), for:
  :admin_user` becomes `defvariant senior(...), for: :user, extends: [:admin]`, and
  `build_senior_admin_user_struct` becomes `build_senior_user_struct`.
- **Breaking:** `insert_*_struct` raises on a struct that has already been inserted (or has been
  deleted). The error names `Ecto.put_meta(struct, state: :built)` for an intended copy.
- **Breaking:** `:variants` is reserved in the options of `insert_*` and `insert_*_list`: it is
  used by FactoryMan, and every other option is passed to the repo. `insert_*_struct` rejects it.
- **Breaking:** A variant that declares `assocs:` no longer runs its strict base factory's
  unknown-key check before the variant body. The base factory checks the params after every
  variant body, so a variant can use up an input key that is not a field (and a key a variant
  drops is no longer checked).
- Error messages name the fix in more places, e.g. a keyword list given to a struct factory, an
  unknown variant, or a variant defined apart from its base factory.

## [0.15.0] - 2026-09-24

### Added

- Hook placements: a hook can be set as `{hook, :before_parent}`, `{hook, :after_parent}`, or
  `{hook, :replace_parent}` to run before, after, or instead of the hooks it inherits.
- Hook names, duplicate hook names at one level, and hook values are validated at compile time.
  A hook must be a 1-arity remote capture; anything else, such as an anonymous function, raises.

### Changed

- **Breaking:** A hook set at a lower level (child module or factory) is chained with the
  inherited hooks of the same name instead of replacing them. The order is onion-style: a
  parent's `before_*` hooks run first and its `after_*` hooks run last.
- **Breaking:** `__factory_man__(:opts)` and `__factory_man__(:opts, name)` hold each hook name's
  resolved list of functions, in run order.
- Hooks are compiled into the generated functions as direct calls, with no runtime lookup. A hook
  that points at a missing function is reported by a compile-time warning instead of failing at
  runtime.

## [0.14.0] - 2026-09-23

### Added

- **Breaking:** The `assocs:` factory option replaces `associations:`. It maps each association
  key to a builder: a 1-arity function (local or remote capture, or anonymous function), a
  2-arity function that also receives the factory params with earlier keys resolved, or
  `{builder, default: value}`. Every declared key is resolved before the factory body, so the body
  always receives it resolved and a final `Map.merge(base_params, params)` no longer restores the
  caller's raw input. The builder is the default: an absent key is built with `%{}` (or resolves
  to `[]` for a plural association) unless `default:` says otherwise.
- `defvariant` accepts `assocs:`. The variant resolves its keys before its body; the base factory
  reuses the resulting structs.
- `assocs:` is evaluated at build time, so it can hold local captures, anonymous functions, and
  shared declarations returned by a function call. It is validated when the factory first builds.
- `assocs:` checks that supplied structs and builder results are the association's schema. A
  builder for a singular association may return `nil`.
- `{builder, required: true}` in `assocs:` makes a singular association resolve to a non-nil
  value: a caller's `nil`, or a builder that returns `nil`, raises. An absent key still builds.
- A recursion guard raises when a default build starts again inside itself (a self-referential
  or mutually recursive association), instead of recursing forever. It covers `assocs:`,
  `assoc/3,4`, and `assoc_list/3,4`, and the error shows the build path.
- `assoc/3,4` accepts a params map as `default:`, and `assoc_list/3,4` accepts `default:` with a
  list of params maps.

### Changed

- **Breaking:** `use FactoryMan`, `deffactory`, and `defvariant` raise on unknown options instead
  of ignoring them.

### Removed

- **Breaking:** The `associations:` option and its factory-name targets (`:user`,
  `{Module, :user}`). Use `assocs:` with function captures.
- **Breaking:** `FactoryMan.resolve_assoc/2,3` and `FactoryMan.resolve_assoc_list/2,3`.
- **Breaking:** The `struct:` and `inherit:` options of `assoc/3,4` and `assoc_list/3,4`. Close
  over extra params in the builder instead: `&build_user_struct(Map.merge(%{role: "writer"}, &1))`.

## [0.13.0] - 2026-09-19

### Added

- `FactoryMan.assoc/3,4` and `FactoryMan.assoc_list/3,4` read an association from a factory's
  params map by key. An absent key builds the default (`assoc`) or resolves to `[]`
  (`assoc_list`); `assoc/3,4` accepts `default: nil` for an association that should only exist
  when the caller supplies one.
- `FactoryMan.resolve_assoc/2,3` and `FactoryMan.resolve_assoc_list/2,3` resolve a value or list
  directly, for helpers that hold the value instead of a params map.
- Struct factories raise when given something other than a params map, instead of failing later
  inside the factory body.

### Changed

- **Breaking:** An explicit `nil` is preserved by the keyed helpers, the value helpers, and the
  declarative `:associations` option. The `:on_nil` option is removed; a factory that needs a
  record for a nil value provides the fallback in its own body.
- **Breaking:** `assoc_list` raises on a nil collection instead of resolving it to an empty list,
  matching declarative `:many`. Use `[]` for no associated values.
- **Breaking:** The value-based `assoc/2,3` and `assoc_list/2,3` from 0.12.0 are renamed to
  `resolve_assoc` and `resolve_assoc_list`. The `assoc` names now take a params map and a key.
- **Breaking:** Lazy values are resolved in two passes: the 0-arity functions, then the 1-arity
  ones. A 1-arity function now receives resolved 0-arity values instead of function references.
- **Breaking:** `body: :struct` factories lazily evaluate the struct their body returns. Function
  values in those fields were previously stored as-is.
- **Breaking:** `:associations` is rejected as a module-level option. Association keys belong to
  one schema, so cascading them would apply a factory's keys to every struct in the module.
- Association errors now name the failing key, and the item index for list associations.
- Documented the association tiers and their nil rules, when to reach for declarative versus
  imperative resolution, and how to keep an imperatively resolved value through a factory body's
  final `Map.merge/2`.

## [0.12.1] - 2026-09-18

### Changed

- Internal macro and build-pipeline helpers are hidden from the generated public API documentation.

## [0.12.0] - 2026-09-17

### Added

- Declarative `associations:` support for Ecto-backed factories. Association schemas and
  cardinality are derived from Ecto; same-module factories use atom references and cross-module
  factories use `{FactoryModule, :factory}` references. Caller-provided nested params are
  normalized into associated structs while missing keys continue to use factory defaults.

### Changed

- Reworked the cookbook into a task-oriented, beginner-to-advanced guide with realistic test
  examples covering generated builders, sequences, lazy values, variants, associations, strict
  params, non-struct factories, inheritance, hooks, specialized construction, and debugging.
- **Breaking:** `FactoryMan.assoc/2,3` and `FactoryMan.assoc_list/2,3` now resolve a value or list
  directly instead of extracting a value from a parent params map. The keyed interfaces and
  `on_missing:` option are removed.
- The low-level helpers' optional `struct:` check now validates builder results as well as supplied
  structs. Invalid builder results raise `ArgumentError`.

## [0.11.1] - 2026-09-15

### Changed

- Documentation now distinguishes struct and non-struct factory function families, explains
  when each generated builder and insert function is useful, and documents multi-level factory
  inheritance and child option overrides.
- Sequence documentation now describes cycling lists, `:start_at`, and reset behavior accurately.

### Fixed

- `FactoryMan.sequence/3` now has a formatter-function type spec that matches its implementation.
  Lists remain supported by `sequence/2`.

## [0.11.0] - 2026-07-03

### Removed

- **Breaking:** Duplicate option warnings (and the `:suppress_duplicate_option_warning` option)
  are removed. The warning could only ever flag harmless same-value redundancy, yet failed
  builds under `--warnings-as-errors` and needed its own suppression escape hatch. Redundancy
  linting belongs in consumer-side tooling.
- **Breaking:** The compile-time tombstone errors for the options removed or renamed in 0.6.0
  (`build_params?`, `build_struct?`) are removed. Legacy keys are now ignored like any other
  unknown option.

## [0.10.0] - 2026-07-03

### Changed

- **Breaking:** `use FactoryMan` no longer imports `assoc/3,4` and `assoc_list/3,4`. Helper
  functions are always called qualified (`FactoryMan.assoc(...)`, `FactoryMan.sequence(...)`),
  making their origin explicit and avoiding collisions with generic names elsewhere (e.g.
  `Ecto.assoc/2`). Only the definition macros `deffactory`/`defvariant` remain imported —
  they read as DSL keywords. Documentation examples previously showed `sequence(...)` bare even
  though it was never imported; all examples now use the qualified form that actually compiles.

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

[0.12.1]: https://github.com/arcanemachine/factory_man/compare/v0.12.0...v0.12.1
[0.12.0]: https://github.com/arcanemachine/factory_man/compare/v0.11.1...v0.12.0
[0.11.1]: https://github.com/arcanemachine/factory_man/compare/v0.11.0...v0.11.1
[0.11.0]: https://github.com/arcanemachine/factory_man/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/arcanemachine/factory_man/compare/v0.9.0...v0.10.0
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
