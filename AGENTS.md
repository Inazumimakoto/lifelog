# Repository Guidelines

## Project Structure & Module Organization
The repo root stays lean: `lifelog/` hosts the SwiftUI app and `docs/` stores requirements (`docs/requirements.md`) and UI guidelines (`docs/ui-guidelines.md`). Within `lifelog/`, features share a consistent layering—`Views` for SwiftUI screens, `ViewModels` for state, `Models` for data types, `Services` for persistence + integrations, and `Components` for reusable UI. Place shared assets under `Assets.xcassets` or `Resources`, and keep any schema or sample payloads close to the consuming service for easy diffing.

## Build, Test, and Development Commands
- `xcodebuild -project lifelog.xcodeproj -scheme lifelog -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` – CI-friendly release build; fails fast on missing assets or compile errors.
- `xcodebuild test -project lifelog.xcodeproj -scheme lifelog -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO` – Runs XCTest suites; prefer the same simulator name locally to match snapshots.
- `xed lifelog.xcodeproj` – Opens the project in Xcode, which is still the fastest way to tweak previews, inspect Core Data models, and regenerate asset catalogs.

## Coding Style & Naming Conventions
Follow Swift’s API Design Guidelines: types in `UpperCamelCase`, methods/properties in `lowerCamelCase`, and prefer expressive parameter labels (`func loadTimeline(for date:)`). Files use 4-space indentation and keep one primary type per file. When adding a feature, mirror the existing folder pattern (e.g., `Views/Today`, `ViewModels/Today`) and annotate important sections with references back to `docs/requirements.md` or `docs/ui-guidelines.md` so future agents can trace intent. Prefer value types for models, `@MainActor` for view models touching UI state, and keep async work isolated inside services.
- Concurrency naming rule: this app has a domain model named `Task`, so async task creation must use `_Concurrency.Task { ... }` (and `_Concurrency.Task.sleep`) to avoid symbol collisions.

## Testing Guidelines
XCTest is the expected harness even though a `lifelogTests` target is not committed yet—create it via Xcode when adding tests. Name files after the type under test (`TodayViewModelTests`) and functions using the `testScenario_expectedOutcome` pattern. Favor deterministic fixtures by reusing the in-memory `AppDataStore` helpers and snapshotting critical timelines. Run `xcodebuild test ...` before every PR and document any intentionally skipped cases.

## Commit & Pull Request Guidelines
History shows short, sentence-case summaries (`Update README.md`, `Initial Commit`). Keep that style but add imperative detail: `Add Today timeline cards`, `Fix diary editor persistence`. Reference updated docs directly in the body (e.g., “syncs docs/requirements.md §Today”). PRs should include: a concise problem/solution blurb, screenshots or screen recordings for UI changes, links to related issues or requirement sections, and a checklist of tested commands. Flag migrations, new entitlements, or Stories in bold so reviewers can focus on risk.
