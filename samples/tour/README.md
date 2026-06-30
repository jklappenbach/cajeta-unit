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
    ├── runner/RunnerDemo.cajeta
    ├── doubles/                 ← CallLog/Verify + the shared hand-written mock
    │   ├── DoublesDemo.cajeta
    │   ├── Mailer.cajeta            ← a collaborator to mock
    │   └── MockMailer.cajeta        ← the hand-written mock (the AoT recipe)
    ├── matchers/MatchersDemo.cajeta
    ├── stubbing/StubbingDemo.cajeta
    ├── verify/VerifyDemo.cajeta
    ├── capture/CaptureDemo.cajeta
    └── inorder/InOrderDemo.cajeta
```

## What each demo showcases

| Demo | unit package / class | shows |
|---|---|---|
| `AssertionsDemo` | `Assert` | `that(...).isEqualTo/startsWith/...`, `thatFloat`, `isTrue/isFalse`, `assertThrows` |
| `RunnerDemo` | `TestRunner` | register named tests, run them, print a pass/fail/skip report + exit code |
| `DoublesDemo` | `CallLog`, `Verify` | record calls by name; `received` / `receivedTimes` / `neverReceived` |
| `MatchersDemo` | `ArgMatchers`, `Matcher` | `any` / `eqInt` / `notNull` / `argThat` |
| `StubbingDemo` | `Mock`, `MockEngine` | `Mock.when(...).thenReturn(...)` incl. consecutive returns |
| `VerifyDemo` | `MockVerify` | `times` / `once` / `never` / `atLeast` / `atMost` + argument-matched `timesWith` |
| `CaptureDemo` | `MockEngine.argOf` / `lastArgOf` | read the arguments a mock received |
| `InOrderDemo` | `InOrder` | verify calls happened in sequence |

The `doubles/Mailer` + `MockMailer` pair is the canonical **hand-written mock
recipe** (subclass the real type, hold a `MockEngine`, forward each call) — see
[`docs/mockito-aot.md`](../../docs/mockito-aot.md).

## Notes on the `.cja` consumer boundary

The tour links `dev.cajeta.unit` as a separate `.cja`, which exercises a couple
of current toolchain edges (documented in `docs/mockito-aot.md`):

- A mock returns `engine.handle(...)` **inline**; binding it to an owned local
  would free the stub's value before the next call. A value-returning mock method
  must therefore be **stubbed before it is called**.
- `thenThrow` and out-of-order `InOrder` failures throw *inside* the linked
  `.cja`; catching such a throw from the consumer currently crashes, so those
  failure paths are exercised by the framework self-tests rather than here.
- `@Inject` / `TestContext` substitution needs a `--profile=test` build and is
  covered in [`docs/test-doubles.md`](../../docs/test-doubles.md), not the tour.
