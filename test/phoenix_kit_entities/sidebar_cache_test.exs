defmodule PhoenixKitEntities.SidebarCacheTest do
  use ExUnit.Case, async: false

  alias PhoenixKit.Dashboard.Registry, as: DashboardRegistry

  @entities_cache_key :entities_children_cache

  describe "invalidate_entities_cache/0" do
    setup do
      # Ensure the DashboardRegistry ETS table exists for this test.
      # If the Registry is not initialized, skip — cache logic is a no-op in that case.
      if DashboardRegistry.initialized?() do
        :ok
      else
        {:ok, _} = start_supervised(DashboardRegistry)
        :ok
      end

      :ok
    end

    test "match_delete clears all per-locale cache entries" do
      table = DashboardRegistry.ets_table()
      now = System.monotonic_time(:millisecond)

      # Seed cache entries for multiple locales
      :ets.insert(table, {{@entities_cache_key, "en-US"}, [:seeded_en], now})
      :ets.insert(table, {{@entities_cache_key, "es-ES"}, [:seeded_es], now})
      :ets.insert(table, {{@entities_cache_key, nil}, [:seeded_none], now})

      assert length(:ets.match(table, {{@entities_cache_key, :_}, :_, :_})) == 3

      assert :ok = PhoenixKitEntities.invalidate_entities_cache()

      assert :ets.match(table, {{@entities_cache_key, :_}, :_, :_}) == []
    end
  end
end
