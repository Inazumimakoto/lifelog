# Repository Guidelines

## Project Structure & Module Organization
The repo root stays lean: `lifelog/` hosts the SwiftUI app and `docs/` stores requirements (`docs/requirements.md`) and UI guidelines (`docs/ui-guidelines.md`). Within `lifelog/`, features share a consistent layering—`Views` for SwiftUI screens, `ViewModels` for state, `Models` for data types, `Services` for persistence + integrations, and `Components` for reusable UI. Place shared assets under `Assets.xcassets` or `Resources`, and keep any schema or sample payloads close to the consuming service for easy diffing.

## Build, Test, and Development Commands
- `xcodebuild -project lifelog.xcodeproj -scheme lifelog -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` – CI-friendly release build; fails fast on missing assets or compile errors.
- `xcodebuild test -project lifelog.xcodeproj -scheme lifelog -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` – Runs the `lifelogTests` XCTest suite. Do NOT pass `CODE_SIGNING_ALLOWED=NO` here: the E2EE tests use the Keychain, which requires the (simulator-signed) app entitlements; unsigned test hosts fail with errSecMissingEntitlement (-34018). Use whatever iPhone simulator is installed locally.
- `xed lifelog.xcodeproj` – Opens the project in Xcode, which is still the fastest way to tweak previews, inspect Core Data models, and regenerate asset catalogs.

## Coding Style & Naming Conventions
Follow Swift’s API Design Guidelines: types in `UpperCamelCase`, methods/properties in `lowerCamelCase`, and prefer expressive parameter labels (`func loadTimeline(for date:)`). Files use 4-space indentation and keep one primary type per file. When adding a feature, mirror the existing folder pattern (e.g., `Views/Today`, `ViewModels/Today`) and annotate important sections with references back to `docs/requirements.md` or `docs/ui-guidelines.md` so future agents can trace intent. Prefer value types for models, `@MainActor` for view models touching UI state, and keep async work isolated inside services.
- Concurrency naming rule: this app has a domain model named `Task`, so async task creation must use `_Concurrency.Task { ... }` (and `_Concurrency.Task.sleep`) to avoid symbol collisions.

## Localization Guidelines
lifelify is a multilingual app. Any new user-facing feature must keep `ja`, `en`, `ko`, `zh-Hans`, and `zh-Hant` complete before release. Add UI strings, Widget copy, notifications, App Intents, permission text, AI prompts, sample/screenshot copy, paywall text, and App Store-facing drafts to the appropriate localization resources when the feature introduces or changes them. Do not translate or overwrite user-created content such as saved diary text, category names, tag names, memo text, or letter bodies. Do not add an in-app language switcher; follow the iOS app language and locale settings.

## Testing Guidelines
XCTest is the expected harness even though a `lifelogTests` target is not committed yet—create it via Xcode when adding tests. Name files after the type under test (`TodayViewModelTests`) and functions using the `testScenario_expectedOutcome` pattern. Favor deterministic fixtures by reusing the in-memory `AppDataStore` helpers and snapshotting critical timelines. Run `xcodebuild test ...` before every PR and document any intentionally skipped cases.

## Commit & Pull Request Guidelines
History shows short, sentence-case summaries (`Update README.md`, `Initial Commit`). Keep that style but add imperative detail: `Add Today timeline cards`, `Fix diary editor persistence`. Before pushing, always fetch/rebase or pull the remote branch first: a remote bot updates README line counts, so local branches commonly fall behind even after a fresh commit. Reference updated docs directly in the body (e.g., “syncs docs/requirements.md §Today”). PRs should include: a concise problem/solution blurb, screenshots or screen recordings for UI changes, links to related issues or requirement sections, and a checklist of tested commands. Flag migrations, new entitlements, or Stories in bold so reviewers can focus on risk.

## Release Workflow and App Store Update Notes
Treat requests such as 「タグつけてコミットプッシュして」 as release preparation: update the version, write App Store update notes, commit, create the version tag, and push the branch and that tag. An ordinary commit/push request does not trigger a version bump or tag. This workflow covers repository changes and update-note drafts; App Store upload/submission and GitHub Release creation require a separate request.

