# Annotation-driven `@Test` discovery

cajeta-unit discovers and runs tests by reflection — no explicit registration, no
codegen. Annotate methods with `@Test`; `Runner.runAll()` finds them across the whole
binary and runs them.

## Writing tests

```cajeta
package myapp;

import org.cajeta.unit.Assert;

public class CalculatorTest {
    Calculator calc;

    @BeforeEach
    public void setUp() {
        this.calc = heap Calculator();
    }

    @Test
    public void addsTwoNumbers() {
        Assert.that(this.calc.add(2, 2)).isEqualTo(4);
    }

    @Test
    public void subtracts() {
        Assert.that(this.calc.sub(5, 3)).isEqualTo(2);
    }

    @Test
    @Disabled
    public void notReadyYet() {
        Assert.fail("never runs while @Disabled");
    }

    @AfterEach
    public void tearDown() {
        // cleanup — runs after every test, even a failing one
    }
}
```

The annotations (`@Test`, `@BeforeEach`, `@AfterEach`, `@Disabled`) are applied **bare** —
no import. They canonicalize to package `code` in the compiler, which is how the runner
matches them.

## Running

```cajeta
import org.cajeta.unit.Runner;

public final class TestMain {
    public static int32 run() {
        return Runner.runAll();   // 0 = all green, 1 = any failure
    }
}
```

Point the build tool's `test` task at it (`entry-method: myapp.TestMain.run`); a non-zero
exit fails the build. The whole suite is one `--emit=exe` binary, so the test classes must
be in the same source root (a `.cja` on the classpath contributes declarations, not linked
code).

## Semantics

- **Discovery**: every class in the binary is scanned; a class with no `@Test` method
  contributes nothing. `allClasses()` is unbounded reflection, so a test binary keeps the
  full class registry (expected — you want every test present).
- **Isolation**: a fresh instance of the test class is constructed (`Class.heapInstance(0)`,
  i.e. its public no-arg constructor) for **each** `@Test` method, so state doesn't leak
  between tests.
- **Lifecycle**: every `@BeforeEach` runs before the body; every `@AfterEach` runs after —
  including when the test (or a `@BeforeEach`) threw, so teardown is reliable. A throw in
  teardown fails an otherwise-passing test. (`@BeforeAll`/`@AfterAll` are not yet
  implemented.)
- **Skipping**: a `@Test @Disabled` method is reported as skipped and never executed.
- **Static tests**: a static `@Test` is invoked with no instance and no lifecycle.
- **Failure**: a thrown `AssertionFailure` — or any other throw — fails that test; the rest
  still run. The reporter prints per-test lines and a `passed / failed / skipped` summary.

## Not yet implemented

`@BeforeAll`/`@AfterAll` (static, once per class), `@Tag` filtering, per-test timing,
`@Disabled("reason")` element values, and JUnit-XML / TAP reporters. Explicit registration
via `TestRunner.test(name, () -> ...)` remains available for code that prefers it.
