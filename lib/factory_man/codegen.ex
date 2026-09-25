defmodule FactoryMan.Codegen do
  @moduledoc false

  # Compile-time helpers shared by `deffactory` and `defvariant`.
  #
  # Each `*_fns` function returns a quoted block of function definitions. The macros call these
  # from within their `quote bind_quoted:` blocks and materialize the result with
  # `Code.eval_quoted/3`, so both macros generate identical function families from a single
  # template.
  #
  # The `projections` map carries the argument AST projections extracted from the factory head:
  #
  # - `:head_ast` - argument with default, no pattern match (for bodiless function heads)
  # - `:plain_var` - just the argument variable (for wrappers that don't destructure)
  # - `:user_var` - the argument variable, for referencing in wrapper bodies
  # - `:has_pattern_match` / `:has_default` - gate which convenience arities are generated

  @doc """
  Wraps `value_ast` in a call to each of the factory's `hook_name` hooks, in run order. The hooks
  are known at compile time, so they are unrolled into nested remote calls (no runtime lookup),
  and a hook name with nothing set returns `value_ast` unchanged.
  """
  def hook_pipe(value_ast, hooks, hook_name) do
    hooks
    |> Keyword.get(hook_name, [])
    |> Enum.reduce(value_ast, fn hook, acc ->
      {:module, module} = Function.info(hook, :module)
      {:name, name} = Function.info(hook, :name)

      quote do: unquote(module).unquote(name)(unquote(acc))
    end)
  end

  @doc """
  The params pipeline of a struct factory with `body: :params`: lazy evaluation of the body's
  result, the strict check that the body kept its params, the params-stage hooks, `struct!/2`,
  then the `after_build_struct` hooks.
  """
  def build_struct_pipeline(block, hooks, struct_module, params_check) do
    params =
      quote(do: FactoryMan.evaluate_lazy_attributes(unquote(block)))
      |> check_params_used(params_check, struct_module)
      |> hook_pipe(hooks, :after_build_params)
      |> hook_pipe(hooks, :before_build_struct)

    hook_pipe(
      quote(do: struct!(unquote(struct_module), unquote(params))),
      hooks,
      :after_build_struct
    )
  end

  @doc """
  Binds the params that enter a strict factory's body, for `check_params_used/3`. `nil` (no
  code) when the factory is not strict.
  """
  def bind_entering_params(nil = _params_check, _user_var), do: nil

  def bind_entering_params({entering_var, _allow, _factory_name}, user_var) do
    quote do: unquote(entering_var) = unquote(user_var)
  end

  @doc """
  Wraps `result_ast` (the body's result, lazily evaluated) in the strict check that the body kept
  the params it received. Returns `result_ast` unchanged when the factory is not strict.
  """
  def check_params_used(result_ast, nil = _params_check, _struct_module), do: result_ast

  def check_params_used(result_ast, {entering_var, allow, factory_name}, struct_module) do
    quote do
      FactoryMan._check_params_used!(
        unquote(result_ast),
        unquote(entering_var),
        unquote(allow),
        unquote(struct_module),
        __MODULE__,
        unquote(factory_name)
      )
    end
  end

  @doc """
  The `(params, opts)` form of a builder, which accepts the `variants:` option. `name` is the
  factory or variant the builder belongs to, `own_variants` is `[]` for a factory and the
  variant's own name for a variant, and `base_build_fn` is the base factory's 1-arity builder.
  """
  def variants_fn(build_fn, name, factory_name, own_variants, base_build_fn) do
    quote do
      @doc "Like `#{unquote(build_fn)}/1`, with options. `variants:` applies the factory's variants."
      def unquote(build_fn)(params, opts) when is_list(opts) do
        FactoryMan._build_with_variants(
          __MODULE__,
          unquote(name),
          unquote(factory_name),
          unquote(own_variants) ++ FactoryMan._variants_opt!(opts, unquote("#{build_fn}/2")),
          params,
          &__factory_man_variant_chain__/2,
          &(unquote(Macro.var(base_build_fn, nil)) / 1)
        )
      end
    end
  end

  @doc """
  Whether `module` is a compiled Ecto schema.
  """
  def ecto_schema?(module) do
    match?({:module, _}, Code.ensure_compiled(module)) and
      function_exported?(module, :__schema__, 1)
  end

  @doc """
  List builders for factories whose params may be any value (params builders and non-struct
  factories).

  The 1-arity convenience calls the item builder with its actual default argument (not `%{}`),
  so factories with non-map defaults work. It is only generated when the factory head has a
  default.
  """
  def value_list_fns(build_fn, build_list_fn, projections) do
    doc = "Builds `count` items, each built independently by `#{build_fn}/1`."

    convenience =
      if projections.has_default do
        quote do
          @doc unquote(doc)
          def unquote(build_list_fn)(count)
              when is_integer(count) and count >= 0 do
            Stream.repeatedly(fn -> unquote(build_fn)() end)
            |> Enum.take(count)
          end
        end
      end

    implementation =
      quote do
        @doc unquote(doc)
        def unquote(build_list_fn)(count, params)
            when is_integer(count) and count >= 0 do
          Stream.repeatedly(fn -> unquote(build_fn)(params) end)
          |> Enum.take(count)
        end

        @doc unquote(doc)
        def unquote(build_list_fn)(count, params, opts)
            when is_integer(count) and count >= 0 and is_list(opts) do
          Stream.repeatedly(fn -> unquote(build_fn)(params, opts) end)
          |> Enum.take(count)
        end
      end

    block([convenience, implementation])
  end

  @doc """
  List builders for functions whose params are always maps (struct builders).

  The 1-arity convenience passes `%{}` and is skipped when the factory head pattern-matches on
  required keys (calling with `%{}` would not match).
  """
  def map_list_fns(build_fn, build_list_fn, projections) do
    doc = "Builds `count` items, each built independently by `#{build_fn}/1`."

    convenience =
      if not projections.has_pattern_match do
        quote do
          @doc unquote(doc)
          def unquote(build_list_fn)(count)
              when is_integer(count) and count >= 0 do
            unquote(build_list_fn)(count, %{})
          end
        end
      end

    implementation =
      quote do
        @doc unquote(doc)
        def unquote(build_list_fn)(count, params)
            when is_integer(count) and count >= 0 and is_map(params) do
          Stream.repeatedly(fn -> unquote(build_fn)(params) end)
          |> Enum.take(count)
        end

        @doc unquote(doc)
        def unquote(build_list_fn)(count, params, opts)
            when is_integer(count) and count >= 0 and is_map(params) and is_list(opts) do
          Stream.repeatedly(fn -> unquote(build_fn)(params, opts) end)
          |> Enum.take(count)
        end
      end

    block([convenience, implementation])
  end

  @doc """
  `build_*_params` and `build_*_string_params` functions for struct factories, plus their
  `_list` variants. They build a struct via `build_<name>_struct` and convert it to a clean
  params map, stripping Ecto metadata for Ecto schemas, or `Map.from_struct/1` for plain
  structs.
  """
  def params_fns(full_name, projections, ecto_schema?) do
    build_struct_fn = :"build_#{full_name}_struct"
    params_fn = :"build_#{full_name}_params"
    string_params_fn = :"build_#{full_name}_string_params"

    {strip_mod, strip_fun} =
      if ecto_schema?, do: {FactoryMan.Params, :strip}, else: {Map, :from_struct}

    params_doc =
      "Builds a struct via `#{build_struct_fn}/1` and converts it to a clean params map."

    string_params_doc = "Like `#{params_fn}/1`, but with string keys."

    zero_arity =
      if projections.has_default do
        quote do
          @doc unquote(params_doc)
          def unquote(params_fn)() do
            unquote(build_struct_fn)()
            |> unquote(strip_mod).unquote(strip_fun)()
          end

          @doc unquote(string_params_doc)
          def unquote(string_params_fn)() do
            unquote(params_fn)()
            |> FactoryMan.Params.stringify_keys()
          end
        end
      end

    one_arity =
      quote do
        @doc unquote(params_doc)
        def unquote(params_fn)(unquote(projections.plain_var)) do
          unquote(projections.user_var)
          |> unquote(build_struct_fn)()
          |> unquote(strip_mod).unquote(strip_fun)()
        end

        @doc unquote(string_params_doc)
        def unquote(string_params_fn)(unquote(projections.plain_var)) do
          unquote(params_fn)(unquote(projections.user_var))
          |> FactoryMan.Params.stringify_keys()
        end
      end

    with_opts =
      quote do
        @doc unquote(params_doc)
        def unquote(params_fn)(params, opts) when is_list(opts) do
          params
          |> unquote(build_struct_fn)(opts)
          |> unquote(strip_mod).unquote(strip_fun)()
        end

        @doc unquote(string_params_doc)
        def unquote(string_params_fn)(params, opts) when is_list(opts) do
          params
          |> unquote(params_fn)(opts)
          |> FactoryMan.Params.stringify_keys()
        end
      end

    block([
      zero_arity,
      one_arity,
      with_opts,
      map_list_fns(params_fn, :"#{params_fn}_list", projections),
      map_list_fns(string_params_fn, :"#{string_params_fn}_list", projections)
    ])
  end

  @doc """
  The names of the `insert_*` and `insert_*_struct` functions of factory or variant `name` for
  one insert target: `nil` for the default target, or the name of an `insert_via:` target.
  """
  def insert_names(name, nil = _target_name), do: {:"insert_#{name}", :"insert_#{name}_struct"}

  def insert_names(name, target_name),
    do: {:"insert_#{name}_via_#{target_name}", :"insert_#{name}_struct_via_#{target_name}"}

  @doc """
  Checks that no function defined by the head `def name(head_ast)` is defined yet in `module`
  (see `define/3`).
  """
  def claim_head!(module, name, head_ast, source) do
    FactoryMan._claim_names!(module, defined_names({:def, [], [{name, [], [head_ast]}]}), source)
  end

  @doc """
  The `insert_*` family of a factory or variant: `insert_*/0,1,2` and `insert_*_list/1,2,3`.
  `insert_*/2` builds with `build_struct_fn`, then inserts with `insert_struct_fn`. `target` is
  what `insert_struct_fn` inserts with (`{:ecto, repo}` or a capture), for the docs.
  """
  def insert_fns(insert_fn, build_struct_fn, insert_struct_fn, target, projections) do
    implementation =
      quote do
        @doc unquote(insert_doc(target))
        def unquote(insert_fn)(unquote(projections.plain_var), opts) when is_list(opts) do
          {variants, insert_opts} = FactoryMan._pop_variants!(opts, unquote("#{insert_fn}/2"))

          unquote(projections.user_var)
          |> unquote(build_struct_fn)(variants: variants)
          |> unquote(insert_struct_fn)(insert_opts)
        end
      end

    block([
      insert_convenience_fns(insert_fn, target, projections),
      implementation,
      insert_list_fns(insert_fn, :"#{insert_fn}_list", projections)
    ])
  end

  defp insert_doc({:ecto, repo} = target) do
    """
    Builds the corresponding struct and inserts it with `#{describe_target(target)}`.

    `opts` is one keyword list: FactoryMan uses `:variants`, and every other option is passed to
    `#{inspect(repo)}.insert!/2` unchanged.

        insert_user(%{username: "alice"}, variants: [:admin], returning: true)
        #                                 └─ FactoryMan ───┘  └─ Repo.insert!/2 ┘
    """
  end

  defp insert_doc(target) do
    """
    Builds the corresponding struct and inserts it with `#{describe_target(target)}`.

    `opts` is one keyword list: FactoryMan uses `:variants`, and every other option is passed to
    `#{describe_target(target)}` unchanged.
    """
  end

  # Head declaration and convenience arities for `insert_*`. The 2-arity implementation must be
  # defined directly after these.
  defp insert_convenience_fns(insert_fn, target, projections) do
    head =
      quote do
        @doc unquote(
               "Builds the corresponding struct and inserts it with " <>
                 "`#{describe_target(target)}`."
             )
        def unquote(insert_fn)(unquote(projections.head_ast))
      end

    # Pattern matches require specific keys, so we can't call with %{}
    opts_convenience =
      if not projections.has_pattern_match do
        quote do
          def unquote(insert_fn)(insert_opts) when is_list(insert_opts) do
            unquote(insert_fn)(%{}, insert_opts)
          end
        end
      end

    params_convenience =
      quote do
        def unquote(insert_fn)(unquote(projections.plain_var)) do
          unquote(insert_fn)(unquote(projections.user_var), [])
        end
      end

    block([head, opts_convenience, params_convenience])
  end

  # `insert_*_list` functions. Each item delegates to `insert_<name>/2`.
  defp insert_list_fns(insert_fn, insert_list_fn, projections) do
    doc =
      "Inserts `count` records, each built and inserted independently by `#{insert_fn}/2`, " <>
        "which takes the same options."

    conveniences =
      if not projections.has_pattern_match do
        quote do
          @doc unquote(doc)
          def unquote(insert_list_fn)(count)
              when is_integer(count) and count >= 0 do
            unquote(insert_list_fn)(count, %{}, [])
          end

          @doc unquote(doc)
          def unquote(insert_list_fn)(count, insert_opts)
              when is_integer(count) and count >= 0 and is_list(insert_opts) do
            unquote(insert_list_fn)(count, %{}, insert_opts)
          end
        end
      end

    # When the pattern-match gate skips the conveniences, the /2 doc must ride on the
    # (count, params) clause instead, since it is then the first clause of that arity
    implementation_doc =
      if projections.has_pattern_match do
        quote do
          @doc unquote(doc)
        end
      end

    implementations =
      quote do
        def unquote(insert_list_fn)(count, params)
            when is_integer(count) and count >= 0 and is_map(params) do
          unquote(insert_list_fn)(count, params, [])
        end

        @doc unquote(doc)
        def unquote(insert_list_fn)(count, params, insert_opts)
            when is_integer(count) and count >= 0 and is_map(params) and
                   is_list(insert_opts) do
          Stream.repeatedly(fn -> unquote(insert_fn)(params, insert_opts) end)
          |> Enum.take(count)
        end
      end

    block([conveniences, implementation_doc, implementations])
  end

  @doc """
  `insert_*_struct` for `deffactory`: inserts an already-built struct with `target`
  (`{:ecto, repo}` or a capture), between the `before_insert` and `after_insert` hooks in
  `hooks`. The `:ecto` insert first checks that the struct has not been inserted. `insert_*`
  delegates here after building, so the insert is defined in one place.
  """
  def insert_struct_fns(insert_struct_fn, insert_fn, struct_module, target, hooks, doc) do
    guard = ecto_guard(insert_struct_fn, target)

    before_insert = hook_pipe(quote(do: struct), hooks, :before_insert)

    insert =
      case target do
        {:ecto, repo} ->
          quote do: unquote(repo).insert!(unquote(before_insert), insert_opts)

        capture ->
          {:module, module} = Function.info(capture, :module)
          {:name, name} = Function.info(capture, :name)

          quote do: unquote(module).unquote(name)(unquote(before_insert), insert_opts)
      end

    quote do
      @doc unquote(doc)
      def unquote(insert_struct_fn)(%unquote(struct_module){} = struct, insert_opts \\ [])
          when is_list(insert_opts) do
        FactoryMan._reject_struct_variants!(
          insert_opts,
          unquote("#{insert_struct_fn}/2"),
          unquote("#{insert_fn}/2")
        )

        unquote(guard)

        unquote(hook_pipe(insert, hooks, :after_insert))
      end
    end
  end

  @doc """
  `insert_*_struct` for `defvariant`: delegates to the base factory's `base_insert_struct_fn`,
  since a variant's preprocessor has no role once the struct is built. The `:ecto` check runs here
  too, so its error names the function the caller called.
  """
  def insert_struct_delegate_fns(
        insert_struct_fn,
        insert_fn,
        struct_module,
        target,
        base_insert_struct_fn,
        doc
      ) do
    quote do
      @doc unquote(doc)
      def unquote(insert_struct_fn)(%unquote(struct_module){} = struct, insert_opts \\ [])
          when is_list(insert_opts) do
        FactoryMan._reject_struct_variants!(
          insert_opts,
          unquote("#{insert_struct_fn}/2"),
          unquote("#{insert_fn}/2")
        )

        unquote(ecto_guard(insert_struct_fn, target))

        unquote(base_insert_struct_fn)(struct, insert_opts)
      end
    end
  end

  defp ecto_guard(insert_struct_fn, {:ecto, _repo}) do
    quote do
      FactoryMan._ensure_not_inserted!(struct, unquote("#{insert_struct_fn}/2"))
    end
  end

  defp ecto_guard(_insert_struct_fn, _capture), do: nil

  @doc """
  The doc of an `insert_*_struct` function. `hooks?` is `true` for the default target, whose
  insert runs between the `factory_name` factory's insert hooks.
  """
  def insert_struct_doc(struct_module, target, factory_name, hooks?) do
    base =
      "Inserts an already-built `#{inspect(struct_module)}` with `#{describe_target(target)}`"

    if hooks? do
      base <>
        ", between the `:#{factory_name}` factory's `before_insert` and `after_insert` hooks."
    else
      base <> ". Insert hooks do not run."
    end
  end

  defp describe_target({:ecto, repo}), do: "#{inspect(repo)}.insert!/2"

  defp describe_target(capture) do
    {:module, module} = Function.info(capture, :module)
    {:name, name} = Function.info(capture, :name)

    "#{inspect(module)}.#{name}/2"
  end

  @doc """
  Defines the functions in `quoted` in `env`'s module, after checking that none of them is
  already defined there (see `FactoryMan._claim_names!/3`). `source` names the factory or variant
  that generates them, for the error message.
  """
  def define(quoted, env, source) do
    FactoryMan._claim_names!(env.module, defined_names(quoted), source)

    Code.eval_quoted(quoted, [], env)
  end

  @doc """
  The `{name, arity}` pairs that the `def`s in `quoted` define, including the arities that
  default arguments add.
  """
  def defined_names(quoted) do
    {_quoted, names} =
      Macro.prewalk(quoted, [], fn
        {:def, _meta, [head | _body]} = node, names -> {node, names ++ head_names(head)}
        node, names -> {node, names}
      end)

    Enum.uniq(names)
  end

  defp head_names({:when, _meta, [call | _guards]}), do: head_names(call)

  defp head_names({name, _meta, args}) when is_atom(name) and is_list(args) do
    defaults = Enum.count(args, &match?({:\\, _meta, _default}, &1))

    for arity <- (length(args) - defaults)..length(args), do: {name, arity}
  end

  # A head without parentheses (`def name do`)
  defp head_names({name, _meta, context}) when is_atom(name) and is_atom(context),
    do: [{name, 0}]

  defp block(parts) do
    {:__block__, [], Enum.reject(parts, &is_nil/1)}
  end
end
