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
  end

  describe "DB integration" do
    test "update/delete paths enforce the guard; listing and cap exclude managed" do
      actor_uuid = Ecto.UUID.generate()

      {:ok, managed} =
        PhoenixKitEntities.create_entity(%{
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
        })

      {:ok, plain} =
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
