# Chair Ledger

Offline appointment book for solo stylists: plan services and buffers, prevent double-booking, and export a daily schedule on phone, tablet, and Windows without accounts.

## Why and who

Solo salon chairs and barbers often need a simple private calendar without payment processing, hosted booking pages, subscriptions, or client data uploaded elsewhere. Chair Ledger is an **organizer-operated** schedule; clients do not book remotely.

## Intended workflow

1. Define services with durations and cleanup buffers; add working hours and breaks.
2. Enter client display name (optional), service, start time, and private note. Show conflict before saving; resolve explicitly instead of silently moving appointments.
3. Review day/week timeline; mark completed/cancelled and copy or print a redacted day sheet.
4. Export JSON backup or CSV schedule; restore only after preview and validation.

## MVP and limits

MVP: local services, hours, appointments, conflict detection, adaptive day/week views, local backup/export, accessibility. No online booking, reminders, payment, contact sync, SMS, cloud, staff roster, medical information, or automated scheduling. App never requires network permission or an account. Client names are optional and may be pseudonyms. Local device data is not encrypted by the app; use OS storage protection, and safeguard exports. No health/medical use.

## Platforms and status

Flutter stable, one codebase; Windows desktop first, Android and iOS on phones and tablets. Strategy A: Cupertino on iOS, Material 3 on Android, Fluent on Windows; touch plus keyboard/mouse, resizing, screen readers, high contrast, scalable text. Bundle/application identifier: `com.infinityball.chairledger` (Windows/MSIX identity may need platform-safe normalization). `AppStore/description.txt` is draft copy; `AppStore/icon.png` is generated art, not yet wired. The Flutter app now includes transactional local SQLite service, hours, and appointment entry, native Cupertino/Material 3/Fluent controls, conflict-preserving forms, and widget tests. Day/week agenda, exports, and icon wiring remain future issues.

Install pinned Flutter 3.47.2 / Dart 3.13.2 from `toolchain.json`, then run `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test`, and `flutter build windows --release` on Windows. CI builds Windows release and Android debug APK in a pinned Linux Docker image. Linux ARM64 runs analysis/tests through the matching-Dart Flutter SDK; Windows executables require Windows CI. No release is claimed yet.

## Distribution

Windows portable zip on `v*` GitHub release through `.github/workflows/release.yml` on `windows-latest`, with manual dispatch. Android/iOS store submission later, not MVP. Repository Actions secret names for future iOS delivery: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`.

## Manual setup required

App Store Connect bundle identifier `com.infinityball.chairledger` could not be registered: `FAILED bundleId lookup rejected: FORBIDDEN_ERROR.PLA_NOT_ACCEPTED`. Account owner must accept current Apple Program License Agreement; registration must be retried before TestFlight. Secrets are configured but do not bypass this gate.
