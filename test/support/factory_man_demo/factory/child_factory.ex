defmodule FactoryManDemo.Factory.ChildFactory do
  use FactoryMan, extends: FactoryManDemo.Factory

  alias FactoryManDemo.EmbeddedSchema
  alias FactoryManDemo.Authors.Author
  alias FactoryManDemo.Users.User

  # ── Core factories ───────────────────────────────────────────────

  deffactory user(params \\ %{}), struct: User do
    base_params = %{username: "user-#{System.os_time()}"}

    Map.merge(base_params, params)
  end

  deffactory author(params \\ %{}), struct: Author do
    base_params = %{
      user: params[:user] || build_user_struct(),
      name: "Some author"
    }

    Map.merge(base_params, params)
  end

  deffactory extended_user(params \\ %{}), struct: User do
    base_params = %{username: Map.get(params, :username, "extended-user-#{System.os_time()}")}

    base_params |> Map.merge(params) |> build_user_params()
  end

  deffactory embedded_schema(params \\ %{}), struct: EmbeddedSchema do
    base_params = %{some_field: "some value"}

    Map.merge(base_params, params)
  end

  deffactory non_struct(params \\ %{}) do
    base_params = %{
      name: "name-#{System.os_time()}",
      age: Enum.random(1..100)
    }

    Map.merge(base_params, params)
  end

  # ── Lazy evaluation ──────────────────────────────────────────────

  deffactory lazy_user(params \\ %{}), struct: User do
    base_params = %{
      username: "user-#{System.os_time()}",
      first_name: "User",
      # Lazy 0-arity: value computed at build time
      created_at: fn -> DateTime.utc_now() end,
      # Lazy 1-arity: receives the parent map
      full_name: fn user -> "#{user.first_name} Userson" end
    }

    Map.merge(base_params, params)
  end

  deffactory lazy_author(params \\ %{}), struct: Author do
    base_params = %{
      name: fn author -> "author-#{author.user.first_name}" end,
      user: params[:user] || build_lazy_user_struct()
    }

    Map.merge(base_params, params)
  end

  # ── Sequences ────────────────────────────────────────────────────

  deffactory user_sequence(params \\ %{}), struct: User do
    base_params = %{
      username: FactoryMan.sequence(:user_id, fn n -> "user-#{n}" end, start_at: System.os_time())
    }

    Map.merge(base_params, params)
  end

  deffactory user_with_role(params \\ %{}), struct: User do
    base_params = %{
      username: fn ->
        "user-#{System.os_time()}-#{FactoryMan.sequence(:user_role, ["admin", "user", "guest"])}"
      end
    }

    Map.merge(base_params, params)
  end

  # ── Variants ────────────────────────────────────────────────────

  defvariant admin(params \\ %{}), for: :user do
    Map.merge(params, %{username: "admin-#{System.os_time()}"})
  end

  defvariant guest(params \\ %{}), for: :user do
    Map.merge(%{username: "guest", first_name: "Guest"}, params)
  end

  defvariant moderator(params \\ %{}), for: :user, as: :mod do
    Map.merge(params, %{username: "mod-#{System.os_time()}"})
  end

  # ── Factory options ──────────────────────────────────────────────

  deffactory raw_user(params \\ %{}), struct: User, params?: false do
    username = Map.get(params, :username, "raw-user-#{System.os_time()}")
    %User{username: username}
  end

  deffactory non_insertable(params \\ %{}), struct: User, insert?: false do
    base_params = %{username: "user-#{System.os_time()}"}

    Map.merge(base_params, params)
  end

  deffactory hooked(params \\ %{}),
    hooks: [after_build_params: &__MODULE__.after_build_params_handler/1] do
    base_params = %{
      name: "name-#{System.os_time()}",
      age: Enum.random(1..100)
    }

    Map.merge(base_params, params)
  end

  @doc "Adds a marker key to params (used to verify hooks work)."
  def after_build_params_handler(params), do: Map.put(params, :hook_applied, true)

  # ── Parameter patterns (macro behavior) ──────────────────────────

  # Simple variable without default — params are required
  deffactory simple_required(params), struct: User do
    base_params = %{username: "required-#{System.os_time()}"}

    Map.merge(base_params, params)
  end

  # Pattern match without default — requires specific keys
  deffactory no_default_fallback(%{username: username} = params), struct: User do
    base_params = %{name: params[:name] || username}

    Map.merge(base_params, params)
  end

  # Pattern match with default — destructures but has fallback
  deffactory combined_pattern(%{first_name: first_name} = params \\ %{first_name: "Default"}),
    struct: User do
    base_params = %{
      username: "user-#{System.os_time()}",
      full_name: "#{first_name} User"
    }

    Map.merge(base_params, params)
  end

  # Nested destructuring
  deffactory nested_pattern(%{author: %{name: name}} = params), struct: User do
    base_params = %{
      username: "author-#{String.downcase(name)}"
    }

    Map.merge(base_params, params)
  end

  # Deep nested destructuring
  deffactory deep_nested(%{config: %{nested: %{value: val}}} = params), struct: User do
    base_params = %{
      username: "deep-#{val}"
    }

    Map.merge(base_params, params)
  end
end
