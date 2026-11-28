# PR #59 review

- **BUG - HIGH**. FieldQuery selected matching UUIDs, then fetched the records again by UUID alone. An intervening status or data update could return a trashed row or a value outside the requested filter.
- **BUG - HIGH**. Index discovery searched the whole schema. An unrelated table's index with the generated name could receive the ownership comment and later be dropped. The ownership prefix also contained underscores that PostgreSQL interpreted as wildcards in a LIKE pattern.
- **BUG - MEDIUM**. The DDL statement allowed long builds, but the enclosing connection checkout still used the repository timeout. A valid concurrent build could lose its connection mid-build.
- **BUG - MEDIUM**. A JSON object in a field's indexed option raised during error formatting. This affected blueprint imports and context callers passing malformed definitions.
- **IMPROVEMENT - MEDIUM**. Daily repair loaded every blueprint and its creator, scanned for orphan indexes it would skip, then reloaded each blueprint and creator under lock. It only needs entity UUIDs and current field definitions.
- **BUG - MEDIUM**. The date cast validated the first ten characters and ignored everything after them. A stored value such as `2026-12-01oops` matched a December 1 filter.
