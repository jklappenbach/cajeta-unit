# cajeta-unit

A unit-testing framework for [Cajeta](https://github.com/jklappenbach/cajeta) —
fluent assertions, a self-reporting runner, and build-tool integration so tests
run as part of the build and a failure fails the build.

```cajeta
import dev.cajeta.unit.Assert;
import dev.cajeta.unit.TestRunner;

public class MathTests {
    public static int32 run() {
        TestRunner t = heap TestRunner();

        t.test("two plus two", () -> {
            Assert.that(2 + 2).isEqualTo(4);
        });
        t.test("a name is shaped right", () -> {
            Assert.that("o_42").startsWith("o_");
            Assert.that("o_42").hasLength(4);
        });
        t.test("charging a negative amount is rejected", () -> {
            Assert.assertThrows(() -> service.charge(-1));
        });
        t.skip("flaky timeout", "see #412");

        return t.summary();   // prints the report; returns 0 = green, 1 = any failure
    }
}
```

```
$ cajeta test
== cajeta-unit self-tests ==
  ✓ PASS  two plus two
  ✓ PASS  a name is shaped right
  ✓ PASS  charging a negative amount is rejected
  ○ SKIP  flaky timeout  (see #412)

Tests: 3 passed, 0 failed, 1 skipped
```

## Assertions

Fluent, AssertJ-style, with high-signal failure messages
(`expected <2> but was <1>`):

| Subject | Entry point | Checks |
|---|---|---|
| integers | `Assert.that(int64)` | `isEqualTo` `isNotEqualTo` `isGreaterThan` `isLessThan` `isGreaterThanOrEqualTo` `isLessThanOrEqualTo` `isZero` `isPositive` `isNegative` |
| strings | `Assert.that(String)` | `isEqualTo` `isNotEqualTo` `contains` `startsWith` `endsWith` `isEmpty` `isNotEmpty` `hasLength` |
| floats | `Assert.thatFloat(float64)` | `isEqualTo` `isCloseTo(value, tolerance)` `isGreaterThan` `isLessThan` |
| booleans | `Assert.isTrue(cond)` / `Assert.isFalse(cond)` | — |
| any | `Assert.fail(msg)` · `Assert.assertThrows(() -> ...)` | — |

A failing check throws `AssertionFailure`; the runner catches it, marks that test
failed, prints why, and continues. (`Assert.thatFloat` and `Assert.isTrue` have
distinct names on purpose: an integer literal like `that(1)` would otherwise
mis-bind to a `that(float64)`/`that(boolean)` overload.)

## Running tests from the build

The `test` task builds a test-runner executable and runs it; a non-zero exit
fails the build:

```jsonc
// cajeta.json
"test": {
  "actions": [
    { "action": "build", "flavor": "debug",
      "entry-method": "your.pkg.Tests.run", "id": "testbin" },
    { "action": "test", "input": "${testbin.path}" }
  ]
}
```

- `cajeta test` — build + run the tests; **a failure fails the build**.
- `cajeta build` — build only; **tests are skipped** (no test run).

## Documentation

- **[docs/unit-tour.md](docs/unit-tour.md)** — a hands-on tour: writing tests,
  every assertion, the runner, and wiring the build.
- **[docs/mockito-aot.md](docs/mockito-aot.md)** — Mockito-style mocks (AoT):
  `when/thenReturn/thenThrow`, argument matchers, `verify` (`times/atLeast/...`),
  argument capture, and in-order verification over a hand-written mock + engine.
- **[docs/test-doubles.md](docs/test-doubles.md)** — record-only `CallLog`/`Verify`
  doubles and the `@Inject` override (`TestContext`).
- **[docs/unit-spec.md](docs/unit-spec.md)** — the full design and the
  best-of-breed comparison (JUnit 5 / AssertJ / pytest / gomock / Spring Test).
- **[plan/unit-plan.md](plan/unit-plan.md)** — the roadmap and what each phase ships.

## Status

**v0.1.0 — Phase 1 (assertions + runner + build integration), self-hosted.**
cajeta-unit tests itself: a bootstrap proves the assertion engine detects both
passing *and* failing checks before the engine is used to test the rest of the
framework (see `dev.cajeta.unit.selftest`).

Since then: annotation-driven `@Test` discovery (v0.3) and a **Mockito-style
AoT mock engine** (v0.4) — `when/thenReturn/thenThrow`, argument matchers,
`verify` (`times/atLeast/atMost`), argument capture, and in-order verification
over hand-written mocks (see [docs/mockito-aot.md](docs/mockito-aot.md)).

Roadmap (see the plan): auto-generated `@Mock` subclasses (needs a compiler
codegen hook), spies, environment fakes (`FakeClock`, in-memory repos),
`@BeforeAll`/`@AfterAll`/`@Tag`, and JUnit-XML / TAP reporters.

## License

Apache-2.0.
