# Test doubles & DI override — what ships today (v0.2)

`unit-spec.md` describes the full aspirational design (codegen `@Mock`,
`@Test` discovery, `@TestComponent`/`@Profile` context). This doc records what
is **actually implemented and self-tested** — which differs, because the
component framework (`@TestComponent`/`@Profile`) moved to
[cazo](https://github.com/jklappenbach/cajeta-cazo) and cajeta-unit stays
framework-neutral (only `@Inject`).

## 1. Overriding `@Inject` — `TestContext`

The language resolves `@Inject` statically. In a **test build**
(`cajeta test`, which compiles with `--profile=test`) the compiler also emits a
runtime override check at each `@Inject` site, and `TestContext` is the front
door to it:

```cajeta
import org.cajeta.unit.TestContext;

MockClock clock = heap MockClock();      // a hand-written double
TestContext.bind(Clock.class, clock);    // every @Inject Clock now resolves to clock

Service s = __cajeta_inject();           // s's @Inject Clock is `clock`
// ... exercise ...
TestContext.clear();                     // forget overrides between cases
```

- **No new annotations** — only the existing `@Inject`. Binding is by
  `T.class` (pointer identity).
- **v1 scope:** singleton-mode, **class-typed** `@Inject` fields — mock by
  subclassing the type and overriding its virtual methods. Interface-typed
  fields are not yet overridable.
- **Borrowed:** you own the double; `clear()` forgets bindings, never frees.
  Keep the double alive for as long as the injected graph uses it. Bind
  *before* the component under test is constructed.
- Overrides only take effect under `--profile=test`; in a production build the
  calls are inert (and the hook isn't compiled in).

See cajeta-two `docs/DI-override-hook.md` for the compiler mechanism.

## 2. Mocks — `CallLog` + `Verify`

Cajeta monomorphizes and has no dynamic proxies, so mocks are **hand-written**:
a mock subclasses/implements the type, holds a `CallLog`, and records each call.
The test verifies against the log.

```cajeta
public class MockMailer extends Mailer {
    public CallLog log = heap CallLog();
    public void send(String to) { this.log.track("send"); }
}

// in a test:
MockMailer m = heap MockMailer();
TestContext.bind(Mailer.class, m);
// ... exercise the code under test ...
Verify.received(m.log, "send");
Verify.receivedTimes(m.log, "send", 1);
Verify.neverReceived(m.log, "delete");
```

`CallLog`: `track(method)`, `count(method)`, `total()`, `received(method)`,
`reset()`. `Verify`: `received` / `receivedTimes` / `neverReceived` — each
fails the test (throws `AssertionFailure`) on mismatch, like an assertion.

## 3. Fakes — hand-written working doubles

A **fake** is a real, simplified implementation (an in-memory repository, a
fake clock). No verification machinery needed: assert on its observable state
with `Assert` directly. This is the model for cloud-service fakes
(`cloud-fakes.md`) — fake the **port**, not the SDK.

## What's NOT yet implemented

- Codegen `@Mock` (Mockito-style auto-mocks) — doubles are hand-written.
- `@Test` discovery — tests are registered explicitly on `TestRunner`.
- Argument matching / stubbed return programming on `CallLog` (record-only v1).
- Interface-typed `@Inject` override.
