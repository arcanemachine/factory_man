# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-02-08

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
