defmodule PhoenixKitEntities.GettextCatalogueTest do
  @moduledoc """
  Guards the shipped `.po` catalogues against silent rot.

  `mix gettext.extract --merge` marks an entry `fuzzy` when a msgid it
  used to match got reworded — the old msgstr is kept (tagged `fuzzy`) so a
  human can review it. The compiled catalogue only drops `obsolete` entries
  (`Gettext.Compiler` filters strictly on `obsolete: false`); a `fuzzy`
  entry keeps compiling and serving the *stale* translation with no runtime
  signal that anything is wrong. Demonstrated during review: rewording a
  source string and re-running `mix gettext.extract --merge` left the
  reworded msgid resolving to the *old* English text via a fuzzy match.

  This test is the guard the compiler doesn't provide — it fails loudly the
  moment any shipped catalogue (including `en/`, which this package ships
  alongside `et/` and `ru/` even though `msgstr == msgid` there) picks up a
  `fuzzy` entry, so the stale translation gets caught before release
  instead of silently shipping.
  """

  use ExUnit.Case, async: true

  @locales ["en", "et", "ru"]

  for locale <- @locales do
    test "priv/gettext/#{locale}/LC_MESSAGES/default.po has no fuzzy entries" do
      locale = unquote(locale)

      po_path =
        Application.app_dir(
          :phoenix_kit_entities,
          "priv/gettext/#{locale}/LC_MESSAGES/default.po"
        )

      assert File.exists?(po_path), "expected catalogue at #{po_path}"

      %Expo.Messages{messages: messages} = Expo.PO.parse_file!(po_path)

      fuzzy_msgids =
        messages
        |> Enum.filter(&Expo.Message.has_flag?(&1, "fuzzy"))
        |> Enum.map(&msgid_text/1)

      assert fuzzy_msgids == [],
             "#{locale}/default.po has fuzzy (stale) translations for: " <>
               Enum.join(fuzzy_msgids, ", ") <>
               " — run `mix gettext.extract --merge`, fix each msgstr by hand, " <>
               "and remove the fuzzy flag."
    end
  end

  defp msgid_text(%Expo.Message.Singular{msgid: msgid}), do: IO.iodata_to_binary(msgid)
  defp msgid_text(%Expo.Message.Plural{msgid: msgid}), do: IO.iodata_to_binary(msgid)
end
