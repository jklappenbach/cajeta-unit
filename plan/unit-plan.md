# cajeta-unit — Implementation Plan

_Execution plan for `docs/unit-spec.md`. Library project (`.cja`), scaffolded from the
`library` archetype._

## Phasing

### Phase 0 — skeleton (done)
- [x] `cajeta init library` scaffold; builds to `org.cajeta.unit-*.cja`.
- [x] Spec with best-of-breed comparison (`docs/unit-spec.md`).

### Phase 1 — assertions + runner + build integration (no annotation dependency) — **DONE (v0.1.0)**
- [x] `Assert.that(...)` fluent core: int (`isEqualTo/isNotEqualTo/isGreaterThan/...`),
      string (`contains/startsWith/hasLength/...`), float (`thatFloat(...).isCloseTo`),
      with rich `expected <x> but was <y>` messages.
- [x] `isTrue/isFalse/equals/fail/assertThrows(lambda)`. (`require`/`assertSoftly` and
      `assertThrows(Type.class, ...)` deferred — typed-catch matching is unreliable today.)
- [x] `TestRunner` (explicit `test(name, () -> ...)` registration), `skip(name, reason)`,
      `summary()` → exit code; console report.
- [x] **Build integration**: `cajeta test` builds a runner exe (`entry-method`) + runs it;
      a failure fails the build; `cajeta build` skips tests. (`cajeta.json` `test` task.)
- [x] Self-host: `org.cajeta.unit.selftest` — a bootstrap proves the engine's pass AND
      fail paths before the engine tests the rest. 9 green + 1 skip.

> **v1 deviations forced by the toolchain (2026-06-16), tracked for Phase 2:**
> annotations are inert + `Class.allClasses()` reflection crashes → `@Test` discovery is
> deferred (explicit registration ships first); `instanceof` on a cross-package user
> exception is unreliable + a multi-catch of a user exception mis-resolves `e.message` →
> the runner uses one `catch (Exception)`; numeric-literal overloads mis-bind → `thatFloat`
> and `isTrue/isFalse` are named apart from `that(int64)`.

### Phase 2 — discovery & runner (resolve the annotation question first)
- [ ] **Decide annotation strategy** (spec §9): reflective `@Test` discovery vs
      compiler-recognized vs aspect+registration. Spike each; pick.
- [ ] `@Test` discovery + `Runner`: lifecycle order (`@BeforeAll/@BeforeEach/...`),
      `@Disabled`, `@Tag` filtering, timing.
- [ ] Console reporter; then JUnit-XML + TAP.
- [ ] Wire to the build tool `test` action + `cajeta.coverage`.

### Phase 3 — `@Component` test contexts
- [ ] `TestContext`: select profile (`unit`/`integration`/`test`), activate via
      `CajetaModule::setActiveProfile` path (as `JitTestHelper` does).
- [ ] Document + ergonomically wrap `@TestComponent`/`@Profile` overrides (shipped) — the
      `@MockBean`-equivalent flow.
- [ ] Compose `@PostConstruct`/`@PreDestroy` with `@BeforeEach`/`@AfterEach`.

### Phase 4 — test doubles
- [ ] **Fakes**: pattern + helpers; `@TestComponent` wiring (works today).
- [ ] **Environment fakes** (spec §6): `FakeClock`/`MutableClock`, in-memory
      `FakeFileSystem`, `FakeHttpClient`/stub server, in-memory `@Repository` fakes, seeded
      RNG, fake env/config — each an override at the **capability seam** (clock/fs/net/
      random/env). Ship the FakeClock + in-memory repo first (highest leverage).
- [ ] **Spectrum profiles**: `unit` (all collaborators + capabilities faked, hermetic),
      `integration` (real subsystem, fake external seams), `e2e`; `TestContext` selects.
- [ ] **Mocks/stubs (codegen)**: `@Mock`/`@GenerateMock` → generated `Mock<T>` with
      matchers (`any/eq/argThat`), `when().thenReturn/thenThrow/thenAnswer`, `verify(...,
      times(n))`. Needs the annotation-processing hook from Phase 2.
- [ ] **Spies**: aspect-interception (`@Around`, shipped) first; generated-subclass spies
      later.

### Phase 5 — parameterization & polish
- [ ] `@ParameterizedTest` + `@ValueSource/@MethodSource/@CsvSource`.
- [ ] Fixture-as-injection (pytest-style) mapped to `@Component`.
- [ ] Parallel execution across classes; per-test isolation via fresh scopes.
- [ ] README + cookbook; publish `.cja` 0.1.0.

## Key risks / dependencies (ranked)
1. **Annotation support** (spec §9) — `@Test`/`@Mock` need reflectable user annotations,
   compiler-recognized annotations, or an aspect+registration shim. **Blocks discovery and
   mock codegen.** Resolve in Phase 2 before building on it.
2. **No runtime proxy** → mocks are compile-time codegen (gomock/mockall model), not
   Mockito runtime proxies. Spies via shipped aspects in v1.
3. Reuses shipped machinery: `@TestComponent`/`@Profile` (test contexts), `@Around`
   aspects (spies), reflection `Class`/`Method.invoke` (discovery/invocation), build-tool
   `test`+coverage. Only the annotation-processing hook is genuinely new.

## Acceptance
1. `@Test` methods are discovered and run with correct lifecycle ordering; report is
   console + JUnit-XML.
2. `assertThat(...)` gives fluent, high-signal failure diffs; `assertThrows` works.
3. A unit test overrides every dependency of the SUT with `@TestComponent` doubles via DI,
   no manual wiring; an integration test overrides only selected seams.
4. `@Mock` generates a working mock with `when/verify`; a spy intercepts via `@Around`.
5. Runs under `cajeta test` with coverage gating.
