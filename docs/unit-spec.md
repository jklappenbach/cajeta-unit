# cajeta-unit — Specification

_A unit & integration testing framework for Cajeta. Best-of-breed: JUnit 5-style
declaration & lifecycle, AssertJ-style fluent assertions, pytest-style parameterization,
and gomock/mockall-style **compile-time** mocking — fused with Cajeta's shipped
`@Component` DI for production-overriding test contexts._

Status: design spec (v0). Builds to a `.cja`. Plan: `plan/unit-plan.md`.

---

## 1. Goals & non-goals

**Goals**
- Make tests trivial to write (`@Test`), with rich lifecycle and fluent assertions.
- **Mocks, fakes, spies, stubs** — all the tricks — within Cajeta's constraints.
- First-class **`@Component` integration**: override production components with test
  doubles for both **unit** and **integration** tests.
- Drive from the build tool's `test` task + `cajeta.coverage`.

**Non-goals (v1)**
- Property-based testing, fuzzing, snapshot testing (design hooks, don't ship).
- A browser/UI runner.

## 2. Best-of-breed comparison

We surveyed the leading frameworks and pick the best idea per dimension.

| Dimension | JUnit 5 (Jupiter) | TestNG | Mockito | pytest | Jest/Vitest | Go `testing`+testify+**gomock** | Rust `#[test]`+**mockall** | Spring Test |
|---|---|---|---|---|---|---|---|---|
| **Declaration** | `@Test` + nested | `@Test`(groups) | — | `test_*` funcs | `test()/it()` | `func TestX` | `#[test]` | builds on JUnit |
| **Lifecycle** | `@BeforeEach/All` | `@BeforeMethod` | — | fixtures | before/after | `TestMain` | — | + context |
| **Assertions** | `assertX` | `assertX` | — | `assert`+rewrite | `expect().to` | testify `assert/require` | `assert!` | — |
| **Fluent diffs** | (AssertJ add-on) | — | — | rich rewrite | rich | testify | — | — |
| **Parameterized** | `@ParameterizedTest`+sources | `@DataProvider` | — | `@parametrize`/fixtures | `test.each` | table-driven | `#[case]` (rstest) | — |
| **Fixtures/DI** | extensions | — | `@InjectMocks` | **fixtures (best)** | — | — | — | **`@MockBean`/ctx** |
| **Mocking model** | (Mockito) | — | **runtime proxy** | `unittest.mock` | `jest.mock` | **codegen** | **codegen** | Mockito |
| **Parallelism** | yes | yes | — | xdist | yes | `t.Parallel()` | threads | — |
| **Tags/filter** | `@Tag` | groups | — | markers | — | build tags | `#[ignore]`/cfg | profiles |

**Selections (best-of-breed):**
- **Declaration & lifecycle → JUnit 5**: `@Test`, `@BeforeEach/@AfterEach`,
  `@BeforeAll/@AfterAll`, `@Disabled`, `@Tag`, nested grouping. Familiar to the Java/C#/TS
  audience Cajeta targets.
- **Assertions → AssertJ + testify `require`**: fluent `assertThat(x).isEqualTo(y)` with
  rich diffs, plus `require`-style fail-fast vs `assert`-style soft (collect-all).
- **Parameterization → pytest + JUnit `@ParameterizedTest`**: value/method/CSV sources and
  a pytest-style fixture concept (which maps to `@Component` injection here).
- **Mocking → gomock/mockall (compile-time codegen)**: **Mockito-style runtime proxies are
  impossible** — Cajeta is AOT with **no runtime class generation / no
  `Proxy.newProxyInstance`** (`docs/stdlib/Reflection.md:183`). So we adopt the
  Go/Rust model: generate mocks at **compile time** from the target interface/class. The
  *API* mimics Mockito (`when(...).thenReturn(...)`, `verify(...)`), the *mechanism* is
  codegen.
- **DI / context override → Spring Test, realized via Cajeta's shipped `@TestComponent` +
  `@Profile`** (see §6) — Cajeta already has the exact mechanism Spring's `@MockBean`/
  `@TestConfiguration` provide.

## 3. Architecture

```
                       org.cajeta.unit
  ┌──────────────────────────────────────────────────────────────┐
  │ Discovery   find @Test methods (annotation-driven; see §9)      │
  │ Runner      lifecycle order, isolation, parallelism, reporting  │
  │ Assert      assertThat(...) fluent + assert/require + soft       │
  │ Params      @ParameterizedTest + value/method/csv sources        │
  │ Doubles     mocks (codegen), fakes (hand/gen), spies, stubs (§5) │
  │ Context     TestContext: profile + @TestComponent overrides (§6) │
  │ Report      console + JUnit-XML + TAP; coverage via build tool   │
  └──────────────────────────────────────────────────────────────┘
```

## 4. Test declaration, lifecycle, assertions

```cajeta
class OrderServiceTest {
    @BeforeEach void setup() { ... }
    @AfterEach  void tearDown() { ... }

    @Test void placesOrder() {
        Order o = service.place(cart);
        assertThat(o.status).isEqualTo(Status.PLACED);
        assertThat(o.lines).hasSize(3);
    }

    @Test @Disabled("flaky — see #412") void retriesOnTimeout() { ... }

    @ParameterizedTest
    @ValueSource(ints = {0, -1, 999999})
    void rejectsBadQuantity(int32 qty) {
        assertThrows(ValidationException.class, () -> service.add(qty));
    }
}
```

- Lifecycle: `@BeforeAll`/`@AfterAll` (static, once), `@BeforeEach`/`@AfterEach`
  (per-test). Ordering, `@Tag` filtering, `@Disabled`.
- Assertions: `assertThat(actual).isEqualTo/isNull/contains/hasSize/...` (AssertJ-fluent),
  plus `assertTrue/assertEquals/assertThrows`; `require*` (fail-fast) vs `assertSoftly`
  (collect all failures, report together).
- `assertThrows(Type.class, () -> ...)` integrates with the exception model; can assert on
  message/cause and, once retrieval lands, the stack trace.

## 5. Test doubles — mocks, fakes, spies, stubs

Under the **no-runtime-proxy** constraint, doubles are produced at compile time or by hand.

### Fakes
Hand-written (or generated) working in-memory implementations (e.g. an in-memory repo).
Wired into the graph via `@TestComponent` (§6). The simplest, most robust double.

### Mocks (compile-time generated — gomock/mockall model)
Annotate a test field or a target type to generate a mock implementing the interface:

```cajeta
@Mock PaymentGateway gateway;          // codegen emits a MockPaymentGateway impl

@Test void chargesOnce() {
    when(gateway.charge(any(), eq(1999))).thenReturn(Receipt.ok("r_1"));
    service.checkout(cart);
    verify(gateway, times(1)).charge(any(), eq(1999));
}
```

- A build-tool **annotation-processing pass** (or template expansion) generates, for each
  `@Mock`-ed interface, a `Mock<T>` class that: records invocations, matches argument
  matchers (`any()/eq()/argThat()`), returns stubbed values (`thenReturn/thenThrow/
  thenAnswer`), and exposes `verify`. The *surface* is Mockito; the *engine* is generated
  code, so it is AOT-friendly and reflection-free.
- Argument matchers and verification are typed (monomorphized templates — no erasure), so
  matcher/return types are checked at compile time.

### Spies (partial mocks)
Wrap a real instance, delegate by default, override selected methods. Two viable engines:
1. **Generated subclass** at compile time that forwards to the wrapped instance except for
   stubbed methods (mockall `mock!` partial style).
2. **Aspect interception** using Cajeta's **shipped** `@Around` aspects to intercept calls
   to the spied component and redirect to recorded stubs. This reuses real language
   machinery and needs no new codegen — attractive for v1. Trade-off: aspects are
   type-pointcut-scoped, so spy granularity is per-type.

### Stubs
The thin end of mocks: `when(...).thenReturn(...)` with no verification. Same engine.

### Engine decision
Primary: **compile-time codegen** for mocks/stubs (`@Mock`/`@GenerateMock`). For spies,
prefer **aspect interception** in v1 (no codegen dependency), with generated-subclass spies
as a Phase-2 upgrade. See §9 for the annotation-support dependency this implies.

## 6. Faking the environment & `@Component` test contexts (unit ↔ integration)

The point of test doubles is to control everything around the system under test (SUT). We
support the **full taxonomy** (Meszaros/Fowler) and a set of **environment fakes**, and we
make the **capability boundary** the natural faking seam — then slide along the unit ↔
integration spectrum by choosing how much of the environment is real.

### Test-double taxonomy
- **Dummy** — passed but unused (a placeholder).
- **Stub** — canned answers (`when(...).thenReturn(...)`), no verification.
- **Spy** — a stub that also records calls (aspect-interception, §5).
- **Mock** — pre-programmed with expectations; interaction-verified (`verify(...)`, §5).
- **Fake** — a working lightweight implementation (in-memory). Preferred for environments.

### Environment fakes (the "tricks")
Each external dependency is reached through an **injected component**, so faking it is just
a `@TestComponent` override — never a global patch:

- **Time** — depend on an injected `Clock` (not the static `cajeta.time.Clock`); a
  `FakeClock`/`MutableClock` lets a test set and *advance* `now()` deterministically (test
  timeouts, TTLs, schedulers without sleeping).
- **Filesystem** — a `FakeFileSystem` (in-memory, jimfs-style) implementing the fs seam for
  isolated tests; a real temp dir for integration.
- **Network / HTTP** — a `FakeHttpClient` with canned/record-replay responses, or an
  in-process stub server (WireMock-style) for integration; assert on requests made.
- **Database / repositories** — Cajeta's `@Repository` is a first-class component, so swap a
  real repo for an **in-memory fake repo** for unit tests; real DB for integration.
- **Randomness** — a seeded/scripted RNG fake for deterministic output.
- **Env / config** — a fake env/config provider instead of `System.env`.
- **External services** — fakes, or contract-tested stubs (consumer-driven contracts).

### The capability seam (Cajeta-specific)
Cajeta's capability system marks exactly the components that touch the outside world —
`clock`, `filesystem`, `network`, `random`, `env`, `process`. **Those capability
boundaries are the faking seams.** To make a test hermetic, override the capability-bearing
components with fakes; what's left needs no capabilities and is pure/deterministic. This is
a faking discipline generic frameworks lack — the type system already tells you where the
environment leaks in.

### The unit ↔ integration spectrum (profiles)
The *same* `@TestComponent`/`@Profile` machinery scales across the spectrum; a `TestContext`
picks the profile and thus the override set:

| | `unit` (isolated) | `integration` | `e2e` |
|---|---|---|---|
| SUT | real | real subsystem | real system |
| Collaborators | **all faked/mocked** | real within subsystem | real |
| Time / RNG | fake (deterministic) | fake or real | real |
| Filesystem | in-memory fake | temp dir (real) | real |
| Network / DB | fake | real DB, fake 3rd-party | real |
| Goal | fast, deterministic, pinpoints failure | seams wired correctly | whole-path confidence |

- **Isolated unit:** `@Profile("unit")` resolves every collaborator and every
  capability-bearing component to a fake/mock — no clock, fs, net, or db touched.
- **Integration:** `@Profile("integration")` keeps a subsystem real (real DB + real repos)
  and fakes only the outermost/external seams (third-party HTTP).
- **Verification style** follows the double: **state-based** (assert on a fake's recorded
  state) for fakes, **interaction-based** (`verify`) for mocks. Guidance: prefer fakes for
  the environment, mocks where the *interaction* is the contract.

## 6b. `@Component` test contexts

Cajeta **already ships** the exact mechanism: `@TestComponent` + `@Profile`
(`src/cajeta/compile/CajetaModule.cpp:584` — in test mode a `@TestComponent` hides the
production `@Component` of the same type; `@Profile("test")` selects an alternate graph).
cajeta-unit standardizes a workflow on top:

- **Unit test (maximal override):** declare the unit under test real, everything it depends
  on as a `@TestComponent` mock/fake. The DI graph resolves to doubles automatically — no
  manual wiring.
  ```cajeta
  @TestComponent class FakePaymentGateway implements PaymentGateway { ... }   // overrides prod
  ```
- **Integration test (selective override):** use the real production graph but override a
  few seams (e.g. swap the external HTTP client for a fake) with `@TestComponent`, keeping
  the rest real.
- **`@MockBean`-equivalent:** `@Mock`-generated mocks registered as `@TestComponent` so a
  generated mock drops into the graph exactly where the prod component was.
- **Custom context:** a `TestContext` selects the active profile (`unit`/`integration`/
  `test`) and the override set; `cajeta-unit` activates it the way the existing harness does
  (`CajetaModule::setActiveProfile`, used today by `JitTestHelper`).
- **Lifecycle:** `@PostConstruct`/`@PreDestroy` on components compose with `@BeforeEach`/
  `@AfterEach` (both shipped) for setup/teardown.

This means **the test-context-override feature the user wants exists at the language
level** — cajeta-unit's job is the ergonomic layer (annotations, defaults, a `TestContext`
API), not a new container.

