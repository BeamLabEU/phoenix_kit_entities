defmodule PhoenixKitEntities.UrlResolver do
  @moduledoc """
  Logic for resolving entity and record URLs based on router introspection,
  entity settings, and global configuration.

  Extracted from SitemapSource to provide a shared API for public URL generation.
  """

  require Logger

  alias PhoenixKit.Modules.Languages
  alias PhoenixKit.Modules.Sitemap.LocalePath
  alias PhoenixKit.Modules.Sitemap.RouteResolver
  alias PhoenixKit.Settings
  alias PhoenixKit.Utils.Multilang

  @type routes_cache :: %{
          optional(:all_routes) => list(),
          optional(:content_routes) => list(),
          optional(:index_routes) => list(),
          required(:entity_patterns) => map(),
          required(:entity_index_paths) => map()
        }

  @doc """
  Builds a cache of all routes for efficient lookups.

  For hot loops (e.g. rendering a listing of records), build the cache once
  via this function and pass it as `:routes_cache` to `EntityData.public_path/3`.
  """
  @spec build_routes_cache() :: routes_cache()
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

  # Find catchall content route like /:entity_name/:slug or /:type/:id.
  #
  # Restricted to second-segment :slug or :id so unrelated 2-param routes
  # (e.g. /:category/:item, /:owner/:repo) are not silently classified as the
  # entity catchall and rewritten by every public_path/3 call.
  defp find_catchall_content_route(routes) do
    Enum.find(routes, fn route ->
      Regex.match?(~r{^/:[a-z_]+/:(slug|id)$}, route.path)
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
  Resolves the URL pattern for an entity using a pre-built routes cache.

  Resolution chain: `entity.settings["sitemap_url_pattern"]` → router introspection
  (explicit or catchall) → `sitemap_entity_<name>_pattern` setting → global
  `sitemap_entities_pattern`. Returns `nil` if none match.
  """
  @spec get_url_pattern_cached(map(), routes_cache()) :: String.t() | nil
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

  # An empty string is treated as "unset" — same convention as the per-entity
  # `sitemap_url_pattern` guard in `get_pattern_from_entity_settings/1`. This
  # matters because the admin-UI schema (`SitemapSource.sitemap_settings_schema/0`)
  # declares `""` as this setting's default, so a blank value can be persisted;
  # without this guard an empty global pattern would resolve to `""` and collapse
  # every eligible record URL to the site root.
  defp get_global_pattern(entity) do
    case safe_get_setting("sitemap_entities_pattern") do
      pattern when is_binary(pattern) and pattern != "" ->
        String.replace(pattern, ":entity_name", entity.name)

      _ ->
        nil
    end
  end

  # Settings lookup may fail if the Settings table isn't available (tests without
  # a repo, transient DB issues, misinstalled module). In that case we want
  # URL generation to fall through the chain, not crash the caller.
  #
  # Rescues are narrowed to the well-known DB-availability exceptions so real
  # bugs (KeyError, FunctionClauseError, etc.) still surface.
  defp safe_get_setting(key) do
    Settings.get_setting(key)
  rescue
    e in [
      DBConnection.ConnectionError,
      DBConnection.OwnershipError,
      Postgrex.Error,
      Ecto.QueryError,
      RuntimeError,
      ArgumentError
    ] ->
      Logger.debug("UrlResolver.safe_get_setting/1 falling back: #{Exception.message(e)}")
      nil
  catch
    # The rescue list names the DB-availability exceptions deliberately — but
    # an unreachable pool EXITS rather than raising, so the guard stopped one
    # step short of the case it was written for. These resolve public URLs.
    :exit, _ -> nil
  end

  defp safe_get_setting(key, default) do
    Settings.get_setting(key, default)
  rescue
    e in [
      DBConnection.ConnectionError,
      DBConnection.OwnershipError,
      Postgrex.Error,
      Ecto.QueryError,
      RuntimeError,
      ArgumentError
    ] ->
      Logger.debug("UrlResolver.safe_get_setting/2 falling back: #{Exception.message(e)}")
      default
  catch
    :exit, _ -> default
  end

  @doc """
  Resolves the index-page path for an entity using a pre-built routes cache.

  Used by the sitemap source to emit index entries (e.g. `/products` alongside
  `/products/:slug`). Returns `nil` if no index path can be resolved.
  """
  @spec get_index_path_cached(map(), routes_cache()) :: String.t() | nil
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
    e in [
      DBConnection.ConnectionError,
      DBConnection.OwnershipError,
      Postgrex.Error,
      Ecto.QueryError,
      RuntimeError,
      ArgumentError
    ] ->
      Logger.debug("UrlResolver.safe_get_boolean_setting/2 falling back: #{Exception.message(e)}")

      default
  catch
    :exit, _ -> default
  end

  @doc """
  Substitutes `:slug` and `:id` placeholders in a URL pattern with record data.

  `:slug` falls back to the record UUID when the slug is nil. Patterns without
  placeholders are returned unchanged.
  """
  @spec build_path(String.t(), map()) :: String.t()
  def build_path(pattern, record) do
    pattern
    |> String.replace(":slug", record.slug || to_string(record.uuid))
    |> String.replace(":id", to_string(record.uuid))
  end

  @doc """
  Adds a language prefix to a path for the sitemap.

  Used by `PhoenixKitEntities.SitemapSource` for hreflang-aware sitemap
  entries. The prefix decision is delegated to the framework-shared
  `PhoenixKit.Modules.Sitemap.LocalePath.emit_prefix?/2` (the same policy
  every core sitemap source uses), so entities' sitemap stays consistent
  with publishing/posts/static. This helper owns only the formatting.

  Pass `is_default: true` only when `language` is the site's primary —
  `emit_prefix?/2` trusts that flag. Consumers building public links
  should prefer `add_public_locale_prefix/2`, which derives primary-ness
  from the locale itself.

  Resolves the site-wide locale settings on every call. When building
  many URLs for the same `(language, is_default)` pair — e.g. a sitemap
  run — resolve `locale_prefix/2` once and prepend it instead.
  """
  @spec build_path_with_language(String.t(), String.t() | nil, boolean()) :: String.t()
  def build_path_with_language(path, language, is_default \\ true) do
    locale_prefix(language, is_default) <> path
  end

  @doc """
  Resolves the constant locale path-prefix for a `(language, is_default)`
  pair — `"/en"`, `""`, etc.

  The decision (via `LocalePath.emit_prefix?/2`) and base-code extraction
  read site-wide language settings, which are invariant across a single
  sitemap generation. Resolve this once and prepend the result to each
  record's path rather than calling `build_path_with_language/3` per URL,
  which re-reads those settings every time.
  """
  @spec locale_prefix(String.t() | nil, boolean()) :: String.t()
  def locale_prefix(language, is_default \\ true) do
    if LocalePath.emit_prefix?(language, is_default) do
      "/#{Languages.DialectMapper.extract_base(language)}"
    else
      ""
    end
  end

  @doc """
  Adds a language prefix for public front-end URLs.

  Policy:
  - Single-language mode → no prefix
  - Locale is `nil`, empty, or malformed → no prefix
  - Locale matches the primary language → follows the site-wide
    `Languages.default_language_no_prefix?/0` setting (when ON, skip
    the prefix; when OFF, include it — `/<base>`)
  - Otherwise → `/<base>` prefix (where `<base>` is a validated base code)

  This matches the convention used by `PhoenixKit.Utils.Routes.path/2`
  and `PhoenixKit.Utils.Routes.admin_path/2`, which both honor the same
  setting.

  The base code is validated against `^[a-z]{2,3}$` before interpolation, so
  caller-supplied locales (for example from request params) cannot inject
  arbitrary path segments.
  """
  @spec add_public_locale_prefix(String.t(), String.t() | nil) :: String.t()
  def add_public_locale_prefix(path, nil), do: path
  def add_public_locale_prefix(path, ""), do: path

  def add_public_locale_prefix(path, locale) when is_binary(locale) do
    cond do
      single_language_mode?() ->
        path

      primary_language_base?(locale) and Languages.prefixless_primary_safe?() ->
        path

      true ->
        case safe_base_code(locale) do
          nil -> path
          base -> "/#{base}#{path}"
        end
    end
  end

  # Extracts a base locale code and validates it against a strict allowlist
  # of ISO 639-style lowercase alpha codes. Returns nil for anything else so
  # the caller can fall back to an unprefixed URL rather than interpolate an
  # attacker-controlled segment into the path.
  defp safe_base_code(locale) do
    base = Languages.DialectMapper.extract_base(locale)

    if Regex.match?(~r/^[a-z]{2,3}$/, base), do: base, else: nil
  end

  defp primary_language_base?(locale) do
    primary =
      try do
        Multilang.primary_language()
      rescue
        e in [
          DBConnection.ConnectionError,
          Postgrex.Error,
          Ecto.QueryError,
          RuntimeError,
          ArgumentError
        ] ->
          Logger.debug(
            "UrlResolver.primary_language_base?/1 falling back: #{Exception.message(e)}"
          )

          nil
      catch
        :exit, _ -> nil
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
  Returns `true` when the site is effectively single-language.

  True when the Languages module is disabled or only one language is enabled;
  also true if the lookup fails (defensive fallback).
  """
  @spec single_language_mode?() :: boolean()
  def single_language_mode? do
    not Languages.enabled?() or length(Languages.get_enabled_languages()) <= 1
  rescue
    _ -> true
  catch
    :exit, _ -> true
  end

  @doc """
  Builds a full URL by prepending a base URL.

  If `base_url` is nil, falls back to the `site_url` setting (or empty string).
  """
  @spec build_url(String.t(), String.t() | nil) :: String.t()
  def build_url(path, base_url \\ nil) do
    base = base_url || safe_get_setting("site_url", "")
    normalized_base = String.trim_trailing(base, "/")
    "#{normalized_base}#{path}"
  end
end
