defmodule PhoenixKitEntitiesTest do
  use ExUnit.Case

  # These tests verify that the module correctly implements the
  # PhoenixKit.Module behaviour.

  describe "behaviour implementation" do
    test "implements PhoenixKit.Module" do
      behaviours =
        PhoenixKitEntities.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert PhoenixKit.Module in behaviours
    end

    test "has @phoenix_kit_module attribute for auto-discovery" do
      attrs = PhoenixKitEntities.__info__(:attributes)
      assert Keyword.get(attrs, :phoenix_kit_module) == [true]
    end
  end

  describe "required callbacks" do
    test "module_key/0 returns 'entities'" do
      assert PhoenixKitEntities.module_key() == "entities"
    end

    test "module_name/0 returns 'Entities'" do
      assert PhoenixKitEntities.module_name() == "Entities"
    end

    test "enabled?/0 returns a boolean" do
      # In test env without DB, this returns false (the rescue fallback)
      assert is_boolean(PhoenixKitEntities.enabled?())
    end

    test "enable_system/0 is exported" do
      assert function_exported?(PhoenixKitEntities, :enable_system, 0)
    end

    test "disable_system/0 is exported" do
      assert function_exported?(PhoenixKitEntities, :disable_system, 0)
    end
  end

  describe "permission_metadata/0" do
    test "returns a map with required fields" do
      meta = PhoenixKitEntities.permission_metadata()
      assert %{key: key, label: label, icon: icon, description: desc} = meta
      assert is_binary(key)
      assert is_binary(label)
      assert is_binary(icon)
      assert is_binary(desc)
    end

    test "key matches module_key" do
      meta = PhoenixKitEntities.permission_metadata()
      assert meta.key == PhoenixKitEntities.module_key()
    end

    test "icon uses hero- prefix" do
      meta = PhoenixKitEntities.permission_metadata()
      assert String.starts_with?(meta.icon, "hero-")
    end
  end

  describe "admin_tabs/0" do
    test "returns a list of Tab structs" do
      tabs = PhoenixKitEntities.admin_tabs()
      assert is_list(tabs)
      assert tabs != []
    end

    test "tab has all required fields" do
      [tab | _] = PhoenixKitEntities.admin_tabs()
      assert tab.id == :admin_entities
      assert tab.label == "Entities"
      assert is_binary(tab.path)
      assert tab.level == :admin
      assert tab.permission == PhoenixKitEntities.module_key()
      assert tab.group == :admin_modules
    end

    test "path uses hyphens or simple names, not underscores" do
      [tab | _] = PhoenixKitEntities.admin_tabs()
      refute String.contains?(tab.path, "_")
    end
  end

  describe "settings_tabs/0" do
    test "returns a list of Tab structs" do
      tabs = PhoenixKitEntities.settings_tabs()
      assert is_list(tabs)
      assert tabs != []
    end
  end

  describe "children/0" do
    test "returns a list with Presence" do
      children = PhoenixKitEntities.children()
      assert is_list(children)
      assert PhoenixKitEntities.Presence in children
    end
  end

  describe "get_config/0" do
    test "returns a map with expected keys" do
      config = PhoenixKitEntities.get_config()
      assert is_map(config)
      assert Map.has_key?(config, :enabled)
    end
  end
end
