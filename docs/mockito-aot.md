# Mockito-style mocks, AoT (v0.4)

cajeta-unit gives you the **Mockito surface** — `when(...).thenReturn(...)`,
argument matchers, `verify(...)`, argument capture, in-order checks — over an
**ahead-of-time engine**, not a runtime proxy. Cajeta is AOT-compiled with no
dynamic class generation (`Proxy.newProxyInstance` does not exist), so a mock is a
**hand-written subclass** that forwards each call to a [`MockEngine`](../src/main/cajeta/dev/cajeta/unit/MockEngine.cajeta).
The *API* mimics Mockito; the *mechanism* is ordinary monomorphized library code.

This is the gomock/mockall model. The longer-term goal is to **generate** these
subclasses from an annotation (`@Mock`); that needs a compiler codegen hook (see
`unit-spec.md` §5/§9). Everything below works **today** and is self-tested in
`dev.cajeta.unit.selftest.SelfTest`.

## The recipe: a hand-written mock

Subclass the real type, hold a `MockEngine`, and forward each method. A non-void
method boxes its arguments, calls `engine.handle(name, #args)`, and downcasts the
answer; a void method calls `handle` and ignores the result (so `thenThrow` still
fires).

```cajeta
import dev.cajeta.unit.MockEngine;
import cajeta.lang.Int64;

public class MockGateway extends Gateway {
    public MockEngine engine;
    public MockGateway() { this.engine = heap MockEngine(); }   // init in a ctor, not inline

    public Coin charge(int64 amount) {
        Object[] a = { Int64.of(amount) };                      // box args into an Object[] local
        return (Coin) this.engine.handle("charge", #a);         // record + answer, then downcast
    }

    public void refund(int64 amount) {
        Object[] a = { Int64.of(amount) };
        this.engine.handle("refund", #a);                       // void: ignore the answer
    }
}
```

## Stubbing — `Mock.when(...)`

```cajeta
Mock.when(gw.engine, "charge").thenReturn(#(heap Coin(50)));            // any args
Matcher[] m = { ArgMatchers.eqInt(1999) };
Mock.when(gw.engine, "charge").withArgs(#m).thenReturn(#(heap Coin(0))); // matched args
Mock.when(gw.engine, "charge").thenReturn(#Int64.of(1)).thenReturn(#Int64.of(2)); // consecutive
Mock.when(gw.engine, "charge").thenThrow(#(heap DeclineError("no funds"))); // throw
```

- The **last** matching rule wins (Mockito ordering). An unstubbed call answers
  `null`.
- Consecutive `thenReturn`s are returned in order; the last repeats once exhausted.
- The builder method is `withArgs` (not `with` — a reserved word) and takes a
  `Matcher[]` (empty set / no `withArgs` ⇒ matches any arguments).
- `thenThrow` takes a `RecoverableException` (or a domain subclass).

## Argument matchers — `ArgMatchers`

| Matcher | Meaning |
|---|---|
| `any()` | any argument, including null |
| `eq(#Object)` | value-equal (dispatches the box type's `hash()`) |
| `eqInt(int64)` | `eq` for an integer (boxes for you) |
| `isNull()` / `notNull()` | null / non-null |
| `argThat((Object) -> boolean)` | a custom predicate (downcast inside it) |

Matchers must not use `instanceof` (unreliable on boxed primitives); compare via
`Object` equality or a downcast inside `argThat`.

## Verification — `MockVerify` (static)

```cajeta
MockVerify.times(gw.engine, "charge", 2);
MockVerify.once(gw.engine, "refund");
MockVerify.never(gw.engine, "void");
MockVerify.atLeast(gw.engine, "retry", 2);
MockVerify.atMost(gw.engine, "retry", 5);

Matcher[] m = { ArgMatchers.eqInt(1999) };
MockVerify.timesWith(gw.engine, "charge", #m, 1);   // argument-matched count
MockVerify.neverWith(gw.engine, "charge", #m);
int32 n = MockVerify.count(gw.engine, "charge");    // raw count for custom asserts
```

`MockVerify` is **static** by design — a fluent `verify(...).times()` builder
would stash a borrowed engine in a heap object and read it back, which is
unreliable in the current toolchain. Each check counts directly on the engine.

## Argument capture

The engine owns every recorded argument, so capture is a query on it (downcast
the boxed result):

```cajeta
gw.charge(1999);
Int64 amt = (Int64) gw.engine.lastArgOf("charge", 0);     // last call's arg 0
Object first = gw.engine.argOf("charge", 0, 0);           // 1st call's arg 0
```

## In-order verification — `InOrder`

```cajeta
InOrder order = heap InOrder();
order.verify(file.engine, "open");
order.verify(file.engine, "write");
order.verify(file.engine, "close");   // fails if close was recorded before write
```

A monotonic cursor scans forward for each next call; ordering is verified **per
engine**. `verifyWith(engine, name, #Matcher[])` adds argument matching.

## What AoT supports vs. Mockito

| Feature | cajeta-unit (AoT) | Notes |
|---|---|---|
| `when().thenReturn()/thenThrow()` | ✅ | hand-written mock + engine |
| consecutive returns | ✅ | last repeats |
| matchers `any/eq/isNull/notNull/argThat` | ✅ | `ArgMatchers` |
| `verify` `times/never/atLeast/atMost` | ✅ | `MockVerify` (static) |
| argument matching in verify | ✅ | `timesWith` / `neverWith` |
| argument capture | ✅ | `engine.argOf` / `lastArgOf` |
| in-order verification | ✅ (per engine) | cross-engine ordering: later |
| `thenAnswer` (dynamic callback) | ⛔ | a func-field returning `Object` fails IR-verify today |
| spies (partial mocks) | ⛔ | planned via `@Around` aspects |
| auto-generated `@Mock` | ⛔ | needs a compiler codegen hook |
| `getAllValues()` captor list | ⛔ | use `argOf(callIndex, …)` per call |

## Ownership & toolchain notes

Hand-written mocks live within the current compiler's constraints (probed and
recorded alongside this work):

- Box primitives with `Int64.of(x)`; build the `Object[]` as a **local**
  (`Object[] a = {..}`), never inline as a call argument.
- Transfer owned values into the engine/rules with `#` (`engine.handle(name, #a)`,
  `thenReturn(#value)`); without it the value use-after-frees.
- Initialize fields in a **constructor**, not with an inline initializer.
- `Matcher` is a base class (not an interface), and its subclasses live in the
  same file — interface dispatch from a `#`-factory and cross-file base/subclass
  parse order both miscompile virtual dispatch otherwise.

See [`test-doubles.md`](test-doubles.md) for the simpler record-only
`CallLog`/`Verify` doubles and the `@Inject` override (`TestContext`).
