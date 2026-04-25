defmodule PhoenixKitEntities.Test.Router do
  @moduledoc """
  Minimal Router used by the LiveView test suite. Routes match the URLs
  the entities admin LiveViews push themselves to so `live/2` calls in
  tests work with the production-ish URL shape.

  `PhoenixKit.Utils.Routes.path/1` defaults to no URL prefix when the
  `phoenix_kit_settings` table is unavailable, and admin paths always
  get the default locale ("en") prefix — so our base becomes
  `/en/admin/entities`.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {PhoenixKitEntities.Test.Layouts, :root})
    plug(:protect_from_forgery)
  end

  scope "/en/admin/entities", PhoenixKitEntities.Web do
    pipe_through(:browser)

    live_session :entities_test,
      layout: {PhoenixKitEntities.Test.Layouts, :app},
      on_mount: {PhoenixKitEntities.Test.Hooks, :assign_scope} do
      live("/", Entities, :index, as: :entities)
      live("/new", EntityForm, :new, as: :entity_new)
      live("/:id/edit", EntityForm, :edit, as: :entity_edit)
      live("/:entity_slug/data", DataNavigator, :entity, as: :data_navigator)
      live("/:entity_slug/data/new", DataForm, :new, as: :data_new)
      live("/:entity_slug/data/:uuid", DataForm, :show, as: :data_show)
      live("/:entity_slug/data/:uuid/edit", DataForm, :edit, as: :data_edit)
    end
  end

  scope "/en/admin/settings/entities", PhoenixKitEntities.Web do
    pipe_through(:browser)

    live_session :entities_settings_test,
      layout: {PhoenixKitEntities.Test.Layouts, :app},
      on_mount: {PhoenixKitEntities.Test.Hooks, :assign_scope} do
      live("/", EntitiesSettings, :index, as: :entities_settings)
    end
  end
end
