# FactoryMan - Ideas

## Sooner

- Add documentation for factory functions with `@doc` tag.

- Add cookbook for common recipes.
  - Example: How to build assocs:

```elixir
some_has_one_assoc =
  Map.get_lazy(params, :some_has_one_assoc, fn ->
    Factory.build_vend_org_struct(params[:some_has_one_assoc] || %{})
  end)
```



## Later

- Changeset-Based Insertion - Option to insert via changeset instead of `Repo.insert!(struct)`.

- `Repo.insert_all` for list inserts - Opt-in bulk insert for `insert_*_list!` functions.

- Transient Attributes - Attributes used during building but stripped before `struct!`.
