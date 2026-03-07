# FactoryMan — Ideas & Future Features

## Features

### Traits / Variants

The most commonly requested feature in factory libraries. Currently, making an "admin" variant
requires defining a whole new factory. A traits system would reduce boilerplate:

```elixir
# Current approach — a new factory per variant:
deffactory admin(params \\ %{}), struct: User do
  %{role: "admin"} |> Map.merge(params) |> build_user_params()
end

# Possible traits API:
deffactory user(params \\ %{}), struct: User do
  %{username: sequence("user"), role: "user"} |> Map.merge(params)
end

trait :admin, for: :user do
  %{role: "admin"}
end

# Usage: build_user_struct(:admin) or build_user_struct(:admin, %{name: "Bob"})
```

Would add real value for larger projects with many schema variants.

### Changeset-Based Insertion

Currently `insert_!` calls `Repo.insert!(struct)` directly — no changeset validation. An option
to insert via changeset would enable validation at insert time, proper handling of virtual fields
and embeds, and more realistic test data:

```elixir
deffactory user(params \\ %{}), struct: User, changeset: &User.changeset/2 do
  %{username: sequence("user")} |> Map.merge(params)
end
```

### `Repo.insert_all` for List Inserts

`insert_user_list!(n)` calls `insert_user!` N times sequentially. For large N, this is slow.
An option to use `Repo.insert_all` would be significantly faster for bulk test data setup.

Trade-offs: `insert_all` skips changesets and hooks, returns different data. Could be an opt-in
via a separate function like `insert_user_batch!/1` or a flag.

### Transient Attributes

Attributes used during building but stripped before `struct!`. Useful for passing control data
that influences the build without being part of the schema:

```elixir
deffactory user(params \\ %{}), struct: User, transient: [:confirmed?] do
  base = %{username: sequence("user"), confirmed?: true}
  merged = Map.merge(base, params)

  if merged.confirmed? do
    Map.put(merged, :confirmed_at, DateTime.utc_now())
  else
    merged
  end
end

# confirmed? is used during build but won't be passed to struct!()
```

### `build_pair` / `insert_pair!` Convenience

Minor convenience for the common "I need exactly 2" pattern in tests:

```elixir
{user1, user2} = MyFactory.build_user_struct_pair()
{admin1, admin2} = MyFactory.insert_admin_pair!(%{role: "admin"})
```

Trivial to implement — just calls the list variant with count 2 and returns a tuple.

## API / Interface

### Auto-Merge Option

Every factory body ends with `Map.merge(base_params, params)`. An opt-in auto-merge mode
could reduce this boilerplate:

```elixir
# Current (explicit merge — full control):
deffactory user(params \\ %{}), struct: User do
  %{username: sequence("user")} |> Map.merge(params)
end

# Possible auto-merge mode:
deffactory user(params \\ %{}), struct: User, merge: :auto do
  %{username: sequence("user")}
  # params merged automatically by FactoryMan
end
```

Trade-off: loses the flexibility of factories that do more complex things (like piping through
another factory). The explicit merge approach is intentional and not much boilerplate in practice.
This is a low-priority idea.

## Documentation

### Options Precedence Table

A concise table showing exactly what wins at each level of the options cascade:

```
Parent module opts  →  Child module opts  →  Factory-level opts
     (use FactoryMan)     (use FactoryMan, extends:)   (deffactory ..., opts)
```

Later levels override earlier ones for the same key. Hooks are merged (not replaced) across
levels, but a factory-level hook overrides a module-level hook for the same hook key.
