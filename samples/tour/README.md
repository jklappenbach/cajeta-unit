# cajeta-unit tour

A hands-on tour of [cajeta-unit](../../README.md), and a worked example of
**consuming the `dev.cajeta.unit` `.cja` library** from another project. Every
load-bearing capability has a demo class that extends `DemoClass` and overrides
`execute()`; `Tour.main` puts one instance of each into an `ArrayList<DemoClass>`
and walks it — so adding a demo means a new `.cajeta` file plus one
`demos.add(heap NewDemo());` line in `Tour.cajeta`. Same shape as the language
tour in the cajeta repo.

## Build & run

```
./run.sh        # build + execute   (CAJETA=/path/to/cajeta to override the compiler)
./build.sh      # build only         → build/tour
```

Because build-tool manifest classpath plumbing isn't shipped yet, `build.sh` does
two steps: it builds the `dev.cajeta.unit` library `.cja` (with `cajeta build`),
then compiles the tour against it via `--classpath`. `cajeta run` / `cajeta build`
delegate to these scripts (see `cajeta.json`).

## Layout

```
samples/tour/
├── README.md            ← you are here
├── cajeta.json          ← manifest (run/build/clean delegate to the scripts)
├── build.sh / run.sh    ← build the .cja, then compile/run the tour with --classpath
└── src/main/cajeta/tour/
    ├── Tour.cajeta              ← entry point — builds the demos[] array
    ├── DemoClass.cajeta         ← base class with virtual execute()
    ├── assertions/AssertionsDemo.cajeta
    ├── discovery/DiscoveryDemo.cajeta   ← @Test/@BeforeEach/@Disabled + Runner.runAll
    ├── report/ReportDemo.cajeta         ← the failure report, exit code 1
    ├── runner/RunnerDemo.cajeta         ← manual TestRunner registration (fallback API)
    ├── subject/SignupService.cajeta     ← the component under test for the mock demos
    ├── doubles/                 ← the hand-written doubles + their demo
    │   ├── DoublesDemo.cajeta
    │   ├── Mailer.cajeta            ← the collaborator to mock
    │   ├── MockMailer.cajeta        ← MockEngine-forwarding mock (the AoT recipe)
    │   └── LoggingMailer.cajeta     ← CallLog-embedding mock (the simple recipe)
    ├── matchers/MatchersDemo.cajeta
    ├── stubbing/StubbingDemo.cajeta
    ├── verify/VerifyDemo.cajeta
    ├── capture/CaptureDemo.cajeta
    ├── inorder/InOrderDemo.cajeta
    └── inject/InjectDemo.cajeta         ← TestContext + @Inject override (--profile=test)
```

## What each demo showcases

| Demo | unit package / class | shows |
|---|---|---|
| `AssertionsDemo` | `Assert` | fluent + classic assertions over a parsed order, `assertThrows` |
| `DiscoveryDemo` | `Runner`, `@Test`/`@BeforeEach`/`@AfterEach`/`@Disabled` | reflective discovery over a real `CartTest`, with the fresh-instance/lifecycle contract PROVEN by counters |
| `ReportDemo` | `TestRunner`, the subjects | a deliberately red test, its ✗ FAIL line, `summary() == 1`, `Assert.equals`, the full subject vocabulary |
| `RunnerDemo` | `TestRunner` | the manual-registration fallback API |
| `DoublesDemo` | `CallLog`, `Verify` | a CallLog-embedding mock driven THROUGH `SignupService`, plus `log.reset()` |
| `MatchersDemo` | `ArgMatchers`, `Matcher` | the predicate vocabulary (`any`/`eq`/`eqInt`/`isNull`/`notNull`/`argThat`) — real roles live in stubbing/verify |
| `StubbingDemo` | `Mock`, `Stubbing` | consecutive `thenReturn` + argument-routed `withArgs`, testing the service's behavior |
| `VerifyDemo` | `MockVerify` | count + argument-matched verification (`timesWith`/`countWith`/`neverWith`) of what the service did |
| `CaptureDemo` | `MockEngine`, `Invocation` | `argOf`/`lastArgOf`/`invocationOf`, `totalCalls`, `reset()` |
| `InOrderDemo` | `InOrder` | sequence verification incl. argument-matched `verifyWith` over `inviteTeam` |
| `InjectDemo` | `TestContext` | `bind`/`clear` overriding an `@Inject Clock` in the `--profile=test` build |

Every mock demo tests `subject/SignupService` THROUGH the mock — stubbing and
verification exist to test the component that uses the collaborator, not the
mock itself.

The `doubles/Mailer` + `MockMailer` pair is the canonical **hand-written mock
recipe** (subclass the real type, hold a `MockEngine`, forward each call) — see
[`docs/mockito-aot.md`](../../docs/mockito-aot.md).

## Notes on the `.cja` consumer boundary

The tour links `dev.cajeta.unit` as a separate `.cja`, which exercises a couple
of current toolchain edges (documented in `docs/mockito-aot.md`):

- A mock returns `engine.handle(...)` **inline**; binding it to an owned local
  would free the stub's value before the next call. A value-returning mock method
  must therefore be **stubbed before it is called**.
- `thenThrow`, out-of-order `InOrder` failures, and catching `AssertionFailure`
  throw *inside* the linked `.cja`; catching such a throw from the consumer
  currently crashes (cajeta INDEX: `cross-cja-exception-catch`). The gated
  demos in StubbingDemo/InOrderDemo carry the ready-to-enable code.
- Borrow-returning accessors (`MockEngine.invocationOf`, `handle`) must be
  read INLINE — binding the borrow to a local registers a drop and frees the
  engine's copy (see CaptureDemo's comment).
- `@Inject` / `TestContext` substitution needs a `--profile=test` build —
  `build.sh` passes it, and `inject/InjectDemo` covers `bind`/`clear`.

Coverage is enforced: `scripts/check-library-tour-coverage.sh src/main/cajeta
samples/tour scripts/tour-coverage-ignore.txt` requires every public type to be
exercised (the ignore file exempts the framework's own selftest fixtures and
the two cross-`.cja`-gated types, each with a stated reason). CI runs suite +
tour + gate via `scripts/ci-checks.sh`.