## 7. Parameterization & fixtures

- `@ParameterizedTest` with `@ValueSource` / `@MethodSource` / `@CsvSource`.
- pytest-style **fixtures map onto `@Component` injection**: a test declares dependencies;
  the framework injects the (possibly test-profile) component. Scope follows the component's
  allocation mode (singleton/owner/transient — all shipped).

## 8. Runner & reporting

- Console reporter (pass/fail/skip, fluent-diff failures, timing).
- Machine reports: **JUnit-XML** and **TAP** for CI ingestion.
- Drives from the build tool's `test` action (`cajeta test`) and integrates with
  `cajeta.coverage` (the basic archetype already wires coverage thresholds).
- Parallel execution across test classes (Cajeta async/fibers); per-test isolation via
  fresh component scopes.

## 9. Key dependency / open question — annotation support

The one real risk. Today **user-defined annotations are largely inert** (parse-only;
`@interface` element methods not registered — `CajetaLlvmVisitor.h:1678`), usable mainly as
**aspect pointcuts**. cajeta-unit's `@Test`/`@Mock`/`@ParameterizedTest` need one of:

1. **Reflective discovery** — enumerate classes (`Class`/reflection is shipped), find
   methods carrying `@Test`, invoke via `Method.invoke*` (shipped). Requires user
   annotations to be **reflectable** (annotation metadata queryable at runtime). *Verify
   this is possible; if not, it's the first thing to fix.*
2. **Compiler-recognized test annotations** — treat `@Test` et al. like `@Component`
   (first-class), with the compiler emitting a discovery registry. Cleanest, but a compiler
   change.
3. **Aspect + registration hybrid** — `@Test` as an aspect pointcut that registers the
   method into a runtime registry the runner reads. Uses shipped machinery; least new work.

**Recommendation:** start with (3)/(1) to avoid blocking on compiler work; pursue (2) for a
polished v1. The mocking codegen (§5) similarly needs an annotation-processing hook — track
both as the framework's primary language dependency.

## 10. Out of scope / future
- Property-based / fuzz / snapshot testing (hooks only).
- Generated-subclass spies (Phase 2; aspect spies first).
- Test sharding across processes (the build tool already shards the compiler's own suite).
