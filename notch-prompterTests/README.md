# Tests

Run everything with `swift test`.

## Characterisation and approval tests

`PrompterViewModelCharacterisationTests` and `CallAssistSessionCharacterisationTests`
record what the app does today, so a refactor that changes behaviour fails. They are
not a statement that today's behaviour is right. A test named `currently…` pins
something that may be a bug: change that behaviour in its own commit and update the
test in the same commit.

Approval tests write the result as text (or an image) and compare it with an approved
file under `__Snapshots__/<suite>/`. The approved files are committed and reviewed like
code.

- A difference fails the test and prints a diff. If the change is intended, delete the
  approved file (or run with `SNAPSHOT_TESTING_RECORD=failed swift test`), run again,
  read the new file, and commit it with the change that caused it.
- A missing approved file is recorded on the first run and that run fails. Read the new
  file before committing it: approving it is the review.
- `SNAPSHOT_TESTING_RECORD=never swift test` never writes files, for CI.

The prompter images depend on macOS's font rendering, so they may need re-recording
after a macOS update. They compare at 98 % precision to absorb small anti-aliasing
differences.

## What the fakes replace

Everything that touches the outside world is a service registered in the dependency
container (`swift-dependencies`, one file per service in `notch-prompter/Services`).
Tests override the services they use with `withDependencies`; a test that reaches a
service it did not override fails with "has no test implementation", so nothing real is
touched by accident.

The Call Assist tests use `useFakes` in `CallAssistSessionCharacterisationTests`: a
scripted `FakeListener` for the transcribers, a `FakeProvider` that answers, stalls or
fails on cue, a `FakeScreen`, a fake Keychain, and a temporary SQLite file for history.
The prompter tests use a throwaway UserDefaults suite and `FrameClock.stopped`, then call
`tick(current:)` with their own times. `AppCoordinatorTests` runs the real models with
these fakes and a `FakePanel` standing in for the prompter window.
