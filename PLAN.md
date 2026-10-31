# Chair Ledger plan

## Scope and architecture

Flutter stable one-codebase app, platform folders `windows/`, `android/`, `ios/` enabled by issue #1. Pure Dart interval/domain logic; local transactional SQLite store; small adaptive-widget layer shared by day/week/appointment screens. No backend. Windows primary CI/release; Android debug CI; iOS simulator compile on macOS when available. Identifier `com.infinityball.chairledger` on Android and iOS; Windows/MSIX platform-safe transformation documented at packaging. iPad and Android tablets enabled.

## UX choice: A, platform-native adaptive

iOS Cupertino navigation/action sheets, Android Material 3 navigation/back, Windows Fluent title bar/command surface/context menus. AdaptiveScaffold/AdaptiveButton/AdaptiveDialog separate visual shell from shared workflow; no Material look on iOS, Cupertino look on Android, or phone layout on Windows. Phone single pane; tablet/desktop split agenda and detail. Keyboard shortcuts, hover, full keyboard navigation, readable text scaling, contrast and screen readers; native date/time/file pickers when supported. Golden/widget tests on TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.windows at 390x844, 820x1180, 1440x900.

## Data and safety

Service(id, name, durationMinutes, bufferMinutes); WorkingWindow(day, open, close); Appointment(id, startLocal, durationSnapshot, bufferSnapshot, serviceId, optional clientLabel, optional note, status). Use half-open intervals; enforce same-day local wall-clock conflicts and working windows; DST ambiguous/skipped times must be flagged instead of guessed. Snapshot durations preserve historic intent after service edits. JSON versioned atomic import with preview; CSV export formula escaping and optional client-name redaction. Local storage, no account, no network, no contacts/calendar/SMS permissions. Exports are sensitive and user-controlled. No medical claims.

## Milestones

1. Pinned Flutter stable skeleton, `windows/`, `android/`, `ios/`, CI and smoke tests.
2. Domain interval and conflict tests; transactional persistence and migrations.
3. Service/hours editor and appointment workflow.
4. Platform-authentic day/week views, keyboard/touch/accessibility tests.
5. Redacted schedule export, versioned backup/restore and privacy checks.
6. `AppStore/icon.png` already generated via OpenAI Images; inspect and wire to Windows `.ico`, Android launcher, iOS catalog; keep `AppStore/description.txt` accurate.
7. `.github/workflows/release.yml`: `v*` tags/manual dispatch on `windows-latest`, zipped portable Windows binary attached to GitHub release. Later opt-in TestFlight/Play submission using `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` (names only). Apple PLA acceptance and bundle registration required first.

## Testing and toolchain

Pure-Dart unit cases: adjacent intervals, buffers, cross-midnight rejection, status changes, restore rollback, malformed JSON, CSV formula injection. Widget/golden checks per TargetPlatform and size. `flutter test` and `flutter build windows --release` on Windows; Android debug build in pinned Docker Linux image. MacOS iOS compile evidence later. Flutter scaffold and service/slot/SQLite/entry-flow tests exist; Windows, Android, and iOS builds must pass CI/native gates before release.

## Risks and non-goals

Offline multi-device data does not sync; export/restore is manual. Local-time DST ambiguity and export privacy need explicit UX. No online booking, staff coordination, payments, SMS, contacts/calendar sync, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or native Swift/Xcode-only app. No placeholder icon or fake CI evidence.
