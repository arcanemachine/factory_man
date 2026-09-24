defmodule FactoryMan.Associations do
  @moduledoc false

  # The process dictionary holds the stack of builds in progress, innermost first. Factory
  # entries (`{:factory, module, name, root}`) exist only for error messages; `root` is the base
  # factory of a variant (or the factory itself). Default build entries
  # (`{:default, key, builder_identity}`) drive the recursion guard.
  @build_stack :factory_man_build_stack

  ## Build tracking

  @doc false
  def track_factory(module, factory_name, root_name \\ nil, fun) do
    with_entry({:factory, module, factory_name, root_name || factory_name}, fun)
  end

  defp with_entry(entry, fun) do
    previous = Process.get(@build_stack, [])
    Process.put(@build_stack, [entry | previous])

    try do
      fun.()
    after
      Process.put(@build_stack, previous)
    end
  end

  ## `assocs:` option

  @doc false
  def validate_schema!(schema, module, factory_name) do
    cond do
      is_nil(schema) ->
        raise ArgumentError,
              "factory :#{factory_name} in #{inspect(module)} uses assocs:, which requires " <>
                "struct: to be an Ecto schema"

      not FactoryMan.Codegen.ecto_schema?(schema) ->
        raise ArgumentError,
              "factory :#{factory_name} in #{inspect(module)} uses assocs:, but " <>
                "#{inspect(schema)} is not an Ecto schema"

      true ->
        :ok
    end
  end

  @doc false
  def resolve_assocs!(params, _specs, _schema, module, factory_name) when not is_map(params) do
    raise ArgumentError,
          "expected a params map for factory :#{factory_name} in #{inspect(module)}, " <>
            "got: #{inspect(params)}"
  end

  def resolve_assocs!(params, specs, schema, module, factory_name) do
    specs = validate_specs!(specs, schema, module, factory_name)
    declared_keys = Enum.map(specs, &elem(&1, 0))

    # Keys resolve top to bottom. A builder sees the keys declared above it resolved, and not the
    # raw input of the current key or of any key declared below it.
    {params, []} =
      Enum.reduce(specs, {params, declared_keys}, fn
        {key, cardinality, related, builder, default, required}, {params, [key | later_keys]} ->
          factory_params = Map.drop(params, [key | later_keys])
          build = &call_builder(builder, &1, factory_params)

          context = %{
            module: module,
            factory: factory_name,
            key: key,
            source: :assocs,
            related: related,
            required: required
          }

          value =
            case Map.fetch(params, key) do
              {:ok, value} -> resolve(value, cardinality, build, context)
              :error -> resolve_default(default, cardinality, builder, build, context)
            end

          {Map.put(params, key, value), later_keys}
      end)

    params
  end

  defp call_builder(builder, params, _factory_params) when is_function(builder, 1),
    do: builder.(params)

  defp call_builder(builder, params, factory_params), do: builder.(params, factory_params)

  defp validate_specs!(specs, schema, module, factory_name) do
    unless is_list(specs) and Keyword.keyword?(specs) do
      raise ArgumentError,
            "assocs: for factory :#{factory_name} in #{inspect(module)} must be a keyword list, " <>
              "got: #{inspect(specs)}"
    end

    case specs |> Keyword.keys() |> duplicates() do
      [] ->
        :ok

      duplicate_keys ->
        raise ArgumentError,
              "duplicate assocs: keys #{inspect(duplicate_keys)} for factory :#{factory_name} " <>
                "in #{inspect(module)}"
    end

    Enum.map(specs, fn {key, spec} ->
      context = %{module: module, factory: factory_name, key: key, source: :assocs}
      association = association!(schema, context)
      {builder, opts} = builder_spec!(spec, context)
      required = required!(opts, association.cardinality, context)

      default =
        opts
        |> Keyword.get(:default, :implicit)
        |> validate_default!(association.cardinality, context)
        |> reject_records!(association.related, context)

      {key, association.cardinality, association.related, builder, default, required}
    end)
  end

  defp association!(schema, context) do
    association = schema.__schema__(:association, context.key)

    cond do
      is_nil(association) ->
        raise ArgumentError,
              "#{describe(context)} is not an association of #{inspect(schema)} " <>
                "(embeds are not supported)"

      Map.get(association, :through) not in [nil, []] ->
        raise ArgumentError,
              "#{describe(context)} is a :through association, which cannot be declared; " <>
                "resolve it in a builder or the body"

      true ->
        association
    end
  end

  defp builder_spec!(builder, _context) when is_function(builder, 1) or is_function(builder, 2),
    do: {builder, []}

  defp builder_spec!({builder, opts} = spec, context)
       when is_function(builder, 1) or is_function(builder, 2) do
    valid? =
      is_list(opts) and Keyword.keyword?(opts) and opts != [] and
        Keyword.keys(opts) -- [:default, :required] == [] and
        duplicates(Keyword.keys(opts)) == []

    if valid?, do: {builder, opts}, else: raise_invalid_spec!(spec, context)
  end

  defp builder_spec!(spec, context), do: raise_invalid_spec!(spec, context)

  defp raise_invalid_spec!(spec, context) do
    raise ArgumentError,
          "#{describe(context)} must be a 1- or 2-arity function, or {function, options} with " <>
            "default: and/or required:, got: #{inspect(spec)}"
  end

  # `required: false` is a no-op on any key, so a shared declaration can compute the flag
  defp required!(opts, cardinality, context) do
    case Keyword.get(opts, :required, false) do
      false ->
        false

      true when cardinality == :many ->
        raise ArgumentError,
              "#{describe(context)} is a list, so required: does not apply: nil already raises " <>
                "for lists, and required: is not a non-emptiness check"

      true ->
        if Keyword.has_key?(opts, :default) and is_nil(opts[:default]) do
          raise ArgumentError,
                "#{describe(context)} is required, so default: nil contradicts it"
        end

        true

      other ->
        raise ArgumentError,
              "required: for #{describe(context)} must be true or false, got: #{inspect(other)}"
    end
  end

  ## Imperative helpers

  @doc false
  def resolve_key(params, key, builder, opts, cardinality) do
    context = %{key: key, source: :helper}
    validate_helper_args!(params, key, builder, context)
    default = helper_default!(opts, cardinality, context)

    case Map.fetch(params, key) do
      {:ok, value} -> resolve(value, cardinality, builder, context)
      :error -> resolve_default(default, cardinality, builder, builder, context)
    end
  end

  defp validate_helper_args!(params, key, builder, context) do
    unless is_map(params) and not is_struct(params) do
      raise ArgumentError,
            "expected a params map to read #{describe(context)} from, got: #{inspect(params)}"
    end

    unless is_atom(key) and not is_nil(key) do
      raise ArgumentError, "expected an association key atom, got: #{inspect(key)}"
    end

    unless is_function(builder, 1) do
      raise ArgumentError,
            "expected the builder for #{describe(context)} to be a 1-arity function, " <>
              "got: #{inspect(builder)}"
    end
  end

  defp helper_default!([], cardinality, context),
    do: validate_default!(:implicit, cardinality, context)

  defp helper_default!([default: default], cardinality, context),
    do: validate_default!(default, cardinality, context)

  defp helper_default!(opts, _cardinality, context) do
    raise ArgumentError,
          "invalid options for #{describe(context)}: #{inspect(opts)}. " <>
            "The only option is default:"
  end

  ## Defaults

  defp validate_default!(:implicit, :one, _context), do: %{}
  defp validate_default!(:implicit, :many, _context), do: []
  defp validate_default!(nil, :one, _context), do: nil

  defp validate_default!(nil, :many, context) do
    raise ArgumentError, "#{describe(context)} is a list, so default: nil is invalid; use []"
  end

  defp validate_default!(default, :one, _context)
       when is_map(default) and not is_struct(default),
       do: default

  defp validate_default!(default, :many, context) when is_list(default) do
    if Enum.all?(default, &(is_map(&1) and not is_struct(&1))) do
      default
    else
      raise_invalid_default!(default, "a list of params maps", context)
    end
  end

  defp validate_default!(default, :one, context),
    do: raise_invalid_default!(default, "nil or a params map", context)

  defp validate_default!(default, :many, context),
    do: raise_invalid_default!(default, "a list of params maps", context)

  defp raise_invalid_default!(default, expected, context) do
    raise ArgumentError,
          "default: for #{describe(context)} must be #{expected}, got: #{inspect(default)}"
  end

  # Defaults are evaluated on every build, so a record built inside one would be built (and maybe
  # inserted) even when the caller supplies the key. Only association positions are checked: a
  # struct in any other field (a date, an embed, data in a map field) is a plain value.
  defp reject_records!(default, related_schema, context) do
    case find_record(default, related_schema, []) do
      nil ->
        default

      {record, path} ->
        raise ArgumentError,
              "default: for #{describe(context)} has a %#{inspect(record.__struct__)}{} record at " <>
                "association #{Enum.map_join(path, ".", &inspect/1)}. Defaults are evaluated on " <>
                "every build, so use params; put build logic in the builder."
    end
  end

  defp find_record(items, schema, path) when is_list(items) do
    Enum.find_value(items, &find_record(&1, schema, path))
  end

  defp find_record(params, schema, path) when is_map(params) and not is_struct(params) do
    Enum.find_value(params, fn {key, value} ->
      case schema.__schema__(:association, key) do
        nil -> nil
        association -> find_record_at(value, association.related, path ++ [key])
      end
    end)
  end

  defp find_record(_value, _schema, _path), do: nil

  defp find_record_at(value, _schema, path) when is_struct(value), do: {value, path}

  defp find_record_at(values, schema, path) when is_list(values) do
    Enum.find_value(values, &find_record_at(&1, schema, path))
  end

  defp find_record_at(value, schema, path), do: find_record(value, schema, path)

  # An absent key is treated as its default. A default that builds something is tracked by the
  # recursion guard; `nil` and `[]` build nothing.
  defp resolve_default(default, cardinality, _builder, build, context)
       when default in [nil, []],
       do: resolve(default, cardinality, build, context)

  defp resolve_default(default, cardinality, builder, build, context) do
    entry = {:default, context.key, builder_identity(builder)}
    stack = Process.get(@build_stack, [])

    if entry in stack do
      raise_recursion!(entry, stack, cardinality, context)
    end

    with_entry(entry, fn -> resolve(default, cardinality, build, context) end)
  end

  # Closures created at the same code site share an identity whatever they capture, so a loop
  # through closures is still caught. `&b/1` and `&M.b/1` also share one.
  defp builder_identity(builder) do
    info = Function.info(builder)
    {info[:module], info[:name], info[:arity]}
  end

  defp raise_recursion!({:default, key, _identity} = entry, stack, cardinality, context) do
    path = stack |> Enum.reverse() |> Enum.map(&path_label/1)
    loop = Enum.take_while(stack, &(&1 != entry))
    loop_roots = for {:factory, module, _name, root} <- loop, uniq: true, do: {module, root}
    kind = if length(loop_roots) > 1, do: "mutually recursive", else: "self-referential"

    owner = calling_factory(stack)
    rebuilt = owner && elem(owner, 2)

    subject =
      case owner do
        {:factory, module, name, _root} ->
          "association #{inspect(key)} in factory #{inspect(name)} in #{inspect(module)}"

        nil ->
          "association #{inspect(key)}"
      end

    rebuilds = if rebuilt, do: "builds #{inspect(rebuilt)} again", else: "starts again"
    empty = if cardinality == :one, do: "nil", else: "[]"

    # A required key cannot default to nil, so a value from the caller is the only fix
    fix =
      case context do
        %{required: true} ->
          "Pass a value (a struct or params)."

        %{source: :assocs} ->
          "Declare it as {builder, default: #{empty}}, or pass a value (nil, a struct, or params)."

        %{source: :helper} ->
          "Pass default: #{empty}, or pass a value (nil, a struct, or params)."
      end

    raise ArgumentError, """
    #{subject} is #{kind}: building it by default #{rebuilds}, which recurses forever.
    Build path: #{Enum.join(path ++ [inspect(key)], " → ")}
    #{fix}
    If the recursion is meant to stop on its own, supply the key at each level instead.\
    """
  end

  # The innermost factory being built. A variant delegates to its base, so when the base sits
  # directly inside its variant, the variant is the factory that was called.
  defp calling_factory(stack) do
    case Enum.drop_while(stack, &match?({:default, _, _}, &1)) do
      [{:factory, module, _name, root} | _] = entries ->
        entries
        |> Enum.take_while(&match?({:factory, ^module, _, ^root}, &1))
        |> List.last()

      _ ->
        nil
    end
  end

  defp path_label({:factory, _module, name, _root}), do: inspect(name)
  defp path_label({:default, key, _identity}), do: inspect(key)

  ## Resolution rules

  defp resolve(nil, :one, _build, %{required: true} = context) do
    raise ArgumentError, "#{describe_calling(context)} is required, got nil"
  end

  defp resolve(nil, :one, _build, _context), do: nil

  # A builder may decide there is no associated value, so `nil` from a builder is kept
  defp resolve(value, :one, _build, context) when is_struct(value), do: check!(value, context)

  defp resolve(value, :one, build, context) when is_map(value) do
    case build.(value) do
      nil ->
        if Map.get(context, :required, false) do
          raise ArgumentError,
                "the builder for #{describe_calling(context)} returned nil, but the " <>
                  "association is required"
        end

        nil

      built ->
        check!(built, context)
    end
  end

  defp resolve(value, :one, _build, context) do
    raise ArgumentError,
          "expected #{describe(context)} to be a struct, a params map, or nil, " <>
            "got: #{inspect(value)}"
  end

  defp resolve(nil, :many, _build, context) do
    raise ArgumentError, "expected #{describe(context)} to be a list, got nil (use [])"
  end

  defp resolve(values, :many, build, context) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.map(fn
      {value, index} when is_struct(value) ->
        check!(value, Map.put(context, :index, index))

      {value, index} when is_map(value) ->
        build_item!(build, value, Map.put(context, :index, index))

      {value, index} ->
        raise_invalid_item!(value, Map.put(context, :index, index))
    end)
  end

  defp resolve(value, :many, _build, context) do
    raise ArgumentError,
          "expected #{describe(context)} to be a list of structs and/or params maps, " <>
            "got: #{inspect(value)}"
  end

  # A list never holds nil, so a builder must return a value for each item
  defp build_item!(build, params, context) do
    case build.(params) do
      nil when not is_map_key(context, :related) ->
        raise ArgumentError, "the builder for #{describe(context)} returned nil"

      built ->
        check!(built, context)
    end
  end

  # `assocs:` knows the related schema, so supplied structs and builder results are checked
  # against it. The helpers have no schema to check against.
  defp check!(value, %{related: related} = context) when not is_struct(value, related) do
    raise ArgumentError,
          "#{describe(context)} expects a %#{inspect(related)}{}, got: #{inspect(value)}"
  end

  defp check!(value, _context), do: value

  defp raise_invalid_item!(value, context) do
    raise ArgumentError,
          "expected #{describe(context)} to be a struct or a params map, got: #{inspect(value)}"
  end

  # Names the factory that was called, like the recursion error: when a variant delegates to its
  # base, the variant is named even though the base declared the association
  defp describe_calling(context) do
    case calling_factory(Process.get(@build_stack, [])) do
      {:factory, module, name, _root} -> describe(%{context | module: module, factory: name})
      nil -> describe(context)
    end
  end

  defp describe(context) do
    subject =
      case context[:index] do
        nil -> "association #{inspect(context.key)}"
        index -> "association #{inspect(context.key)}[#{index}]"
      end

    case context do
      %{factory: factory, module: module} ->
        "#{subject} in factory #{inspect(factory)} in #{inspect(module)}"

      _ ->
        subject
    end
  end

  defp duplicates(values) do
    for {value, count} <- Enum.frequencies(values), count > 1, do: value
  end
end
