defmodule FactoryMan.Associations do
  @moduledoc false

  @resolver_options [:struct, :inherit, :on_nil]
  @list_options [:struct, :inherit]

  @doc false
  def resolve(value, build_fun, opts \\ []) do
    validate_builder!(build_fun)
    opts = validate_options!(opts, @resolver_options)
    expected_struct = validate_expected_struct!(Keyword.get(opts, :struct))
    inherit = validate_inherit!(Keyword.get(opts, :inherit, %{}))
    on_nil = Keyword.get(opts, :on_nil, :build)

    if on_nil not in [:build, :keep] do
      raise ArgumentError,
            "invalid :on_nil option: #{inspect(on_nil)}. Expected :build (default) or :keep."
    end

    resolve_value(value, build_fun, inherit, expected_struct, on_nil, :association)
  end

  @doc false
  def resolve_list(values, build_fun, opts \\ []) do
    validate_builder!(build_fun)
    opts = validate_options!(opts, @list_options)
    expected_struct = validate_expected_struct!(Keyword.get(opts, :struct))
    inherit = validate_inherit!(Keyword.get(opts, :inherit, %{}))

    case values do
      nil ->
        []

      values when is_list(values) ->
        Enum.with_index(values)
        |> Enum.map(fn {value, index} ->
          resolve_value(value, build_fun, inherit, expected_struct, :reject, {:list, index})
        end)

      other ->
        raise ArgumentError,
              "expected an association list of structs and/or params maps, got: #{inspect(other)}"
    end
  end

  @doc false
  def compile_specs!(_owner_module, _owner_factory_name, _owner_schema, associations)
      when is_nil(associations) or associations == [],
      do: []

  def compile_specs!(owner_module, owner_factory_name, owner_schema, associations)
      when is_list(associations) do
    unless Keyword.keyword?(associations) do
      raise ArgumentError,
            ":associations for factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
              "must be a keyword list, got: #{inspect(associations)}"
    end

    unless ecto_schema?(owner_schema) do
      raise ArgumentError,
            "factory :#{owner_factory_name} in #{inspect(owner_module)} uses :associations, " <>
              "but its :struct is not an Ecto schema"
    end

    duplicate_keys = associations |> Keyword.keys() |> duplicates()

    if duplicate_keys != [] do
      raise ArgumentError,
            "duplicate association keys #{inspect(duplicate_keys)} for factory " <>
              ":#{owner_factory_name} in #{inspect(owner_module)}"
    end

    Enum.map(associations, fn {key, target} ->
      unless is_atom(key) do
        raise ArgumentError,
              "association keys for factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
                "must be atoms, got: #{inspect(key)}"
      end

      association =
        try do
          owner_schema.__schema__(:association, key)
        rescue
          _ -> nil
        end

      if is_nil(association) do
        raise ArgumentError,
              "association :#{key} for factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
                "is not defined on #{inspect(owner_schema)}"
      end

      if Map.get(association, :through) not in [nil, []] do
        raise ArgumentError,
              "association :#{key} for factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
                "is a through association, which is not supported"
      end

      target = normalize_target!(target, owner_module, owner_factory_name, key)
      cardinality = Map.get(association, :cardinality)
      related_schema = Map.get(association, :related)

      if cardinality not in [:one, :many] or is_nil(related_schema) do
        raise ArgumentError,
              "could not determine the type of association :#{key} for factory " <>
                ":#{owner_factory_name} in #{inspect(owner_module)}"
      end

      {key, cardinality, related_schema, target}
    end)
  end

  def compile_specs!(owner_module, owner_factory_name, _owner_schema, associations) do
    raise ArgumentError,
          ":associations for factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
            "must be a keyword list, got: #{inspect(associations)}"
  end

  @doc false
  def normalize_params!(params, [], _owner_module, _owner_factory_name), do: params

  def normalize_params!(params, specs, owner_module, owner_factory_name) when is_map(params) do
    resolved_specs =
      Enum.map(specs, fn {key, cardinality, related_schema, target} ->
        resolver =
          association_resolver!(
            related_schema,
            target,
            owner_module,
            owner_factory_name,
            key
          )

        {key, cardinality, related_schema, resolver}
      end)

    Enum.reduce(resolved_specs, params, fn {key, cardinality, related_schema, resolver}, params ->
      if Map.has_key?(params, key) do
        value = Map.fetch!(params, key)

        resolved =
          resolve_declared_value!(
            value,
            cardinality,
            related_schema,
            resolver,
            owner_module,
            owner_factory_name,
            key
          )

        Map.put(params, key, resolved)
      else
        params
      end
    end)
  end

  def normalize_params!(params, _specs, owner_module, owner_factory_name) do
    raise ArgumentError,
          "expected params for factory :#{owner_factory_name} in #{inspect(owner_module)} to be a " <>
            "map when :associations are configured, got: #{inspect(params)}"
  end

  defp resolve_declared_value!(
         value,
         :one,
         related_schema,
         resolver,
         owner_module,
         owner_factory_name,
         key
       ) do
    resolve_with_resolver!(value, related_schema, resolver, owner_module, owner_factory_name, key)
  end

  defp resolve_declared_value!(
         nil,
         :many,
         _related_schema,
         _target,
         owner_module,
         owner_factory_name,
         key
       ) do
    raise ArgumentError,
          "expected association :#{key} in factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
            "to be a list; got nil (use [] for no associated records)"
  end

  defp resolve_declared_value!(
         values,
         :many,
         related_schema,
         resolver,
         owner_module,
         owner_factory_name,
         key
       )
       when is_list(values) do
    Enum.with_index(values)
    |> Enum.map(fn
      {nil, index} ->
        raise ArgumentError,
              "expected association :#{key}[#{index}] in factory :#{owner_factory_name} in " <>
                "#{inspect(owner_module)} to be a #{inspect(related_schema)} struct or a params map, " <>
                "got: nil"

      {value, index} ->
        resolve_with_resolver!(
          value,
          related_schema,
          resolver,
          owner_module,
          owner_factory_name,
          "#{key}[#{index}]"
        )
    end)
  end

  defp resolve_declared_value!(
         value,
         :many,
         _related_schema,
         _target,
         owner_module,
         owner_factory_name,
         key
       ) do
    raise ArgumentError,
          "expected association :#{key} in factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
            "to be a list of structs and/or params maps, got: #{inspect(value)}"
  end

  defp association_resolver!(
         related_schema,
         {target_module, target_name},
         owner_module,
         owner_factory_name,
         key
       ) do
    target_schema =
      target_schema!(target_module, target_name, owner_module, owner_factory_name, key)

    if target_schema != related_schema do
      raise ArgumentError,
            "association :#{key} in factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
              "expects #{inspect(related_schema)}, but #{inspect(target_module)} factory " <>
              ":#{target_name} declares #{inspect(target_schema)}"
    end

    {target_module, builder!(target_module, target_name, owner_module, owner_factory_name, key)}
  end

  defp resolve_with_resolver!(
         value,
         related_schema,
         {target_module, builder},
         owner_module,
         owner_factory_name,
         key
       ) do
    case value do
      nil ->
        nil

      value when is_map(value) ->
        if is_struct(value) do
          validate_result!(value, related_schema, owner_module, owner_factory_name, key)
        else
          result = apply(target_module, builder, [value])
          validate_result!(result, related_schema, owner_module, owner_factory_name, key)
        end

      other ->
        raise ArgumentError,
              "expected association :#{key} in factory :#{owner_factory_name} in " <>
                "#{inspect(owner_module)} to be a #{inspect(related_schema)} struct or a params " <>
                "map, got: #{inspect(other)}"
    end
  end

  defp target_schema!(target_module, target_name, owner_module, owner_factory_name, key) do
    ensure_factory_module!(target_module, owner_module, owner_factory_name, key)

    factories = apply(target_module, :__factory_man__, [:factories])

    unless target_name in factories do
      raise ArgumentError,
            "association :#{key} in factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
              "references unknown factory :#{target_name} in #{inspect(target_module)}"
    end

    target_opts = apply(target_module, :__factory_man__, [:opts, target_name])
    target_schema = Keyword.get(target_opts, :struct)

    if is_nil(target_schema) do
      raise ArgumentError,
            "association :#{key} in factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
              "references non-struct factory :#{target_name} in #{inspect(target_module)}"
    end

    target_schema
  end

  defp builder!(target_module, target_name, owner_module, owner_factory_name, key) do
    builder = :"build_#{target_name}_struct"

    unless function_exported?(target_module, builder, 1) do
      raise ArgumentError,
            "association :#{key} in factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
              "cannot use #{inspect(target_module)} factory :#{target_name}: " <>
              "#{builder}/1 is not exported"
    end

    builder
  end

  defp ensure_factory_module!(target_module, owner_module, owner_factory_name, key) do
    unless is_atom(target_module) do
      raise ArgumentError,
            "association :#{key} in factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
              "has an invalid factory module: #{inspect(target_module)}"
    end

    case Code.ensure_loaded(target_module) do
      {:module, ^target_module} ->
        if function_exported?(target_module, :__factory_man__, 1) and
             function_exported?(target_module, :__factory_man__, 2) do
          :ok
        else
          raise ArgumentError,
                "association :#{key} in factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
                  "references #{inspect(target_module)}, which is not a FactoryMan module"
        end

      {:error, reason} ->
        raise ArgumentError,
              "association :#{key} in factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
                "could not load factory module #{inspect(target_module)}: #{inspect(reason)}"
    end
  end

  defp resolve_value(nil, build_fun, inherit, expected_struct, :build, _context) do
    build_result!(build_fun, inherit, expected_struct)
  end

  defp resolve_value(nil, _build_fun, _inherit, _expected_struct, :keep, _context), do: nil

  defp resolve_value(nil, _build_fun, _inherit, _expected_struct, :reject, context) do
    raise_invalid_value!(nil, context)
  end

  defp resolve_value(value, build_fun, inherit, expected_struct, _on_nil, context)
       when is_map(value) do
    if is_struct(value) do
      validate_result!(value, expected_struct, context)
    else
      build_result!(build_fun, Map.merge(inherit, value), expected_struct)
    end
  end

  defp resolve_value(value, _build_fun, _inherit, _expected_struct, _on_nil, context) do
    raise_invalid_value!(value, context)
  end

  defp build_result!(build_fun, params, nil), do: build_fun.(params)

  defp build_result!(build_fun, params, expected_struct) do
    result = build_fun.(params)
    validate_result!(result, expected_struct, :association)
  end

  defp validate_result!(value, nil, _owner_module, _owner_factory_name, _key), do: value

  defp validate_result!(value, expected_struct, owner_module, owner_factory_name, key) do
    if is_struct(value, expected_struct) do
      value
    else
      raise ArgumentError,
            "expected association #{inspect(key)} to be a #{inspect(expected_struct)} struct, got: " <>
              "#{inspect(value)} (in factory :#{owner_factory_name} in #{inspect(owner_module)})"
    end
  end

  defp validate_result!(value, expected_struct, context) do
    if is_nil(expected_struct) or is_struct(value, expected_struct) do
      value
    else
      raise ArgumentError,
            "expected association value in #{inspect(context)} to be a " <>
              "#{inspect(expected_struct)} struct, got: #{inspect(value)}"
    end
  end

  defp raise_invalid_value!(value, :association) do
    raise ArgumentError,
          "expected an association to be a struct, a params map, or nil, got: #{inspect(value)}"
  end

  defp raise_invalid_value!(value, {:list, index}) do
    raise ArgumentError,
          "expected association list item #{index} to be a struct or a params map, got: " <>
            "#{inspect(value)}"
  end

  defp validate_builder!(build_fun) when is_function(build_fun, 1), do: :ok

  defp validate_builder!(build_fun) do
    raise ArgumentError,
          "expected association builder to be a 1-arity function, got: #{inspect(build_fun)}"
  end

  defp validate_options!(opts, allowed) when is_list(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError,
            "expected association options to be a keyword list, got: #{inspect(opts)}"
    end

    unknown = Keyword.keys(opts) -- allowed

    if unknown != [] do
      raise ArgumentError,
            "invalid association options #{inspect(unknown)}. Allowed options: #{inspect(allowed)}"
    end

    opts
  end

  defp validate_options!(opts, _allowed) do
    raise ArgumentError,
          "expected association options to be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_expected_struct!(nil), do: nil

  defp validate_expected_struct!(struct) when is_atom(struct) do
    case Code.ensure_loaded(struct) do
      {:module, ^struct} ->
        if function_exported?(struct, :__struct__, 0) do
          struct
        else
          raise ArgumentError,
                "expected association :struct option to name a struct module, got: #{inspect(struct)}"
        end

      {:error, _reason} ->
        raise ArgumentError,
              "expected association :struct option to name a loaded struct module, got: #{inspect(struct)}"
    end
  end

  defp validate_expected_struct!(struct) do
    raise ArgumentError,
          "expected association :struct option to be a module, got: #{inspect(struct)}"
  end

  defp validate_inherit!(inherit) when is_map(inherit) and not is_struct(inherit), do: inherit

  defp validate_inherit!(inherit) do
    raise ArgumentError,
          "expected association :inherit option to be a params map, got: #{inspect(inherit)}"
  end

  defp normalize_target!(factory_name, owner_module, _owner_factory_name, _key)
       when is_atom(factory_name),
       do: {owner_module, factory_name}

  defp normalize_target!({module, factory_name}, _owner_module, _owner_factory_name, _key)
       when is_atom(module) and is_atom(factory_name),
       do: {module, factory_name}

  defp normalize_target!(target, owner_module, owner_factory_name, key) do
    raise ArgumentError,
          "association :#{key} for factory :#{owner_factory_name} in #{inspect(owner_module)} " <>
            "must reference a factory name or {module, factory_name}, got: #{inspect(target)}"
  end

  defp ecto_schema?(module) do
    match?({:module, _}, Code.ensure_compiled(module)) and
      function_exported?(module, :__schema__, 1)
  end

  defp duplicates(values) do
    values
    |> Enum.frequencies()
    |> Enum.filter(fn {_value, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
  end
end
