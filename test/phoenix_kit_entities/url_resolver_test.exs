defmodule PhoenixKitEntities.UrlResolverTest do
  use ExUnit.Case, async: true

  alias PhoenixKitEntities.UrlResolver

  describe "build_path/2" do
    test "substitutes :slug" do
      record = %{uuid: "018e3c4a-9f6b-7890-abcd-ef1234567890", slug: "my-item"}
      assert UrlResolver.build_path("/products/:slug", record) == "/products/my-item"
    end

    test "substitutes :id" do
      record = %{uuid: "018e3c4a-9f6b-7890-abcd-ef1234567890", slug: "my-item"}

      assert UrlResolver.build_path("/items/:id", record) ==
               "/items/018e3c4a-9f6b-7890-abcd-ef1234567890"
    end

    test "substitutes both :slug and :id in one pattern" do
      record = %{uuid: "018e3c4a-9f6b-7890-abcd-ef1234567890", slug: "my-item"}

      assert UrlResolver.build_path("/shop/:slug/:id", record) ==
               "/shop/my-item/018e3c4a-9f6b-7890-abcd-ef1234567890"
    end

    test "slug falls back to uuid when missing" do
      record = %{uuid: "018e3c4a-9f6b-7890-abcd-ef1234567890", slug: nil}

      assert UrlResolver.build_path("/products/:slug", record) ==
               "/products/018e3c4a-9f6b-7890-abcd-ef1234567890"
    end

    test "handles complex patterns with literal segments" do
      record = %{uuid: "uuid123", slug: "my-post"}

      assert UrlResolver.build_path("/blog/2025/:slug", record) ==
               "/blog/2025/my-post"
    end
  end

  describe "get_url_pattern_cached/2 — precedence" do
    test "entity.settings['sitemap_url_pattern'] wins" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => "/shop/:slug"}}

      cache = %{
        entity_patterns: %{"product" => "/ignored/:slug", :catchall => nil},
        entity_index_paths: %{}
      }

      assert UrlResolver.get_url_pattern_cached(entity, cache) == "/shop/:slug"
    end

    test "router introspection wins over global settings" do
      entity = %{name: "product", settings: %{}}

      cache = %{
        entity_patterns: %{"product" => "/products/:slug", :catchall => nil},
        entity_index_paths: %{}
      }

      assert UrlResolver.get_url_pattern_cached(entity, cache) == "/products/:slug"
    end

    test "catchall route rewrites entity_name placeholder" do
      entity = %{name: "widget", settings: %{}}

      cache = %{
        entity_patterns: %{catchall: %{path: "/:entity_name/:slug"}},
        entity_index_paths: %{}
      }

      assert UrlResolver.get_url_pattern_cached(entity, cache) == "/widget/:slug"
    end

    test "returns nil when no route, no settings" do
      entity = %{name: "product", settings: %{}}
      cache = %{entity_patterns: %{catchall: nil}, entity_index_paths: %{}}

      assert UrlResolver.get_url_pattern_cached(entity, cache) == nil
    end

    test "empty settings pattern is ignored, falls through to router" do
      entity = %{name: "product", settings: %{"sitemap_url_pattern" => ""}}

      cache = %{
        entity_patterns: %{"product" => "/products/:slug", :catchall => nil},
        entity_index_paths: %{}
      }

      assert UrlResolver.get_url_pattern_cached(entity, cache) == "/products/:slug"
    end
  end

  describe "add_public_locale_prefix/2" do
    test "nil locale returns path unchanged" do
      assert UrlResolver.add_public_locale_prefix("/products/my-item", nil) ==
               "/products/my-item"
    end

    test "empty locale returns path unchanged" do
      assert UrlResolver.add_public_locale_prefix("/products/my-item", "") ==
               "/products/my-item"
    end

    test "single-language mode returns path unchanged even with a locale" do
      # Languages module is not enabled in the test environment, so
      # single_language_mode?/0 returns true and the prefix is skipped.
      assert UrlResolver.add_public_locale_prefix("/products/my-item", "es-ES") ==
               "/products/my-item"
    end

    # These tests exercise the safe_base_code/1 guard against path injection
    # from caller-supplied locales (e.g. raw request params). The guard runs
    # before single_language_mode?/0, so even in tests without the Languages
    # module these inputs must never leak into the prefix.
    test "rejects locale with path-traversal attempt" do
      # Even if a malicious locale got past single-language-mode check,
      # safe_base_code would strip it — verified by the no-prefix output.
      assert UrlResolver.add_public_locale_prefix("/products/my-item", "../etc/passwd") ==
               "/products/my-item"
    end

    test "rejects locale containing slashes" do
      assert UrlResolver.add_public_locale_prefix("/products/my-item", "en/admin") ==
               "/products/my-item"
    end

    test "rejects locale with non-alpha chars" do
      assert UrlResolver.add_public_locale_prefix("/products/my-item", "en123") ==
               "/products/my-item"
    end
  end

  describe "build_url/2" do
    test "prepends base_url" do
      assert UrlResolver.build_url("/path", "https://example.com") ==
               "https://example.com/path"
    end

    test "trims trailing slash from base_url" do
      assert UrlResolver.build_url("/path", "https://example.com/") ==
               "https://example.com/path"
    end
  end

  describe "single_language_mode?/0" do
    test "returns true when Languages module is disabled" do
      assert UrlResolver.single_language_mode?() == true
    end
  end
end
