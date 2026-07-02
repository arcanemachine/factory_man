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

  test "__factory_man__(:factories) lists factories and variants in definition order" do
    factories = ChildFactory.__factory_man__(:factories)

    # Factories appear under their own name, variants under their full name
    assert :user in factories
    assert :admin_user in factories
    # The :as option determines the registered variant name
    assert :mod in factories
    refute :moderator_user in factories
    # A variant of a variant is registered too
    assert :senior_admin_user in factories

    # Definition order: :user is defined before its variants
    assert Enum.find_index(factories, &(&1 == :user)) <
             Enum.find_index(factories, &(&1 == :admin_user))
  end

  test "__factory_man__(:factories) is empty for a factory module without factories" do
    assert FactoryManDemo.Factory.__factory_man__(:factories) == []
  end
end
