defmodule PhoenixKitEntities.ManagedTest do
  @moduledoc """
  The managed-blueprint contract (catalogue attribute sets et al.):
  write-path guard, listing exclusion, cap exemption, delete guard.
  Pure-map + DB pins; the guard functions take any struct/map with
  `settings`/`name`/`status`, so most pins need no DB.
  """
  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKitEntities.Managed

  defp managed_entity(overrides \\ %{}) do
    Map.merge(
      %{
        name: "catalogue_set_ikea_colors",
        status: "published",
        settings: %{
          "managed_by" => "catalogue",
          "locked_keys" => ["kind", "default_value_slug"],
          "catalogue" => %{"kind" => "multi", "default_value_slug" => "oak"}
        }
      },
      overrides
    )
  end

  describe "validate_mutation/3" do
    test "unmanaged entities are untouched" do
      assert :ok = Managed.validate_mutation(%{settings: %{}}, %{"name" => "x"})
    end

    test "generic writes cannot rename identity or status" do
      e = managed_entity()
      assert {:error, :managed_blueprint} = Managed.validate_mutation(e, %{"name" => "renamed"})

      assert {:error, :managed_blueprint} =
               Managed.validate_mutation(e, %{"status" => "archived"})
    end

    test "generic writes cannot change locked owner-settings keys" do
      e = managed_entity()

      attrs = %{
        "settings" => %{
          "managed_by" => "catalogue",
          "locked_keys" => ["kind", "default_value_slug"],
          "catalogue" => %{"kind" => "fixed", "default_value_slug" => "oak"}
        }
      }

      assert {:error, :locked_key} = Managed.validate_mutation(e, attrs)
    end

    test "adding new fields/settings stays allowed (the extras contract)" do
      e = managed_entity()

      attrs = %{
        "fields_definition" => [%{"type" => "number", "key" => "price_per_liter"}],
        "settings" =>
          e.settings
          |> put_in(["catalogue", "vendor"], "ikea")
      }

      assert :ok = Managed.validate_mutation(e, attrs)
    end

    test "the owner passes unconditionally via on_behalf_of" do
      e = managed_entity()

      assert :ok =
               Managed.validate_mutation(e, %{"name" => "renamed"}, on_behalf_of: "catalogue")
    end

    test "generic writes cannot rewrite or drop the marker keys themselves" do
      e = managed_entity()

      # Dropping managed_by would un-manage the blueprint entirely.
      assert {:error, :managed_blueprint} =
               Managed.validate_mutation(e, %{
                 "settings" => Map.delete(e.settings, "managed_by")
               })

      # Emptying locked_keys would unlock every contract key.
      assert {:error, :managed_blueprint} =
               Managed.validate_mutation(e, %{
                 "settings" => Map.put(e.settings, "locked_keys", [])
               })

      # The owner may still restructure its own contract.
      assert :ok =
               Managed.validate_mutation(
                 e,
                 %{"settings" => Map.put(e.settings, "locked_keys", ["kind"])},
                 on_behalf_of: "catalogue"
               )
    end
  end

  describe "validate_creation/2" do
    test "generic creates cannot claim a managed_by owner" do
      attrs = %{settings: %{"managed_by" => "catalogue"}, name: "catalogue_set_forged"}

      assert {:error, :managed_blueprint} = Managed.validate_creation(attrs)
      assert :ok = Managed.validate_creation(attrs, on_behalf_of: "catalogue")
      assert :ok = Managed.validate_creation(%{name: "plain", settings: %{}})
      assert :ok = Managed.validate_creation(%{name: "no_settings"})
    end

    test "atom-keyed settings cannot slip a claim past the guard" do
      # Ecto's :map stores atom-keyed maps as given and JSONB-encodes
      # them to string keys — a string-only lookup fails OPEN here
      # (panel finding, 2026-08-19 review).
      attrs = %{settings: %{managed_by: "catalogue"}, name: "catalogue_set_forged"}

      assert {:error, :managed_blueprint} = Managed.validate_creation(attrs)
      assert :ok = Managed.validate_creation(attrs, on_behalf_of: "catalogue")
    end
  end

  describe "marker acquisition via update (create-then-update masquerade)" do
    test "an unmanaged blueprint cannot acquire managed_by generically" do
      unmanaged = %{name: "plain", status: "published", settings: %{}}
      claim = %{settings: %{"managed_by" => "catalogue", "locked_keys" => ["kind"]}}

      assert {:error, :managed_blueprint} = Managed.validate_mutation(unmanaged, claim)
      # Atom-keyed claim is caught the same way.
      assert {:error, :managed_blueprint} =
               Managed.validate_mutation(unmanaged, %{settings: %{managed_by: "catalogue"}})

      # The claimed owner itself may stamp its own markers.
      assert :ok = Managed.validate_mutation(unmanaged, claim, on_behalf_of: "catalogue")

      # Settings writes without a claim stay untouched.
      assert :ok = Managed.validate_mutation(unmanaged, %{settings: %{"sort_mode" => "manual"}})
    end
  end

  describe "validate_delete/2" do
    test "generic deletes of managed blueprints are refused" do
      assert {:error, :managed_blueprint} = Managed.validate_delete(managed_entity())
    end

    test "owner deletes fail closed without a registered guard, pass with approval" do
      e = managed_entity(%{settings: %{"managed_by" => "managed_test_owner"}})

      assert {:error, :no_delete_guard} =
               Managed.validate_delete(e, on_behalf_of: "managed_test_owner")

      Managed.register_delete_guard("managed_test_owner", fn _e -> :ok end)
      assert :ok = Managed.validate_delete(e, on_behalf_of: "managed_test_owner")

      Managed.register_delete_guard("managed_test_owner", fn _e -> {:error, :set_in_use} end)

      assert {:error, :set_in_use} =
               Managed.validate_delete(e, on_behalf_of: "managed_test_owner")
    end

    test "a crashing or misbehaving guard fails closed, never propagates" do
      e = managed_entity(%{settings: %{"managed_by" => "crashy_owner"}})

      Managed.register_delete_guard("crashy_owner", fn _e -> raise "stale fun" end)

      assert {:error, :delete_guard_error} =
               Managed.validate_delete(e, on_behalf_of: "crashy_owner")

      Managed.register_delete_guard("crashy_owner", fn _e -> :weird end)

      assert {:error, {:invalid_guard_result, :weird}} =
               Managed.validate_delete(e, on_behalf_of: "crashy_owner")

      # An EXIT (e.g. the guard's DB connection owner died) fails
      # closed the same way a raise does.
      Managed.register_delete_guard("crashy_owner", fn _e -> exit(:connection_died) end)

      assert {:error, :delete_guard_error} =
               Managed.validate_delete(e, on_behalf_of: "crashy_owner")
    end
  end

  describe "DB integration" do
    test "update/delete paths enforce the guard; listing and cap exclude managed" do
      actor_uuid = Ecto.UUID.generate()

      managed_attrs = %{
        name: "catalogue_set_test_colors",
        display_name: "Test colors",
        display_name_plural: "Test colors",
        status: "published",
        fields_definition: [],
        created_by_uuid: actor_uuid,
        settings: %{
          "managed_by" => "catalogue",
          "locked_keys" => ["kind"],
          "catalogue" => %{"kind" => "multi"}
        }
      }

      # Creation guard live on the real create path: generic callers
      # cannot claim an owner; the owner provisions via on_behalf_of.
      assert {:error, :managed_blueprint} = PhoenixKitEntities.create_entity(managed_attrs)
      {:ok, managed} = PhoenixKitEntities.create_entity(managed_attrs, on_behalf_of: "catalogue")

      {:ok, _plain} =
        PhoenixKitEntities.create_entity(%{
          name: "plain_entity",
          display_name: "Plain",
          display_name_plural: "Plains",
          status: "published",
          fields_definition: [],
          created_by_uuid: actor_uuid
        })

      # Write guard live on the real update path.
      assert {:error, :managed_blueprint} =
               PhoenixKitEntities.update_entity(managed, %{"name" => "sneaky"})

      assert {:ok, _} =
               PhoenixKitEntities.update_entity(managed, %{"name" => "renamed_by_owner"},
                 on_behalf_of: "catalogue"
               )

      # Delete guard live.
      assert {:error, :managed_blueprint} = PhoenixKitEntities.delete_entity(managed)

      # Listing exclusion.
      names = PhoenixKitEntities.list_entities(include_managed: false) |> Enum.map(& &1.name)
      assert "plain_entity" in names
      refute Enum.any?(names, &String.starts_with?(&1, "catalogue_set_"))

      # Cap exemption: only the plain entity counts for its creator.
      assert PhoenixKitEntities.count_user_entities(actor_uuid) == 1
    end
  end
end
