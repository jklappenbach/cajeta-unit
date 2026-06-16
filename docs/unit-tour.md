# cajeta-unit — a hands-on tour

A runnable walk through cajeta-unit v0.1.0: write tests, assert, run them from
the build. Pairs with the design in [`unit-spec.md`](./unit-spec.md).

## 1. Your first test

A test is a **name** plus a **body closure**. Register it on a `TestRunner`; the
body runs immediately inside a try/catch, and a thrown assertion fails just that
test.

```cajeta
package shop.tests;

import org.cajeta.unit.Assert;
import org.cajeta.unit.TestRunner;

public class CartTests {
    public static int32 run() {
        TestRunner t = heap TestRunner();

        t.test("an empty cart totals zero", () -> {
            Cart c = heap Cart();
            Assert.that(c.total()).isEqualTo(0);
        });

        t.test("adding two items sums their prices", () -> {
            Cart c = heap Cart();
            c.add(heap Item("pen", 150));
            c.add(heap Item("pad", 350));
            Assert.that(c.total()).isEqualTo(500);
        });

        return t.summary();   // 0 = all green, 1 = any failure
    }
}
```

`summary()` prints the report and returns the process exit code — the signal the
build turns into pass/fail.

## 2. Assertions

Fluent and typed. The failure message shows expected vs actual.

```cajeta
// integers
Assert.that(order.total).isEqualTo(1999);
Assert.that(qty).isGreaterThan(0);
Assert.that(balance).isLessThanOrEqualTo(limit);

// strings
Assert.that(id).startsWith("o_");
Assert.that(id).hasLength(6);
Assert.that(name).contains("ell");

// floats — note the distinct `thatFloat` name (see "Gotchas")
Assert.thatFloat(ratio).isCloseTo(0.5, 1e-9);

// booleans — classic form (no `that(boolean)`)
Assert.isTrue(order.isPaid());
Assert.isFalse(cart.isEmpty());

// failure & exceptions
Assert.fail("should be unreachable");
Assert.assertThrows(() -> service.charge(-1));   // passes iff the body throws
```

When a check fails you get, e.g.:

```
  ✗ FAIL  adding two items sums their prices  ::  expected <500> but was <150>
```

## 3. Skipping

```cajeta
t.skip("retries on timeout", "flaky — see #412");
```

Skipped tests are reported (`○ SKIP`) and never fail the run.

## 4. Running from the build

Point the `test` task at your runner's entry method. The build compiles a test
executable and runs it; a non-zero exit **fails the build**.

```jsonc
// cajeta.json
"test": {
  "description": "Build + run unit tests",
  "actions": [
    { "action": "build", "flavor": "debug",
      "entry-method": "shop.tests.CartTests.run", "id": "testbin" },
    { "action": "test", "input": "${testbin.path}" }
  ]
}
```

```
$ cajeta test     # builds the test runner, runs it; fails the build on any failure
$ cajeta build    # builds your library only — tests are skipped
```

## 5. Self-hosting (how cajeta-unit tests itself)

A test framework can't be trusted to test itself until you've proven its engine
detects **both** a passing check (doesn't throw) **and** a failing check (does
throw) — otherwise a broken `isEqualTo` that always "passes" would make every
self-test green. cajeta-unit's `org.cajeta.unit.selftest.SelfTest` does exactly
this: a `bootstrap()` verifies both paths with raw try/catch (no runner), and
only then uses the now-trusted engine to test the rest. It's worth reading as the
reference for the negative-test discipline.

## 6. Gotchas (Cajeta-specific, v0.1.0)

- **Floats use `Assert.thatFloat(...)`, booleans use `Assert.isTrue/isFalse`.**
  An integer literal (`that(1)`) would mis-bind to a `that(float64)`/
  `that(boolean)` overload, so those entry points are deliberately named apart to
  keep the integer `that(...)` path unambiguous.
- **A thrown exception in a test fails it** — whether a failed assertion or an
  unexpected error. (v0.1.0 reports both as `✗ FAIL`.)

## What's next

Annotation-driven `@Test` discovery (no manual registration), `@Component`/
`@TestComponent` test contexts, and compile-time mocks/fakes/spies are designed
in [`unit-spec.md`](./unit-spec.md) and staged on top of this assertion core.
