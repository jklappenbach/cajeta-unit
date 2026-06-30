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
import dev.cajeta.unit.TestContext;

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

## Mockito-style mocks (v0.4)

Beyond record-only `CallLog`/`Verify`, cajeta-unit now ships a full **AoT
Mockito surface** — `when(...).thenReturn/thenThrow`, argument matchers,
`verify` with `times/atLeast/atMost`, argument capture, and in-order checks —
built on a hand-written mock + `MockEngine` (no runtime proxy). See
[`mockito-aot.md`](mockito-aot.md). Use `CallLog`/`Verify` for the simplest
record-and-check doubles; reach for `MockEngine`/`Mock`/`MockVerify` when you
need stubbed return values, argument matching, or call-order assertions.

## What's NOT yet implemented

- Codegen `@Mock` (auto-generated mock subclasses) — mocks are hand-written
  (the engine they forward to is shipped).
- `thenAnswer` (dynamic callback), spies (partial mocks), and a `getAllValues()`
  captor list — see the matrix in [`mockito-aot.md`](mockito-aot.md).
- Argument matching / stubbed returns on `CallLog` itself (use `MockEngine`).
- Interface-typed `@Inject` override.
