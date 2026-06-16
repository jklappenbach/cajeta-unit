# Cloud-service fakes — design

_How cajeta-unit supports faking cloud/infrastructure services (object storage, document
stores like DynamoDB/Firestore/Cosmos, SQL databases) for isolated unit tests and
integration tests. Companion to `unit-spec.md` §5–6. Plan: `plan/cloud-fakes-plan.md`._

## Verdict

Yes — provide cloud-service fakes. But:
1. **Fake provider-neutral *ports*, not the cloud SDKs.** (Hexagonal / ports-and-adapters.)
2. **Ship them as separate, layered libraries** — not in cajeta-unit core.
3. **Don't reimplement LocalStack/Azurite.** Provide in-memory port fakes as the default
   and *wrap* existing emulators for high-fidelity integration tests.
4. **Verify fakes with shared contract suites** so a fake provably behaves like the real
   adapter for the operations you use.

## 1. Fake the port, not the SDK

The application depends on a Cajeta-native **port**, with provider adapters and a fake
behind it:

```
            ObjectStore (port)              ← app code depends on THIS, never on an SDK
          /      |        \         \
   S3Adapter  BlobAdapter  GcsAdapter   FakeObjectStore (in-memory)
   @Profile("prod")  ...                 dev-dependency, @TestComponent override
```

A test swaps the adapter via `@TestComponent`/`@Profile` (cajeta-unit's shipped mechanism).
The fake mimics the **port's behavior**, not S3's HTTP wire protocol — far simpler and more
robust than emulating a cloud API. (Contrast Moto/LocalStack, which emulate the API; for
unit tests the in-memory port fake wins decisively.)

## 2. Two fidelity tiers

| Tier | What | Use | Cost |
|---|---|---|---|
| **A. Port-level in-memory fake** (primary) | `FakeObjectStore`, `FakeDocStore`, in-memory KV | unit + most integration; hermetic, deterministic, µs-fast | tiny |
| **B. Wire-level emulator** (wrap, don't build) | LocalStack / Azurite / DynamoDB Local via a testcontainers-style driver | high-fidelity integration: real SDK + serialization | process + startup |

Invest in **A**. For **B**, drive existing emulators — reimplementing LocalStack in Cajeta
is an infinite, low-ROI treadmill.

## 3. SQL is a special case — don't fake the engine

In-memory SQL fakes (H2-pretending-to-be-Postgres) leak dialect differences and give false
confidence. Instead:
- **Unit:** fake at the **repository/DAO port** — an in-memory `@Repository` (ties into
  cajeta-unit's in-memory-repo primitive). Don't go through SQL at all.
- **Integration:** run a **real** engine — SQLite in-memory (light) or real Postgres via
  testcontainers (fidelity), behind a thin `cajeta.sql` port.

So "fake SQL" = *fake the repository above SQL, or run real SQL* — never emulate a SQL
engine.

## 4. Library structure (separate, layered)

```
cajeta-unit                          core: doubles, @TestComponent glue,
                                     FakeClock/FakeFileSystem/in-memory-repo PRIMITIVES,
                                     the contract-suite harness
cajeta.cloud.objectstore             neutral port + contract suite     ← worked example
cajeta.cloud.docstore                neutral port: KeyValue/Document (Dynamo/Firestore/Cosmos)
cajeta.sql                           neutral port: SqlConnection/Statement
  ├─ cajeta.aws.{s3,dynamo,rds}          prod adapters @Profile("prod")
  ├─ cajeta.azure.{blob,cosmos,sql}      prod adapters
  └─ cajeta.gcp.{gcs,firestore,cloudsql} prod adapters
cajeta.cloud.*.testkit               the FAKES — in-memory adapters, shipped as DEV-deps
cajeta.testkit.containers            testcontainers-style emulator drivers (LocalStack/…)
```

Why separate libraries:
- **Leanness** — a test framework must not drag cloud SDKs into every project.
- **Independent cadence** — cloud APIs churn; fakes version with their provider port, not
  with cajeta-unit.
- **Cajeta's model rewards it** — fakes go under `dev-dependencies` (excluded from the
  published `.cja`); dead-code elimination + the capability system (`network` gates the
  real adapters) keep the prod/test split clean.

## 5. Verified fakes via contract suites

Define one **abstract port contract suite** ("an `ObjectStore` must round-trip, report
exists, delete, and return absent for missing keys…") that **both the fake and every real
adapter must pass.** This closes the "my fake lied to me" gap. cajeta-unit provides the
shared-contract harness; each cloud library provides its suite and runs it against the fake
(always) and the real adapter (in integration mode).

## 6. What lives where

- **cajeta-unit core:** generic double machinery + the environment-faking *primitives*
  (FakeClock, FakeFileSystem, in-memory repo) + the contract-suite harness. **No cloud
  knowledge.**
- **Per-provider libraries:** ports + prod adapters + `.testkit` fakes + contract suites.
- **`cajeta.testkit.containers`:** emulator process drivers.

## 7. The unit ↔ integration spectrum (applied)

- **Isolated unit:** `@Profile("unit")` → `FakeObjectStore`, in-memory repo, FakeClock —
  no network, no credentials, deterministic.
- **Integration:** `@Profile("integration")` → real adapter against a Tier-B emulator
  (LocalStack S3) or a real bucket; same **contract suite** must still pass.
- **e2e:** real services.

## 8. Worked example

`cajeta.cloud.objectstore` (scaffolded from the `library` archetype) demonstrates the whole
pattern minimally: the `ObjectStore` **port**, an in-memory **`FakeObjectStore`**, and an
**`ObjectStoreContract`** that any implementation must satisfy. See that project and
`plan/cloud-fakes-plan.md`.
