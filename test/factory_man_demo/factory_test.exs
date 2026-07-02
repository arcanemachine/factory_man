defmodule FactoryManDemo.FactoryTest do
  use FactoryManDemo.DataCase
  alias FactoryManDemo.Factory.ChildFactory

  # Factory option inheritance
  test "factory options cascade from parent to child to individual factory" do
    # Parent factory (FactoryManDemo.Factory) has repo and hooks
    parent_opts = FactoryManDemo.Factory.__factory_man__(:opts)
    assert Keyword.has_key?(parent_opts, :repo)
    assert Keyword.has_key?(parent_opts, :hooks)

    # Child factory extends parent and inherits repo and hooks
    child_opts = ChildFactory.__factory_man__(:opts)
    assert Keyword.get(child_opts, :repo) == FactoryManDemo.Repo
    assert Keyword.has_key?(child_opts, :hooks)
    assert Keyword.get(child_opts, :extends) == FactoryManDemo.Factory

    # Individual factory inherits all and adds its own options
    user_opts = ChildFactory.__factory_man__(:opts, :user)
    assert Keyword.get(user_opts, :repo) == FactoryManDemo.Repo
    assert Keyword.has_key?(user_opts, :hooks)
    assert Keyword.get(user_opts, :struct) == FactoryManDemo.Users.User

    # Factory-level options override inherited ones
    non_insertable_opts = ChildFactory.__factory_man__(:opts, :non_insertable)
    assert Keyword.get(non_insertable_opts, :insert?) == false
    assert Keyword.get(non_insertable_opts, :repo) == FactoryManDemo.Repo
  end
end
