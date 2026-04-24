defmodule PhoenixKitEntities.EntityDataUrlTest do
  use ExUnit.Case, async: true

  alias PhoenixKitEntities.EntityData

  # These tests run without Languages enabled (single-language mode),
  # so `add_public_locale_prefix/2` never adds a prefix regardless of locale.
  # Prefix behavior is covered in tests that mock Languages (integration).

  describe "public_path/3 — pattern resolution" do
    test "uses entity.settings['sitemap_url_pattern']" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/shop/:slug"}}
      record = %{uuid: "uuid-1", slug: "my-item"}
      cache = empty_cache()

      assert EntityData.public_path(entity, record, routes_cache: cache) ==
               "/shop/my-item"
    end

    test "uses router-introspected pattern when no entity setting" do
      entity = %{name: "product", settings: %{}}
      record = %{uuid: "uuid-1", slug: "my-item"}

      cache = %{
        entity_patterns: %{"product" => "/products/:slug", :catchall => nil},
        entity_index_paths: %{}
      }

      assert EntityData.public_path(entity, record, routes_cache: cache) ==
               "/products/my-item"
    end

    test "falls back to /<entity_name>/:slug when no pattern is resolvable" do
      entity = %{name: "product", settings: %{}}
      record = %{uuid: "uuid-1", slug: "my-item"}
      cache = empty_cache()

      assert EntityData.public_path(entity, record, routes_cache: cache) ==
               "/product/my-item"
    end

    test "slug falls back to uuid when missing" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/p/:slug"}}
      record = %{uuid: "uuid-abc", slug: nil}
      cache = empty_cache()

      assert EntityData.public_path(entity, record, routes_cache: cache) ==
               "/p/uuid-abc"
    end

    test "substitutes :id placeholder" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/p/:id"}}
      record = %{uuid: "uuid-abc", slug: "ignored"}
      cache = empty_cache()

      assert EntityData.public_path(entity, record, routes_cache: cache) ==
               "/p/uuid-abc"
    end

    test "pattern with literal segments works" do
      entity = %{name: "post", settings: %{"sitemap_url_pattern" => "/blog/2025/:slug"}}
      record = %{uuid: "uuid-1", slug: "hello"}
      cache = empty_cache()

      assert EntityData.public_path(entity, record, routes_cache: cache) ==
               "/blog/2025/hello"
    end
  end

  describe "public_path/3 — locale prefix (single-language mode)" do
    test "locale is ignored when single-language mode is active" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/p/:slug"}}
      record = %{uuid: "uuid-1", slug: "item"}
      cache = empty_cache()

      # In tests, Languages is disabled → single_language_mode? is true → no prefix
      assert EntityData.public_path(entity, record, locale: "es-ES", routes_cache: cache) ==
               "/p/item"

      assert EntityData.public_path(entity, record, locale: "ru", routes_cache: cache) ==
               "/p/item"
    end

    test "nil locale returns bare path" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/p/:slug"}}
      record = %{uuid: "uuid-1", slug: "item"}
      cache = empty_cache()

      assert EntityData.public_path(entity, record, locale: nil, routes_cache: cache) ==
               "/p/item"
    end
  end

  describe "public_path/3 — translated slugs" do
    test "uses secondary-language _slug override when locale is given" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/p/:slug"}}

      record = %{
        uuid: "uuid-1",
        slug: "my-item",
        data: %{
          "en-US" => %{"_slug" => "my-item"},
          "es-ES" => %{"_slug" => "mi-articulo"}
        }
      }

      cache = empty_cache()

      assert EntityData.public_path(entity, record, locale: "es-ES", routes_cache: cache) ==
               "/p/mi-articulo"
    end

    test "falls back to primary slug when locale has no _slug override" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/p/:slug"}}

      record = %{
        uuid: "uuid-1",
        slug: "my-item",
        data: %{"es-ES" => %{"name" => "Mi Artículo"}}
      }

      cache = empty_cache()

      assert EntityData.public_path(entity, record, locale: "es-ES", routes_cache: cache) ==
               "/p/my-item"
    end

    test "ignores _slug override when no locale is given" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/p/:slug"}}

      record = %{
        uuid: "uuid-1",
        slug: "my-item",
        data: %{"es-ES" => %{"_slug" => "mi-articulo"}}
      }

      cache = empty_cache()

      assert EntityData.public_path(entity, record, routes_cache: cache) == "/p/my-item"
    end

    test "empty _slug override falls back to primary" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/p/:slug"}}

      record = %{
        uuid: "uuid-1",
        slug: "my-item",
        data: %{"es-ES" => %{"_slug" => ""}}
      }

      cache = empty_cache()

      assert EntityData.public_path(entity, record, locale: "es-ES", routes_cache: cache) ==
               "/p/my-item"
    end

    test "nil data map does not crash" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/p/:slug"}}
      record = %{uuid: "uuid-1", slug: "my-item", data: nil}
      cache = empty_cache()

      assert EntityData.public_path(entity, record, locale: "es-ES", routes_cache: cache) ==
               "/p/my-item"
    end
  end

  describe "public_path/3 — defensive inputs" do
    test "nil settings on entity uses fallback pattern" do
      entity = %{name: "product", settings: nil}
      record = %{uuid: "uuid-1", slug: "item"}
      cache = empty_cache()

      assert EntityData.public_path(entity, record, routes_cache: cache) ==
               "/product/item"
    end

    test "empty settings map on entity uses fallback pattern" do
      entity = %{name: "product", settings: %{}}
      record = %{uuid: "uuid-1", slug: "item"}
      cache = empty_cache()

      assert EntityData.public_path(entity, record, routes_cache: cache) ==
               "/product/item"
    end
  end

  describe "public_url/3" do
    test "prepends base_url option" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/p/:slug"}}
      record = %{uuid: "uuid-1", slug: "item"}
      cache = empty_cache()

      assert EntityData.public_url(entity, record,
               base_url: "https://site.com",
               routes_cache: cache
             ) == "https://site.com/p/item"
    end

    test "trailing slash on base_url is trimmed" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/p/:slug"}}
      record = %{uuid: "uuid-1", slug: "item"}
      cache = empty_cache()

      assert EntityData.public_url(entity, record,
               base_url: "https://site.com/",
               routes_cache: cache
             ) == "https://site.com/p/item"
    end

    test "no base_url falls back to site_url setting (empty default)" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/p/:slug"}}
      record = %{uuid: "uuid-1", slug: "item"}
      cache = empty_cache()

      # No site_url configured in tests, so base is "" and only the path remains.
      assert EntityData.public_url(entity, record, routes_cache: cache) == "/p/item"
    end
  end

  defp empty_cache do
    %{entity_patterns: %{catchall: nil}, entity_index_paths: %{}}
  end
end
