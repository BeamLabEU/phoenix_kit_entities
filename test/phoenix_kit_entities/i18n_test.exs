defmodule PhoenixKitEntities.I18nTest do
  @moduledoc """
  Smoke test for the per-module i18n wiring.

  Confirms that:
    * `admin_tabs/0` and `settings_tabs/0` carry `gettext_backend:
      PhoenixKitEntities.Gettext`.
    * `permission_metadata/0` carries the same backend.
    * Locale switching on the module's own backend produces translated
      labels for a well-known msgid (regression guard for
      `priv/gettext/<locale>/LC_MESSAGES/default.po` shipping with the
      package).
    * Falls back to the raw msgid for an unknown locale.

  See `guides/per-module-i18n.md` in the `phoenix_kit` core repo for the
  full convention this test follows.
  """

  use ExUnit.Case, async: true

  # Excluded by `test/test_helper.exs` when running against a `phoenix_kit`
  # release that pre-dates the `gettext_backend` API (PR BeamLabEU/phoenix_kit#522).
  # Once the consumer's `phoenix_kit` dep resolves to a release that ships
  # `Tab.localized_label/1`, the helper detects it and these tests run
  # automatically — no follow-up edit needed.
  @moduletag :requires_phoenix_kit_i18n_api

  alias PhoenixKit.Dashboard.Tab
  alias PhoenixKitEntities.Gettext, as: EntitiesGettext

  describe "admin_tabs/0 and settings_tabs/0 wiring" do
    test "every admin tab carries the module's own gettext backend" do
      for tab <- PhoenixKitEntities.admin_tabs() do
        assert tab.gettext_backend == EntitiesGettext,
               "Tab #{inspect(tab.id)} is missing or wrong gettext_backend " <>
                 "(got #{inspect(tab.gettext_backend)})"
      end
    end

    test "every settings tab carries the module's own gettext backend" do
      for tab <- PhoenixKitEntities.settings_tabs() do
        assert tab.gettext_backend == EntitiesGettext,
               "Tab #{inspect(tab.id)} is missing or wrong gettext_backend " <>
                 "(got #{inspect(tab.gettext_backend)})"
      end
    end
  end

  describe "permission_metadata/0 wiring" do
    test "carries the module's own gettext backend" do
      meta = PhoenixKitEntities.permission_metadata()
      assert meta[:gettext_backend] == EntitiesGettext
      assert meta[:gettext_domain] == "default"
    end
  end

  describe "Tab.localized_label/1 against the module's catalogue" do
    test "ru locale resolves the admin 'Entities' tab to 'Сущности'" do
      [tab | _] = PhoenixKitEntities.admin_tabs()

      Gettext.with_locale(EntitiesGettext, "ru", fn ->
        assert Tab.localized_label(tab) == "Сущности"
      end)
    end

    test "et locale resolves the admin 'Entities' tab to 'Olemid'" do
      [tab | _] = PhoenixKitEntities.admin_tabs()

      Gettext.with_locale(EntitiesGettext, "et", fn ->
        assert Tab.localized_label(tab) == "Olemid"
      end)
    end

    test "unknown locale falls back to the raw msgid" do
      [tab | _] = PhoenixKitEntities.admin_tabs()

      Gettext.with_locale(EntitiesGettext, "zz", fn ->
        assert Tab.localized_label(tab) == tab.label
      end)
    end
  end
end
