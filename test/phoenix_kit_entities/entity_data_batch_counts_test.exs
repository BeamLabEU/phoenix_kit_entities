defmodule PhoenixKitEntities.EntityDataBatchCountsTest do
  @moduledoc """
  `counts_by_entities/2` exists so listings showing counts for a page of
  entities run ONE grouped query — and so its tally matches what viewers
  actually show (`exclude_statuses:` mirrors their archived filtering,
  trashed is excluded like `list_by_entity/2`).
  """
  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData

  setup do
    actor = Ecto.UUID.generate()

    {:ok, a} =
      Entities.create_entity(
        %{
          name: "batch_count_a",
          display_name: "Alpha",
          display_name_plural: "Alphas",
          fields_definition: [],
          created_by_uuid: actor
        },
        actor_uuid: actor
      )

    {:ok, b} =
      Entities.create_entity(
        %{
          name: "batch_count_b",
          display_name: "Beta",
          display_name_plural: "Betas",
          fields_definition: [],
          created_by_uuid: actor
        },
        actor_uuid: actor
      )

    make = fn entity, title, status ->
      {:ok, rec} =
        EntityData.create(%{
          entity_uuid: entity.uuid,
          title: title,
          slug: String.downcase(String.replace(title, " ", "-")),
          status: status,
          data: %{},
          created_by_uuid: actor
        })

      rec
    end

    %{a: a, b: b, actor: actor, make: make}
  end

  test "one grouped query, per-entity tallies, absent entities absent", %{a: a, b: b, make: make} do
    make.(a, "A One", "published")
    make.(a, "A Two", "draft")
    make.(b, "B One", "published")

    counts = EntityData.counts_by_entities([a.uuid, b.uuid, Ecto.UUID.generate()])
    assert counts[a.uuid] == 2
    assert counts[b.uuid] == 1
    assert map_size(counts) == 2

    assert EntityData.counts_by_entities([]) == %{}
  end

  test "exclude_statuses mirrors viewer filtering", %{a: a, make: make} do
    make.(a, "Live", "published")
    make.(a, "Sleeping", "archived")

    assert EntityData.counts_by_entities([a.uuid]) == %{a.uuid => 2}

    assert EntityData.counts_by_entities([a.uuid], exclude_statuses: ["archived"]) ==
             %{a.uuid => 1}
  end

  describe "entity_uuids_matching_title/3" do
    test "one query answers 'which of these contain a match?'", %{a: a, b: b, make: make} do
      make.(a, "Oak", "published")
      make.(a, "Walnut", "published")
      make.(b, "Steel", "published")

      assert EntityData.entity_uuids_matching_title([a.uuid, b.uuid], "oak") == [a.uuid]

      # Case-insensitive, substring, and scoped to the given uuids.
      assert EntityData.entity_uuids_matching_title([a.uuid], "WALN") == [a.uuid]
      assert EntityData.entity_uuids_matching_title([b.uuid], "oak") == []
      assert EntityData.entity_uuids_matching_title([], "oak") == []
    end

    test "blank terms match nothing; statuses filter like the viewers", %{a: a, make: make} do
      make.(a, "Archived Oak", "archived")

      assert EntityData.entity_uuids_matching_title([a.uuid], "   ") == []
      assert EntityData.entity_uuids_matching_title([a.uuid], "oak") == [a.uuid]

      assert EntityData.entity_uuids_matching_title([a.uuid], "oak",
               exclude_statuses: ["archived"]
             ) == []
    end

    test "LIKE metacharacters are literal", %{a: a, b: b, actor: actor, make: make} do
      # Built inline: the slug format rejects "%", but the TITLE may
      # carry it — which is exactly the case being pinned.
      {:ok, _} =
        EntityData.create(%{
          entity_uuid: a.uuid,
          title: "50% gloss",
          slug: "fifty-gloss",
          status: "published",
          data: %{},
          created_by_uuid: actor
        })

      make.(b, "plain", "published")

      # "%" must not act as a wildcard: it matches the one real title.
      assert EntityData.entity_uuids_matching_title([a.uuid, b.uuid], "0% gl") == [a.uuid]

      # A bare "%" would match everything if unescaped.
      assert EntityData.entity_uuids_matching_title([b.uuid], "%") == []
    end
  end

  test "list_by_entity honors :limit", %{a: a, make: make} do
    for i <- 1..4, do: make.(a, "Rec #{i}", "published")

    assert length(EntityData.list_by_entity(a.uuid, limit: 2)) == 2
    assert length(EntityData.list_by_entity(a.uuid)) == 4
  end
end
