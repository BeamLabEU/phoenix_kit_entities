# PR #59 follow-up

FieldQuery now loads the returned record data from the same statement that applies filtering, ordering, and pagination. Association preloads and language resolution still run on the results. A regression test counts reads of the record table and checks both preloads.

Index discovery now checks the indexed table and uses literal comment prefixes. A conflicting relation name fails the create before a comment can be written. A PostgreSQL regression test reserves the generated name on the blueprint table and verifies that the index keeps its original comment.

Synchronization gives the checkout the same unlimited timeout as the DDL. The advisory lock wait retains its own deadline. Daily repair selects UUIDs, reads field definitions under lock, and leaves the orphan scan to full synchronization.

Malformed index options now produce a changeset error. The regression passes a nested JSON object through the entity update API.

The V2 date function now accepts only a complete calendar date with optional surrounding ASCII whitespace. A regression checks that a valid prefix followed by garbage cannot match a date filter.

The PostgreSQL-backed suite reported 1,720 tests, zero failures, and two default exclusions for unreleased core behavior. A separate check on a connection outside the sandbox created a valid index with concurrent DDL, removed the field's index option, and verified that synchronization dropped the index.

`mix precommit` passed, including strict Credo, Dialyzer, the Hex audit, and all 16 JavaScript tests.
