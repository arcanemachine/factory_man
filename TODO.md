# FactoryMan - Todo

## Priority: High

- Rename generated functions: "(string_)params_for_*" -> "build_*_(string_)params"

- Look for opportunities for improvement in main resort repo.

- Improve documentation structure and flow (e.g. show base properties first)
  - Maybe show the code to a model and get it to build the documentation from the ground up.
  - Move to better (more prominent) place: Hooks, "When to Use What"

- More thorough test coverage for each type of generated item?

- docs: add mermaid diagram showing function generation hierarchy (e.g. params -> struct -> insert)

- fix: release commits should update all version numbers
  - Should do find-and-replace for version number, and increment all relevant instances that are found

- Improve `deffactory` options (Missing e.g. `build_params?`)

- Add documentation for factory functions with `@doc` tag.

- Add cookbook for common recipes:
  - How to build assocs:

```elixir
some_has_one_assoc =
  Map.get_lazy(params, :some_has_one_assoc, fn ->
    Factory.build_vend_org_struct(params[:some_has_one_assoc] || %{})
  end)
```

## Potential ideas (need to look into these)

- Changeset-Based Insertion - Option to insert via changeset instead of `Repo.insert!(struct)`.

- `Repo.insert_all` for list inserts - Opt-in bulk insert for `insert_*_list` functions.

- Transient Attributes - Attributes used during building but stripped before `struct!`. (Why would this be needed? Get some feedback on this one)
