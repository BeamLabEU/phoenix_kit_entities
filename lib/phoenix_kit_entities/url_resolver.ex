defmodule PhoenixKitEntities.UrlResolver do
  @moduledoc """
  Logic for resolving entity and record URLs based on router introspection,
  entity settings, and global configuration.

  Extracted from SitemapSource to provide a shared API for public URL generation.
  """

  alias PhoenixKit.Modules.Languages
  alias PhoenixKit.Modules.Sitemap.RouteResolver
  alias PhoenixKit.Settings
  alias PhoenixKit.Utils.Multilang

  @doc """
  Builds a cache of all routes for efficient lookups.
  """
  def build_routes_cache do
    routes = RouteResolver.get_routes()

    # Pre-filter GET routes with :slug or :id params (content routes)
    content_routes =
      Enum.filter(routes, fn route ->
        route.verb == :get and
          (String.contains?(route.path, ":slug") or String.contains?(route.path, ":id"))
      end)

    # Pre-filter GET routes without params (index routes)
    index_routes =
      Enum.filter(routes, fn route ->
        route.verb == :get and
          not String.contains?(route.path, ":") and
          not String.contains?(route.path, "*")
      end)

    # Build entity name -> pattern map for quick lookups
    entity_patterns = build_entity_pattern_map(content_routes)
    entity_index_paths = build_entity_index_map(index_routes)

    %{
      all_routes: routes,
      content_routes: content_routes,
      index_routes: index_routes,
      entity_patterns: entity_patterns,
      entity_index_paths: entity_index_paths
    }
  end

  # Build map of entity_name -> url_pattern from routes
  # Also detects catchall routes like /:entity_name/:slug
  defp build_entity_pattern_map(content_routes) do
    # Check for catchall route first
    catchall_route = find_catchall_content_route(content_routes)

    content_routes
    |> Enum.reduce(%{catchall: catchall_route}, fn route, acc ->
      path_lower = String.downcase(route.path)

      # Extract entity name from path like /products/:slug or /product/:id
      case extract_entity_from_path(path_lower) do
        nil -> acc
        entity_name -> Map.put_new(acc, entity_name, route.path)
      end
    end)
  end

  # Build map of entity_name -> index_path from routes
  # Also detects catchall routes like /:entity_name
  defp build_entity_index_map(index_routes) do
    # Check for catchall index route first
    catchall_route = find_catchall_index_route(index_routes)

    index_routes
    |> Enum.reduce(%{catchall: catchall_route}, fn route, acc ->
      path_lower = String.downcase(route.path)

      # Extract entity name from path like /products or /product
      case extract_entity_from_index_path(path_lower) do
        nil -> acc
        entity_name -> Map.put_new(acc, entity_name, route.path)
      end
    end)
  end

  # Find catchall content route like /:entity_name/:slug
  defp find_catchall_content_route(routes) do
    Enum.find(routes, fn route ->
      # Match patterns like /:entity_name/:slug, /:name/:slug, /:type/:id
      Regex.match?(~r{^/:[a-z_]+/:[a-z_]+$}, route.path)
    end)
  end

  # Find catchall index route like /:entity_name
  defp find_catchall_index_route(routes) do
    Enum.find(routes, fn route ->
      # Match patterns like /:entity_name, /:name (single param at root)
      Regex.match?(~r{^/:[a-z_]+$}, route.path)
    end)
  end

  # Extract entity name from content path like /products/:slug -> "product"
  defp extract_entity_from_path(path) do
    case Regex.run(~r{^/([a-z_]+)s?/:[a-z_]+$}, path) do
      [_, name] -> String.trim_trailing(name, "s")
      _ -> nil
    end
  end

  # Extract entity name from index path like /products -> "product"
  defp extract_entity_from_index_path(path) do
    case Regex.run(~r{^/([a-z_]+)s?$}, path) do
      [_, name] -> String.trim_trailing(name, "s")
      _ -> nil
    end
  end

  @doc """
  Gets the URL pattern for an entity using cached routes.
  """
  def get_url_pattern_cached(entity, routes_cache) do
    get_pattern_from_entity_settings(entity) ||
      get_pattern_from_cache(entity, routes_cache) ||
      get_pattern_from_settings(entity)
  end

  defp get_pattern_from_entity_settings(entity) do
    case entity.settings do
      %{"sitemap_url_pattern" => pattern} when is_binary(pattern) and pattern != "" -> pattern
      _ -> nil
    end
  end

  defp get_pattern_from_cache(entity, routes_cache) do
    entity_lower = String.downcase(entity.name)

    # First try explicit route for this entity
    explicit_pattern =
      Map.get(routes_cache.entity_patterns, entity_lower) ||
        Map.get(routes_cache.entity_patterns, entity.name)

    if explicit_pattern do
      explicit_pattern
    else
      # Fall back to catchall route, replacing param with entity name
      case routes_cache.entity_patterns[:catchall] do
        nil -> nil
        %{path: path} -> String.replace(path, ~r{^/:[a-z_]+/}, "/#{entity.name}/")
      end
    end
  end

  defp get_pattern_from_settings(entity) do
    per_entity_key = "sitemap_entity_#{entity.name}_pattern"

    case safe_get_setting(per_entity_key) do
      nil -> get_global_pattern(entity)
      pattern -> pattern
    end
  end

  defp get_global_pattern(entity) do
    case safe_get_setting("sitemap_entities_pattern") do
      nil -> nil
      global_pattern -> String.replace(global_pattern, ":entity_name", entity.name)
    end
  end

  # Settings lookup may fail if the Settings table isn't available (tests without
  # a repo, transient DB issues, misinstalled module). In that case we want
  # URL generation to fall through the chain, not crash the caller.
  defp safe_get_setting(key) do
    Settings.get_setting(key)
  rescue
    _ -> nil
  end

  defp safe_get_setting(key, default) do
    Settings.get_setting(key, default)
  rescue
    _ -> default
  end

  @doc """
  Gets the index path for an entity using cached routes.
  """
  def get_index_path_cached(entity, routes_cache) do
    get_index_from_entity_settings(entity) ||
      get_index_from_cache(entity, routes_cache) ||
      get_index_from_catchall(entity, routes_cache) ||
      get_index_from_settings(entity) ||
      get_fallback_index_path(entity)
  end

  defp get_index_from_entity_settings(entity) do
    case entity.settings do
      %{"sitemap_index_path" => path} when is_binary(path) and path != "" -> path
      _ -> nil
    end
  end

  defp get_index_from_cache(entity, routes_cache) do
    entity_lower = String.downcase(entity.name)

    Map.get(routes_cache.entity_index_paths, entity_lower) ||
      Map.get(routes_cache.entity_index_paths, entity.name)
  end

  defp get_index_from_catchall(entity, routes_cache) do
    case routes_cache.entity_index_paths[:catchall] do
      %{path: _} -> "/#{entity.name}"
      _ -> nil
    end
  end

  defp get_index_from_settings(entity) do
    safe_get_setting("sitemap_entity_#{entity.name}_index_path")
  end

  defp get_fallback_index_path(entity) do
    if safe_get_boolean_setting("sitemap_entities_auto_pattern", false) do
      "/#{entity.name}"
    else
      nil
    end
  end

  defp safe_get_boolean_setting(key, default) do
    Settings.get_boolean_setting(key, default)
  rescue
    _ -> default
  end

  @doc """
  Substitutes variables in a URL pattern with record data.
  """
  def build_path(pattern, record) do
    pattern
    |> String.replace(":slug", record.slug || to_string(record.uuid))
    |> String.replace(":id", to_string(record.uuid))
  end

  @doc """
  Adds a language prefix to a path (sitemap policy: prefix every language in multilang mode).

  Used by `PhoenixKitEntities.SitemapSource` for hreflang-aware sitemap entries.
  Consumers building public links should prefer `add_public_locale_prefix/2`, which
  omits the prefix for the primary language (matching `PhoenixKit.Utils.Routes` conventions).
  """
  def build_path_with_language(path, language, _is_default \\ true) do
    if language && !single_language_mode?() do
      "/#{Languages.DialectMapper.extract_base(language)}#{path}"
    else
      path
    end
  end

  @doc """
  Adds a language prefix for public front-end URLs.

  Policy:
  - Single-language mode → no prefix
  - Locale is `nil` → no prefix (caller did not request a specific locale)
  - Locale matches the primary language → no prefix
  - Otherwise → `/<base>` prefix

  This matches the convention used by `PhoenixKit.Utils.Routes.path/2`
  (default locale served from unprefixed URLs).
  """
  @spec add_public_locale_prefix(String.t(), String.t() | nil) :: String.t()
  def add_public_locale_prefix(path, nil), do: path

  def add_public_locale_prefix(path, locale) when is_binary(locale) do
    cond do
      single_language_mode?() ->
        path

      primary_language_base?(locale) ->
        path

      true ->
        "/#{Languages.DialectMapper.extract_base(locale)}#{path}"
    end
  end

  defp primary_language_base?(locale) do
    primary =
      try do
        Multilang.primary_language()
      rescue
        _ -> nil
      end

    case primary do
      nil ->
        false

      primary_code ->
        Languages.DialectMapper.extract_base(primary_code) ==
          Languages.DialectMapper.extract_base(locale)
    end
  end

  @doc """
  Checks if the system is in single language mode.
  """
  def single_language_mode? do
    not Languages.enabled?() or length(Languages.get_enabled_languages()) <= 1
  rescue
    _ -> true
  end

  @doc """
  Builds a full URL by prepending a base URL.

  If `base_url` is nil, falls back to the `site_url` setting (or empty string).
  """
  def build_url(path, base_url \\ nil) do
    base = base_url || safe_get_setting("site_url", "")
    normalized_base = String.trim_trailing(base, "/")
    "#{normalized_base}#{path}"
  end
end
