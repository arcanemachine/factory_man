import Config

config :factory_man, ecto_repos: [FactoryManDemo.Repo]

config :factory_man, FactoryManDemo.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  database: "factory_man_demo",
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: System.get_env("POSTGRES_PORT", "5432") |> String.to_integer(),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :logger, level: System.get_env("LOGGER_LEVEL", "warning") |> String.to_existing_atom()
