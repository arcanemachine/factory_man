# A variant without a body (`defvariant admin, for: :user, defaults: %{...}`) reads as a
# declaration, so projects that import this file's settings keep it without parentheses
locals_without_parens = [defvariant: 2]

[
  import_deps: [:ecto, :ecto_sql],
  subdirectories: ["priv/*/migrations"],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "priv/*/seeds.exs"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
