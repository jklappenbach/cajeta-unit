# cajeta-unit — Implementation Plan

_Execution plan for `docs/unit-spec.md`. Library project (`.cja`), scaffolded from the
`library` archetype._

## Phasing

### Phase 0 — skeleton (done)
- [x] `cajeta init library` scaffold; builds to `dev.cajeta.unit-*.cja`.
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
- [x] Self-host: `dev.cajeta.unit.selftest` — a bootstrap proves the engine's pass AND
      fail paths before the engine tests the rest. 9 green + 1 skip.

> **v1 deviations forced by the toolchain (2026-06-16), tracked for Phase 2:**
> annotations are inert + `Class.allClasses()` reflection crashes → `@Test` discovery is
> deferred (explicit registration ships first); `instanceof` on a cross-package user
> exception is unreliable + a multi-catch of a user exception mis-resolves `e.message` →
> the runner uses one `catch (Exception)`; numeric-literal overloads mis-bind → `thatFloat`
> and `isTrue/isFalse` are named apart from `that(int64)`.

### Phase 2 — discovery & runner — **basic discovery DONE (v0.3)**
- [x] **Decided annotation strategy** (spec §9): **reflective `@Test` discovery**
      (`Class.allClasses()` → method `hasAnnotation("code.Test")` → `heapInstance(0)`
      + `Method.invokeObject`). No compiler work needed — the reflection foundation
      already covered it. Compiler-recognized registry left as a future optimization.
- [x] `@Test` discovery + `Runner.runAll()`: marker annotations `@Test`, `@BeforeEach`,
      `@AfterEach`, `@Disabled`; fresh instance per test (isolation); `@AfterEach`
      runs even on failure; static `@Test` supported. Self-hosted via `selftest/
      discovery/ExampleTest` (3 pass + 1 `@Disabled` skip), driven from `SelfTest.run`.
- [x] Console reporter (reuses `TestRunner` counting/`summary()` → exit code).
- [x] Wired to the build tool `test` action (the existing `entry-method` runner exe
      already calls `Runner.runAll()`).
- [ ] **Deferred to a later phase:** `@BeforeAll`/`@AfterAll` (static once-per-class),
      `@Tag` filtering, per-test timing, `@Disabled("reason")` element value, JUnit-XML
      + TAP reporters, `cajeta.coverage`.

> **Gotcha hit (workaround in `Runner`):** an UNQUALIFIED same-class `static final
> String` read currently miscompiles to an empty string, so the annotation-name
> constants are referenced qualified (`Runner.TEST`, not `TEST`). Compiler bug to fix
> upstream in cajeta-two.

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

### Phase 4a — Mockito-AoT doubles engine — **ACTIVE (targeting v0.4)**

_The user-requested "more Mockito features, AoT mechanism." No runtime proxy:
hand-written mocks subclass the target, hold a `MockEngine`, box each call's args
into an `Object[]`, record it, and (for non-void) `return (T) engine.answer(name,
args)`. The Mockito *surface* (`when/thenReturn/verify/matchers`) over an AoT
*engine* (ordinary monomorphized library code)._

> **Compiler feasibility — empirically probed 2026-06-30 (cajeta 0.7.1), see the
> `cajeta-two-object-generic-constraints` memory.** Feasible with care:
> box via `Int64.of(x)` (value-`hash()` → `eq` works); `Object[]` only as a
> local (never inline as a call arg); matchers are `boolean`-returning interfaces
> over `Object`; downcast `Object`→user/box/String is fine. **Discipline:** store
> owned values into `Object` fields with `#` transfer (`#v`) or they use-after-free;
> never use `instanceof` (false on boxes); never a func-field returning `Object`
> (IR-verify failure) — use an `Answer` interface.

- [x] **4a.1 Matchers** — `Matcher` **base class** (`boolean matches(Object)`;
      interface crashes from a `#`-factory, so it's a class) + `ArgMatchers`:
      `any()`, `eq(#Object)`, `eqInt(int64)`, `isNull()`, `notNull()`,
      `argThat((Object)->boolean)`. Self-tested (`SelfTest.run`, 12 green).
- [ ] **4a.2 MockEngine + Invocation** — `Invocation(name, Object[] args)`;
      `MockEngine.record(name, args)`, invocation list, `callCount(name)`,
      `invocations(name)`, arg access. Self-test.
- [ ] **4a.3 Stubbing** — `Mock.when(engine, name)` → `Stubbing` with
      `.with(Matcher[])`, `.thenReturn(Object)` (consecutive), `.thenThrow(Throwable)`;
      `engine.answer(name, args)` resolves first matching rule (else default/null).
      Mock body downcasts the `Object` result. Self-test round-trip (user type + box).
- [ ] **4a.4 Rich verification** — `MockVerify.on(engine, name)` →
      `.with(Matcher[])` then `.times(n)/once()/never()/atLeast(n)/atMost(n)`; each
      fails via `Assert.fail` with a high-signal message. Keep `CallLog`/`Verify`
      (name-only) intact. Self-test.
- [ ] **4a.5 ArgumentCaptor** — capture the nth arg of matched invocations
      (`values()`, `value()` = last). Self-test.
- [ ] **4a.6 InOrder** — `Mock.inOrder()`; ordered `verify(engine, name[, matchers])`
      across one or more engines via a monotonic cursor. Self-test.
- [ ] **4a.7 Docs** — `docs/mockito-aot.md` (the engine, the hand-written-mock
      recipe, the matrix of what AoT supports vs. Mockito); update `test-doubles.md`
      "what's NOT implemented", README status, spec §5.

### Phase 6 — samples/tour project (`samples/`) — **ACTIVE (targeting v0.4)**

_User-requested: a tour like `cajeta/samples/tour` — a build-tool app whose demo
packages mirror cajeta-unit's packages/classes. Each demo extends `DemoClass` and
overrides `execute()`; `Tour.main` walks a `demos[]` array._

- [ ] **6.1 Scaffold** — `samples/tour/cajeta.json` (binary archetype, entry
      `tour.Tour::main`, depends on the built `dev.cajeta.unit` `.cja` via
      `--classpath`), `DemoClass` base, `Tour` entry, `build.sh`/`run.sh`, `.gitignore`.
      Builds + runs green.
- [ ] **6.2 Demo packages mirroring unit** — `tour.assertions` (Assert fluent +
      classic), `tour.discovery` (`@Test`/lifecycle + `Runner`), `tour.doubles`
      (CallLog/Verify hand-written mock), `tour.matchers`, `tour.stubbing`,
      `tour.verify`, `tour.captor`, `tour.inorder`, `tour.inject` (TestContext).
      One demo class per unit capability; all run from `Tour.main`.
- [ ] **6.3 README** — `samples/tour/README.md` mapping each demo → the unit
      package/class it showcases (mirrors the cajeta tour README shape).

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
