defmodule FactoryMan.LazyEvaluationTest.Item do
  use Ecto.Schema

  schema "factory_man_lazy_test_items" do
    field :name, :string
    field :size, :integer
    field :label, :string
    field :derived, :string
  end
end

defmodule FactoryMan.LazyEvaluationTest.RecordingRepo do
  def insert!(record, opts) do
    send(self(), {:repo_insert, record, opts})
    record
  end
end

defmodule FactoryMan.LazyEvaluationTest.Factory do
  use FactoryMan, repo: FactoryMan.LazyEvaluationTest.RecordingRepo

  alias FactoryMan.LazyEvaluationTest.Item

  # A derived value reads a lazy value from the same factory
  deffactory item(params \\ %{}), struct: Item do
    base_params = %{
      name: "item",
      size: fn -> 10 end,
      derived: fn item -> "#{item.name}-#{item.size}" end
    }

    Map.merge(base_params, params)
  end

  # A derived value reading another derived value is not supported
  deffactory chained(params \\ %{}), struct: Item do
    base_params = %{
      size: fn -> 1 end,
      label: fn item -> "label-#{item.size}" end,
      derived: fn item -> "derived-#{inspect(item.label)}" end
    }

    Map.merge(base_params, params)
  end

  deffactory direct_item(params \\ %{}), struct: Item, body: :struct do
    %Item{
      name: Map.get(params, :name, "direct"),
      size: fn -> 20 end,
      derived: fn item -> "#{item.name}-#{item.size}" end
    }
  end

  deffactory counted(params \\ %{}), struct: Item do
    base_params = %{
      name: fn ->
        send(self(), :name_built)
        "counted"
      end
    }

    Map.merge(base_params, params)
  end

  deffactory settings(overrides \\ []) do
    base = [
      timeout: fn -> 5000 end,
      label: fn kw -> "timeout-#{kw[:timeout]}" end
    ]

    Keyword.merge(base, overrides)
  end
end

defmodule FactoryMan.LazyEvaluationTest do
  use ExUnit.Case, async: true

  alias FactoryMan.LazyEvaluationTest.Factory
  alias FactoryMan.LazyEvaluationTest.Item

  describe "two-pass evaluation" do
    test "a derived value reads a resolved lazy value" do
      assert Factory.build_item_struct().derived == "item-10"
    end

    test "a derived value reads a caller override" do
      item = Factory.build_item_struct(%{name: "custom", size: 99})

      assert item.derived == "custom-99"
    end

    test "a derived value reads a plain value" do
      assert Factory.build_item_struct(%{size: 1}).derived == "item-1"
    end

    test "a derived value cannot read another derived value" do
      item = Factory.build_chained_struct()

      assert item.label == "label-1"
      assert item.derived =~ "#Function<"
    end

    test "the same rules apply to keyword list factories" do
      assert Factory.build_settings()[:label] == "timeout-5000"
      assert Factory.build_settings(timeout: 10)[:label] == "timeout-10"
    end

    test "lazy values are resolved once per build" do
      Factory.build_counted_struct()

      assert_received :name_built
      refute_received :name_built
    end

    test "lazy values are resolved for each item of a list" do
      items = Factory.build_item_struct_list(3, %{name: "listed"})

      assert Enum.map(items, & &1.derived) == ["listed-10", "listed-10", "listed-10"]
    end
  end

  describe "body: :struct factories" do
    test "lazy values in the returned struct are resolved" do
      item = Factory.build_direct_item_struct()

      assert item.size == 20
      assert item.derived == "direct-20"
    end

    test "a derived value reads the struct after the first pass" do
      assert Factory.build_direct_item_struct(%{name: "named"}).derived == "named-20"
    end

    test "params builders see resolved values" do
      params = Factory.build_direct_item_params()

      refute is_function(params.size)
      assert params.derived == "direct-20"
    end

    test "inserts persist resolved values" do
      Factory.insert_direct_item()

      assert_received {:repo_insert, %Item{size: 20, derived: "direct-20"}, []}
    end

    test "insert_*_struct takes the struct as given" do
      lazy_size = fn -> 30 end

      Factory.insert_direct_item_struct(%Item{name: "given", size: lazy_size})

      assert_received {:repo_insert, %Item{name: "given", size: ^lazy_size}, []}
    end
  end
end
