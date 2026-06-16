# Cloud-service fakes — plan

_Execution plan for `docs/cloud-fakes.md`. Builds out provider-neutral ports + verified
in-memory fakes as separate libraries, with cajeta-unit core providing only the
contract-suite harness and the faking primitives._

## Phase 0 — foundations (in cajeta-unit core)
- [ ] Contract-suite harness: a way to declare a shared abstract suite and run it against
      multiple implementations (fake + real adapters). Depends on cajeta-unit's `@Test`
      discovery (unit-spec §9).
- [ ] Environment-faking primitives already planned in `unit-plan.md` Phase 4 (FakeClock,
      FakeFileSystem, in-memory repo).

## Phase 1 — object storage (worked example, in progress)
- [x] `cajeta.cloud.objectstore`: `ObjectStore` port + `FakeObjectStore` + `ObjectStoreContract`,
      scaffolded from the `library` archetype, building to a `.cja`.
- [ ] Flesh out the port: `list(prefix)`, `Optional<Blob>` get, metadata, content-type.
- [ ] Convert the contract suite to cajeta-unit `@Test` once discovery lands.
- [ ] First real adapter (`cajeta.aws.s3`) + run the same contract suite in integration
      mode against LocalStack.

## Phase 2 — document/KV store
- [ ] `cajeta.cloud.docstore` port (put/get/query/delete by key + secondary index).
- [ ] `FakeDocStore` in-memory; contract suite.
- [ ] Adapters: `cajeta.aws.dynamo`, `cajeta.gcp.firestore`, `cajeta.azure.cosmos`.

## Phase 3 — SQL
- [ ] `cajeta.sql` thin port (connection/statement/result).
- [ ] **No engine fake.** Unit tests fake the repository above SQL (in-memory `@Repository`).
- [ ] Integration: SQLite in-memory driver + `cajeta.testkit.containers` Postgres.

## Phase 4 — emulator drivers
- [ ] `cajeta.testkit.containers`: testcontainers-style process management for LocalStack,
      Azurite, DynamoDB Local, Postgres — start/stop, port mapping, health-wait.

## Phasing notes / principles
- Each library is **independent and versioned with its provider**; fakes ship as
  `dev-dependencies` (`.testkit`), excluded from published artifacts.
- `network` capability gates real adapters; fakes need no capabilities → hermetic by
  construction.
- Every fake is **contract-verified** against the same suite the real adapter runs.

## Acceptance (per service)
1. Port interface + in-memory fake + contract suite all build to a `.cja`.
2. The fake passes the full contract suite.
3. The real adapter passes the **same** suite (integration mode).
4. A consumer swaps fake↔real purely via `@Profile`/`@TestComponent`, no app-code change.
