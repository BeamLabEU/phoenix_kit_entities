defmodule PhoenixKitEntities.SitemapSource do
  @moduledoc """
  Entities source for sitemap generation.

  Collects published entity records from the PhoenixKit Entities system.
  Each entity can define its own URL pattern in settings, and individual
  records can be excluded via metadata.

  ## Universal Entity Support

  This source automatically collects ALL published entities regardless of their name.
  By default, auto-pattern generation is enabled (`sitemap_entities_auto_pattern: true`),
  which means every entity with published records will be included in the sitemap.

  ## URL Pattern Resolution

  URL patterns are resolved using fallback chain:
  1. Entity-specific override: `entity.settings["sitemap_url_pattern"]`
  2. Router Introspection: automatic detection from parent app router
  3. Per-entity Settings: `sitemap_entity_{name}_pattern`
  4. Global Settings: `sitemap_entities_pattern`
  5. Auto-generated fallback: `/:entity_name/:slug` (if `sitemap_entities_auto_pattern` is true)

  Pattern variables:
  - `:slug` - Record slug
  - `:id` - Record ID
  - `:entity_name` - Entity name (for global pattern)

  ## Examples

      # Entity settings override (highest priority):
      # entity.settings = %{"sitemap_url_pattern" => "/blog/:slug"}
      # Generates: /blog/my-article

      # Router auto-detection (if parent app has route):
      # live "/pages/:slug", PagesLive, :show
      # Entity "page" generates: /pages/my-article

      # Settings override:
      # sitemap_entity_page_pattern = "/content/:slug"
      # Entity "page" generates: /content/my-article

      # Auto-generated fallback (enabled by default):
      # Entity "hydraulic_cylinder" generates: /hydraulic_cylinder/my-product
      # Entity "contact_request" generates: /contact_request/request-123

  ## Index Pages

  By default, index/list pages are included for each entity (e.g., `/page`, `/products`).
  This can be controlled via the `sitemap_entities_include_index` setting (default: true).

  Index path resolution:
  1. Entity settings: `entity.settings["sitemap_index_path"]`
  2. Router Introspection: automatic detection (e.g., `/page` or `/pages`)
  3. Per-entity Settings: `sitemap_entity_{name}_index_path`
  4. Auto-generated fallback: `/:entity_name` (if `sitemap_entities_auto_pattern` is true)

  ## Configuration

  - `sitemap_entities_auto_pattern` - Enable auto URL pattern generation (default: false)
  - `sitemap_entities_include_index` - Include entity index pages (default: true)
  - `sitemap_entity_{name}_pattern` - Per-entity URL pattern override
  - `sitemap_entity_{name}_index_path` - Per-entity index page path override
  - `sitemap_entities_pattern` - Global pattern template (e.g., "/:entity_name/:slug")

  ## Exclusion

  Records can be excluded by setting `record.metadata["sitemap_exclude"] = true`.

  ## Sitemap Properties

  **Records:**
  - Priority: 0.8 (high priority for entity content)
  - Change frequency: weekly
  - Category: Entity display name
  - Last modified: Record's date_updated timestamp

  **Index pages:**
  - Priority: 0.7
  - Change frequency: daily
  - Category: Entity display name
  - Last modified: Entity's updated_at timestamp
  """

  @behaviour PhoenixKit.Modules.Sitemap.Sources.Source

  require Logger

  alias PhoenixKit.Modules.Sitemap.RouteResolver
  alias PhoenixKit.Modules.Sitemap.UrlEntry
  alias PhoenixKit.Settings
  alias PhoenixKitEntities.EntityData
  alias PhoenixKitEntities.UrlResolver

  @impl true
  def source_name, do: :entities

  @impl true
  def sitemap_filename, do: "sitemap-entities"

  @doc """
  Returns per-entity-type sub-sitemaps.
  Each entity type gets its own sitemap file.
  """
  @impl true
  def sub_sitemaps(opts) do
    is_default = Keyword.get(opts, :is_default_language, true)

    if enabled?() and is_default do
      base_url = Keyword.get(opts, :base_url)
      language = Keyword.get(opts, :language)
      include_index = Settings.get_boolean_setting("sitemap_entities_include_index", true)
      routes_cache = UrlResolver.build_routes_cache()

      sub_maps =
        PhoenixKitEntities.list_active_entities()
        |> Enum.filter(&entity_has_public_route?(&1, routes_cache))
        |> Enum.map(fn entity ->
          entries =
            collect_entity_entries(
              entity,
              base_url,
              include_index,
              language,
              is_default,
              routes_cache
            )

          {entity.name, entries}
        end)
        |> Enum.reject(fn {_name, entries} -> entries == [] end)

      if sub_maps == [], do: nil, else: sub_maps
    else
      nil
    end
  rescue
    _ -> nil
  end

  @impl true
  def enabled? do
    PhoenixKitEntities.enabled?()
  rescue
    _ -> false
  end

  @impl true
  def collect(opts \\ []) do
    is_default = Keyword.get(opts, :is_default_language, true)

    # Entities only generate URLs for the default language
    # Non-default language URLs would lead to 404 errors
    if enabled?() and is_default do
      do_collect(opts)
    else
      []
    end
  rescue
    error ->
      Logger.warning("Entities sitemap source failed to collect: #{inspect(error)}")
      []
  end

  defp do_collect(opts) do
    base_url = Keyword.get(opts, :base_url)
    language = Keyword.get(opts, :language)
    is_default = Keyword.get(opts, :is_default_language, true)
    include_index = Settings.get_boolean_setting("sitemap_entities_include_index", true)

    # Optimization: Get all routes ONCE and build lookup map
    routes_cache = UrlResolver.build_routes_cache()

    # Early exit if no public entity routes exist
    if map_size(routes_cache.entity_patterns) == 0 and
         not Settings.get_boolean_setting("sitemap_entities_auto_pattern", false) do
      Logger.debug("Sitemap: No public entity routes found, skipping entities source")
      []
    else
      PhoenixKitEntities.list_active_entities()
      |> Enum.filter(&entity_has_public_route?(&1, routes_cache))
      |> Enum.flat_map(
        &collect_entity_entries(&1, base_url, include_index, language, is_default, routes_cache)
      )
    end
  end

  # Check if entity has a public route (either in router or auto-pattern enabled)
  defp entity_has_public_route?(entity, routes_cache) do
    entity_lower = String.downcase(entity.name)

    # Check if entity has explicit route in router
    has_explicit_route =
      Map.has_key?(routes_cache.entity_patterns, entity_lower) or
        Map.has_key?(routes_cache.entity_patterns, entity.name)

    # Check if catchall route exists (like /:entity_name/:slug)
    has_catchall_route = routes_cache.entity_patterns[:catchall] != nil

    # Check if entity has settings override
    has_settings_pattern =
      case entity.settings do
        %{"sitemap_url_pattern" => pattern} when is_binary(pattern) and pattern != "" -> true
        _ -> Settings.get_setting("sitemap_entity_#{entity.name}_pattern") != nil
      end

    # Check if auto-pattern is enabled (fallback for all entities)
    auto_pattern_enabled = Settings.get_boolean_setting("sitemap_entities_auto_pattern", false)

    has_explicit_route or has_catchall_route or has_settings_pattern or auto_pattern_enabled
  end

  defp collect_entity_entries(entity, base_url, include_index, language, is_default, routes_cache) do
    records = collect_entity_records(entity, base_url, language, is_default, routes_cache)

    if include_index do
      prepend_index_entry(records, entity, base_url, language, is_default, routes_cache)
    else
      records
    end
  end

  defp prepend_index_entry(records, entity, base_url, language, is_default, routes_cache) do
    case collect_entity_index(entity, base_url, language, is_default, routes_cache) do
      nil -> records
      index_entry -> [index_entry | records]
    end
  end

  defp collect_entity_records(entity, base_url, language, is_default, routes_cache) do
    if entity_requires_auth_cached?(entity, routes_cache) do
      Logger.debug("Sitemap: Entity '#{entity.name}' skipped - routes require authentication")
      []
    else
      do_collect_entity_records(entity, base_url, language, is_default, routes_cache)
    end
  rescue
    error ->
      Logger.warning("Failed to collect records for entity #{entity.name}: #{inspect(error)}")
      []
  end

  defp do_collect_entity_records(entity, base_url, language, is_default, routes_cache) do
    url_pattern = UrlResolver.get_url_pattern_cached(entity, routes_cache)
    effective_pattern = url_pattern || get_fallback_pattern(entity)

    if effective_pattern do
      records = EntityData.published_records(entity.uuid)
      log_pattern_usage(entity, url_pattern, effective_pattern, length(records))

      records
      |> Enum.reject(&excluded?/1)
      |> Enum.map(fn record ->
        build_entry(record, entity, effective_pattern, base_url, language, is_default)
      end)
    else
      Logger.warning(
        "Sitemap: Entity '#{entity.name}' skipped - no URL pattern configured and fallback disabled"
      )

      []
    end
  end

  defp log_pattern_usage(entity, url_pattern, effective_pattern, count) do
    if url_pattern do
      Logger.debug(
        "Sitemap: Entity '#{entity.name}' using URL pattern: #{url_pattern} (#{count} published records)"
      )
    else
      Logger.info(
        "Sitemap: Entity '#{entity.name}' using fallback pattern: #{effective_pattern} (#{count} published records)"
      )
    end
  end

  # Fallback pattern using entity name - disabled by default
  # Enable via Settings: sitemap_entities_auto_pattern = true
  # WARNING: Only enable if you're sure routes exist for all entities
  defp get_fallback_pattern(entity) do
    if Settings.get_boolean_setting("sitemap_entities_auto_pattern", false) do
      "/#{entity.name}/:slug"
    else
      nil
    end
  end

  # Collect index page entry for entity (e.g., /page, /products) - cached version
  defp collect_entity_index(entity, base_url, language, is_default, routes_cache) do
    index_path = UrlResolver.get_index_path_cached(entity, routes_cache)

    if index_path do
      # Canonical path without language prefix (for hreflang grouping)
      canonical_path = index_path
      path = UrlResolver.build_path_with_language(index_path, language, is_default)
      url = UrlResolver.build_url(path, base_url)

      UrlEntry.new(%{
        loc: url,
        lastmod: entity.date_updated || entity.date_created,
        changefreq: "daily",
        priority: 0.7,
        title: "#{entity.display_name || entity.display_name_plural || entity.name} - Index",
        category: entity.display_name || entity.name,
        source: :entities,
        canonical_path: canonical_path
      })
    else
      nil
    end
  rescue
    error ->
      Logger.warning("Failed to collect index for entity #{entity.name}: #{inspect(error)}")
      nil
  end

  # Check if entity requires auth using cached routes
  defp entity_requires_auth_cached?(entity, routes_cache) do
    entity_lower = String.downcase(entity.name)

    # Find the route for this entity in cached routes
    route =
      Enum.find(routes_cache.content_routes, fn route ->
        path_lower = String.downcase(route.path)

        String.contains?(path_lower, "/#{entity_lower}/") or
          String.contains?(path_lower, "/#{entity_lower}s/") or
          String.starts_with?(path_lower, "/#{entity_lower}/") or
          String.starts_with?(path_lower, "/#{entity_lower}s/")
      end)

    cond do
      # Found explicit route for this entity
      route != nil ->
        RouteResolver.route_requires_auth?(route)

      # Check catchall route
      routes_cache.entity_patterns[:catchall] != nil ->
        RouteResolver.route_requires_auth?(routes_cache.entity_patterns[:catchall])

      # No route found
      true ->
        false
    end
  end

  defp excluded?(record) do
    case record.metadata do
      %{"sitemap_exclude" => true} -> true
      %{"sitemap_exclude" => "true"} -> true
      _ -> false
    end
  end

  defp build_entry(record, entity, url_pattern, base_url, language, is_default) do
    # Canonical path without language prefix (for hreflang grouping)
    canonical_path = UrlResolver.build_path(url_pattern, record)
    path = UrlResolver.build_path_with_language(canonical_path, language, is_default)
    url = UrlResolver.build_url(path, base_url)

    UrlEntry.new(%{
      loc: url,
      lastmod: record.date_updated,
      changefreq: "weekly",
      priority: 0.8,
      title: record.title,
      category: entity.display_name || entity.name,
      source: :entities,
      canonical_path: canonical_path
    })
  end
end
