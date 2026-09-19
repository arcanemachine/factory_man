defmodule FactoryMan.Associations do
  @moduledoc false

  @resolver_options [:struct, :inherit]
  @keyed_resolver_options [:struct, :inherit, :default]
  @list_options [:struct, :inherit]

  @doc false
  def resolve(value, build_fun, opts \\ []) do
    validate_builder!(build_fun)
    opts = validate_options!(opts, @resolver_options)
    {expected_struct, inherit} = resolver_opts!(opts)

    resolve_value(value, build_fun, inherit, expected_struct, [])
  end

  @doc false
  def resolve_key(params, key, build_fun, opts \\ []) do
    validate_key!(key)
    validate_params_map!(params, key)
    validate_builder!(build_fun)
    opts = validate_options!(opts, @keyed_resolver_options)
    default = validate_default!(Keyword.get(opts, :default, :build))
    {expected_struct, inherit} = resolver_opts!(opts)
    context = [key: key]

    case Map.fetch(params, key) do
      {:ok, value} -> resolve_value(value, build_fun, inherit, expected_struct, context)
      :error when default == :build -> build_result!(build_fun, inherit, expected_struct, context)
      :error -> nil
    end
  end

  @doc false
  def resolve_list(values, build_fun, opts \\ []) do
    validate_builder!(build_fun)
    opts = validate_options!(opts, @list_options)
    {expected_struct, inherit} = resolver_opts!(opts)

    resolve_values(values, build_fun, inherit, expected_struct, [])
  end

  @doc false
  def resolve_list_key(params, key, build_fun, opts \\ []) do
    validate_key!(key)
    validate_params_map!(params, key)
    validate_builder!(build_fun)
    opts = validate_options!(opts, @list_options)
    {expected_struct, inherit} = resolver_opts!(opts)

    case Map.fetch(params, key) do
      {:ok, values} -> resolve_values(values, build_fun, inherit, expected_struct, key: key)
      :error -> []
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

    unless FactoryMan.Codegen.ecto_schema?(owner_schema) do
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
    # Every declared target is validated on every build, including for keys the caller omitted:
    # a mistyped factory reference should fail whether or not a test happens to exercise it.
    resolved_specs =
      Enum.map(specs, fn {key, cardinality, related_schema, target} ->
        resolver =
          association_resolver!(related_schema, target, owner_module, owner_factory_name, key)

        {key, cardinality, resolver}
      end)

    Enum.reduce(resolved_specs, params, fn {key, cardinality, resolver}, params ->
      if Map.has_key?(params, key) do
        context = [module: owner_module, factory: owner_factory_name, key: key]

        resolved =
          resolve_declared_value!(Map.fetch!(params, key), cardinality, resolver, context)

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

  # ── Value resolution ─────────────────────────────────────────────

  defp resolve_declared_value!(value, :one, {related_schema, builder}, context) do
    resolve_value(value, builder, %{}, related_schema, context)
  end

  defp resolve_declared_value!(values, :many, {related_schema, builder}, context) do
    resolve_values(values, builder, %{}, related_schema, context)
  end

  defp resolve_values(nil, _build_fun, _inherit, _expected_struct, context) do
    raise ArgumentError,
          "expected #{describe_context(context)} to be a list; got nil " <>
            "(use [] for no associated values)"
  end

  defp resolve_values(values, build_fun, inherit, expected_struct, context)
       when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.map(fn {value, index} ->
      item_context = Keyword.put(context, :index, index)

      case value do
        nil -> raise_invalid_value!(nil, item_context)
        value -> resolve_value(value, build_fun, inherit, expected_struct, item_context)
      end
    end)
  end

  defp resolve_values(other, _build_fun, _inherit, _expected_struct, context) do
    raise ArgumentError,
          "expected #{describe_context(context)} to be a list of structs and/or params maps, " <>
            "got: #{inspect(other)}"
  end

  defp resolve_value(nil, _build_fun, _inherit, _expected_struct, _context), do: nil

  defp resolve_value(value, build_fun, inherit, expected_struct, context) when is_map(value) do
    if is_struct(value) do
      validate_struct!(value, expected_struct, context)
    else
      build_result!(build_fun, Map.merge(inherit, value), expected_struct, context)
    end
  end

  defp resolve_value(value, _build_fun, _inherit, _expected_struct, context) do
    raise_invalid_value!(value, context)
  end

  defp build_result!(build_fun, params, expected_struct, context) do
    build_fun.(params) |> validate_struct!(expected_struct, context)
  end

  defp validate_struct!(value, nil, _context), do: value

  defp validate_struct!(value, expected_struct, context) do
    if is_struct(value, expected_struct) do
      value
    else
      raise ArgumentError,
            "expected #{describe_context(context)} to be a #{inspect(expected_struct)} struct, " <>
              "got: #{inspect(value)}"
    end
  end

  defp raise_invalid_value!(value, context) do
    accepted =
      if Keyword.has_key?(context, :index),
        do: "a struct or a params map",
        else: "a struct, a params map, or nil"

    raise ArgumentError,
          "expected #{describe_context(context)} to be #{accepted}, got: #{inspect(value)}"
  end

  # Renders an error context: an optional key (with an optional list index), and the owning
  # factory/module when the caller is the declarative `:associations` option.
  defp describe_context(context) do
    subject =
      case {context[:key], context[:index]} do
        {nil, nil} -> "an association"
        {nil, index} -> "association list item #{index}"
        {key, nil} -> "association #{inspect(key)}"
        {key, index} -> "association #{inspect(key)}[#{index}]"
      end

    case {context[:factory], context[:module]} do
      {nil, _} -> subject
      {factory, nil} -> "#{subject} in factory #{inspect(factory)}"
      {factory, module} -> "#{subject} in factory #{inspect(factory)} in #{inspect(module)}"
    end
  end

  # ── Declarative target resolution ────────────────────────────────

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

    builder = builder!(target_module, target_name, owner_module, owner_factory_name, key)

    {related_schema, &apply(target_module, builder, [&1])}
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

  # ── Option validation ────────────────────────────────────────────

  defp resolver_opts!(opts) do
    {validate_expected_struct!(Keyword.get(opts, :struct)),
     validate_inherit!(Keyword.get(opts, :inherit, %{}))}
  end

  defp validate_builder!(build_fun) when is_function(build_fun, 1), do: :ok

  defp validate_builder!(build_fun) do
    raise ArgumentError,
          "expected association builder to be a 1-arity function, got: #{inspect(build_fun)}"
  end

  defp validate_key!(key) when is_atom(key) and not is_nil(key), do: :ok

  defp validate_key!(key) do
    raise ArgumentError, "expected an association key atom, got: #{inspect(key)}"
  end

  defp validate_params_map!(params, _key) when is_map(params) and not is_struct(params), do: :ok

  defp validate_params_map!(params, key) do
    raise ArgumentError,
          "expected a params map to read association #{inspect(key)} from, got: #{inspect(params)}"
  end

  defp validate_default!(default) when default in [:build, nil], do: default

  defp validate_default!(default) do
    raise ArgumentError,
          "invalid :default option: #{inspect(default)}. Expected :build (default) or nil."
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

  defp duplicates(values) do
    values
    |> Enum.frequencies()
    |> Enum.filter(fn {_value, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
  end
end