### Comparison Baseline

- Fetch the remote branch and tags, then record the previous `vX.Y.Z` version tag in the release branch's history before creating a new tag. Use that previous tag as the comparison baseline, regardless of whether that version was actually published on the App Store. App Store publication history must not silently replace this baseline.
- When resuming a release whose tag already exists, reuse the comparison tag recorded in that release's notes; do not treat the target release tag itself as the baseline.
- Review the cumulative code diff from that tag to the final release contents, including changes intended for the release that are not yet committed. Use commit history and docs as supporting context, rather than copying commit subjects into update notes. Resolve the final user-visible behavior, omitting reverted changes and features unavailable in the release configuration. If no previous version tag exists, clarify the baseline before drafting notes.

### Version, Commit, Tag, and Push

- Unless the user specifies a version, increment the minor version and reset the patch to zero when adding user-facing features (for example, `1.16.0` to `1.17.0`); use a patch increment for fixes/improvements without new features (for example, `1.16.0` to `1.16.1`). Increment the build number (`CURRENT_PROJECT_VERSION`) by one for a new release, keeping it monotonic across marketing versions. Retain an appropriate version/build already advanced for this release instead of incrementing them again on a retry.
- Before the release commit, update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `lifelog.xcodeproj/project.pbxproj`, keeping the main app and Widget extension consistent in both Debug and Release. Test-target versions are independent.
- Save the update notes described below as `docs/release-notes-vX.Y.Z.md` and include that file and the version changes in the release commit, together with the intended release changes.
- Run the build and XCTest commands documented above, using an installed iPhone simulator and preserving simulator signing for tests. Fix regressions and report actual results, including any checks that could not be completed and their reasons.
- Reconcile remote changes before tagging. Create an annotated tag named `vX.Y.Z` (matching `MARKETING_VERSION`, with a message such as `Release vX.Y.Z`) on the final synchronized release commit. Push the target branch and only that release tag; do not use `git push --tags`. Do not move or overwrite an existing tag. If the requested tag already exists, verify its commit and remote state before resuming any incomplete push.

### Update-Note Content and Output

- Consult the Japanese [lifelify App Store version history](https://apps.apple.com/jp/app/lifelify/id6755782099) for tone, headings, and level of detail. Treat it as a writing reference; the repository diff determines which changes belong to this update. If it cannot be accessed, use the saved release-note drafts as a fallback and disclose that limitation separately from the copyable update text.
- Write user-facing text suitable for App Store Connect's 「このバージョンの新機能」 field, with no emoji in any language. Follow the existing 「新機能／改善」 structure, giving each feature a concise name and a short explanation of what users can now do. Omit empty headings.
- Classify features relative to the comparison tag. If a feature was first introduced after that tag, combine all subsequent fixes, refinements, and UI adjustments to it into one 「新機能」 item describing its final capabilities. Do not list the same feature again under 「改善」 or describe bugs users never encountered. Improvements to features already present at the comparison tag belong under 「改善」. This rule takes precedence over older drafts that list a new feature and its development refinements separately.
- Include user-visible feature removals and changes to availability or usage conditions. Omit internal refactors, tests, development settings, and other implementation details without user impact. Avoid technical jargon, duplicate items, and unsupported filler such as 「その他の軽微な修正」. Keep claims grounded in implemented behavior.
- Save complete, equivalent update text for `ja`, `en`, `ko`, `zh-Hans`, and `zh-Hant` in `docs/release-notes-vX.Y.Z.md`, with separate copyable text blocks. Record the comparison tag and target version/build outside those blocks; keep validation details and operational caveats outside the user-facing text as well.
- In the final chat response, provide the Japanese update text in a copyable block and link to the file containing all five languages. Separately report the version/build, comparison tag, commit/tag/push results, and validation status. Do not report an App Store submission or distribution as completed unless that separate action was actually performed.
