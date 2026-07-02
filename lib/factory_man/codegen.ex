defmodule FactoryMan.Codegen do
  @moduledoc false

  # Compile-time helpers shared by `deffactory` and `defvariant`.
  #
  # Each `*_fns` function returns a quoted block of function definitions. The macros call these
  # from within their `quote bind_quoted:` blocks and materialize the result with
  # `Module.eval_quoted/2`, so both macros generate identical function families from a single
  # template.
  #
  # The `projections` map carries the argument AST projections extracted from the factory head:
  #
  # - `:head_ast` — argument with default, no pattern match (for bodiless function heads)
  # - `:plain_var` — just the argument variable (for wrappers that don't destructure)
  # - `:user_var` — the argument variable, for referencing in wrapper bodies
  # - `:has_pattern_match` / `:has_default` — gate which convenience arities are generated

  @doc """
  Whether `module` is a compiled Ecto schema.
  """
  def ecto_schema?(module) do
    match?({:module, _}, Code.ensure_compiled(module)) and
      function_exported?(module, :__schema__, 1)
  end

  @doc """
  Whether `module` is an Ecto schema that can be inserted (has a source table and a repo is
  configured). Embedded schemas have no source and are not insertable.
  """
  def insertable_ecto_schema?(module, repo) do
    ecto_schema?(module) and not is_nil(repo) and module.__schema__(:source) != nil
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
      end

    block([convenience, implementation])
  end

  @doc """
  `build_*_params` and `build_*_string_params` functions for struct factories, plus their
  `_list` variants. They build a struct via `build_<name>_struct` and convert it to a clean
  params map — stripping Ecto metadata for Ecto schemas, or `Map.from_struct/1` for plain
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

    block([
      zero_arity,
      one_arity,
      map_list_fns(params_fn, :"#{params_fn}_list", projections),
      map_list_fns(string_params_fn, :"#{string_params_fn}_list", projections)
    ])
  end

  @doc """
  Head declaration and convenience arities for `insert_*`. The 2-arity implementation clause
  differs between `deffactory` and `defvariant` and stays in the macros; it must be defined
  directly after these.
  """
  def insert_convenience_fns(insert_fn, projections) do
    head =
      quote do
        @doc "Builds the corresponding struct and inserts it into the database."
        def unquote(insert_fn)(unquote(projections.head_ast))
      end

    # Pattern matches require specific keys, so we can't call with %{}
    repo_opts_convenience =
      if not projections.has_pattern_match do
        quote do
          def unquote(insert_fn)(repo_insert_opts)
              when is_list(repo_insert_opts) do
            unquote(insert_fn)(%{}, repo_insert_opts)
          end
        end
      end

    params_convenience =
      quote do
        def unquote(insert_fn)(unquote(projections.plain_var)) do
          unquote(insert_fn)(unquote(projections.user_var), [])
        end
      end

    block([head, repo_opts_convenience, params_convenience])
  end

  @doc """
  `insert_*_list` functions. Each item delegates to `insert_<name>/2`.
  """
  def insert_list_fns(insert_fn, insert_list_fn, projections) do
    doc = "Inserts `count` records, each built and inserted independently by `#{insert_fn}/2`."

    conveniences =
      if not projections.has_pattern_match do
        quote do
          @doc unquote(doc)
          def unquote(insert_list_fn)(count)
              when is_integer(count) and count >= 0 do
            unquote(insert_list_fn)(count, %{}, [])
          end

          @doc unquote(doc)
          def unquote(insert_list_fn)(count, repo_insert_opts)
              when is_integer(count) and count >= 0 and is_list(repo_insert_opts) do
            unquote(insert_list_fn)(count, %{}, repo_insert_opts)
          end
        end
      end

    implementations =
      quote do
        def unquote(insert_list_fn)(count, params)
            when is_integer(count) and count >= 0 and is_map(params) do
          unquote(insert_list_fn)(count, params, [])
        end

        @doc unquote(doc)
        def unquote(insert_list_fn)(count, params, repo_insert_opts)
            when is_integer(count) and count >= 0 and is_map(params) and
                   is_list(repo_insert_opts) do
          Stream.repeatedly(fn -> unquote(insert_fn)(params, repo_insert_opts) end)
          |> Enum.take(count)
        end
      end

    block([conveniences, implementations])
  end

  defp block(parts) do
    {:__block__, [], Enum.reject(parts, &is_nil/1)}
  end
end
