defmodule PhoenixKitEntities.EntityMultilangTest do
  use ExUnit.Case, async: true
  alias PhoenixKitEntities, as: Entities

  describe "resolve_language/2" do
    test "resolves entity metadata from settings.translations" do
      entity = %Entities{
        display_name: "Product",
        display_name_plural: "Products",
        description: "Standard product",
        settings: %{
          "translations" => %{
            "es-ES" => %{
              "display_name" => "Producto",
              "display_name_plural" => "Productos",
              "description" => "Producto estándar"
            }
          }
        }
      }

      resolved = Entities.resolve_language(entity, "es-ES")

      assert resolved.display_name == "Producto"
      assert resolved.display_name_plural == "Productos"
      assert resolved.description == "Producto estándar"
    end

    test "falls back to default fields when translation is missing" do
      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{}}
      }

      resolved = Entities.resolve_language(entity, "es-ES")
      assert resolved.display_name == "Product"
    end

    test "falls back to default fields when lang is nil" do
      entity = %Entities{display_name: "Product"}
      resolved = Entities.resolve_language(entity, nil)
      assert resolved.display_name == "Product"
    end
  end

  describe "maybe_resolve_lang/2" do
    test "resolves when lang option is present" do
      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{"es-ES" => %{"display_name" => "Producto"}}}
      }

      resolved = Entities.maybe_resolve_lang(entity, lang: "es-ES")
      assert resolved.display_name == "Producto"
    end

    test "skips resolution when lang is missing" do
      entity = %Entities{display_name: "Product"}
      resolved = Entities.maybe_resolve_lang(entity, [])
      assert resolved.display_name == "Product"
    end

    test "skips resolution when lang is nil in opts" do
      entity = %Entities{display_name: "Product"}
      resolved = Entities.maybe_resolve_lang(entity, lang: nil)
      assert resolved.display_name == "Product"
    end
  end

  describe "resolve_language/2 — defensive handling" do
    test "no settings (nil)" do
      entity = %Entities{display_name: "Product", settings: nil}
      assert Entities.resolve_language(entity, "es-ES").display_name == "Product"
    end

    test "empty settings" do
      entity = %Entities{display_name: "Product", settings: %{}}
      assert Entities.resolve_language(entity, "es-ES").display_name == "Product"
    end

    test "translations map present but target locale missing" do
      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{"fr-FR" => %{"display_name" => "Produit"}}}
      }

      assert Entities.resolve_language(entity, "es-ES").display_name == "Product"
    end

    test "per-field missing — mixed resolution" do
      entity = %Entities{
        display_name: "Product",
        display_name_plural: "Products",
        description: "English description",
        settings: %{
          "translations" => %{
            "es-ES" => %{"display_name" => "Producto"}
            # plural + description intentionally missing
          }
        }
      }

      resolved = Entities.resolve_language(entity, "es-ES")
      assert resolved.display_name == "Producto"
      # Missing translations fall back to primary values
      assert resolved.display_name_plural == "Products"
      assert resolved.description == "English description"
    end

    test "empty-string override falls back to primary" do
      entity = %Entities{
        display_name: "Product",
        settings: %{"translations" => %{"es-ES" => %{"display_name" => ""}}}
      }

      assert Entities.resolve_language(entity, "es-ES").display_name == "Product"
    end
  end

  describe "resolve_languages/2" do
    test "empty list" do
      assert Entities.resolve_languages([], "es-ES") == []
    end

    test "nil locale is a no-op" do
      entity = %Entities{display_name: "Product"}
      assert Entities.resolve_languages([entity], nil) == [entity]
    end

    test "resolves every element" do
      entities = [
        %Entities{
          display_name: "Product",
          settings: %{"translations" => %{"es-ES" => %{"display_name" => "Producto"}}}
        },
        %Entities{
          display_name: "Article",
          settings: %{"translations" => %{"es-ES" => %{"display_name" => "Artículo"}}}
        }
      ]

      resolved = Entities.resolve_languages(entities, "es-ES")
      assert Enum.map(resolved, & &1.display_name) == ["Producto", "Artículo"]
    end
  end
end
