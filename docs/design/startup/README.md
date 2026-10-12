# Startup animation preview

The static launch logo and animated logo share transparent vector artwork with the approved stem/dot layout at the same 200pt size. The original AppIcon PNGs contain background color variation, so launch-only PDFs draw the stem and dot on a transparent page to avoid a visible rectangular edge against the launch background. AppIcon assets are unchanged.

The native launch resource is `StartupLaunchScreen.storyboard`, selected by `UILaunchStoryboardName`. Its full-screen `LaunchBackdrop` image draws an opaque white page in light appearance and an opaque black page in dark appearance, with all four edges constrained to the root view rather than the safe area. The root view also has a fixed black fallback. This bypasses named UIView background-color resolution for the native snapshot while the animated overlay continues to use `LaunchBackground` (#FFFFFF / #000000).

The user still observed a gray native screen followed by a black SwiftUI overlay after the storyboard rename. The user's existing built app was checked read-only: it includes the renamed storyboard, the transparent logo, and the zero-valued dark color. The opaque backdrop is a code-side correction for that mismatch; the precise runtime cause and the revised on-device rendering have not been visually verified. No app build, launch, or screenshot capture was performed for this revision.

Once the first screen is ready, the blue dot squashes against its lower edge for 70ms to anticipate the jump. It stretches upward for 25ms, rises to 28pt above its original position while slowing down for 45ms, and accelerates back down over 55ms. Landing compresses it for 25ms, then it recovers its round shape over 30ms. These stages add anticipation, easing, and squash/stretch without changing the static layout.

After landing, its interior becomes a transparent circular window onto the actual home or app unlock screen. Over 280ms, that window expands from the original dot center until it covers the entire screen. A thin blue rim and faint shadow distinguish the window from the surrounding splash, then fade as the window reaches the screen edges. The mask and rim use the same interpolated progress so their boundaries remain aligned. The splash background and logo remain opaque outside the window. The specified animation durations total 530ms; frame scheduling and completion handoffs can extend the observed duration. No loading delay or network wait is added.

Reduced Motion uses a 100ms fade instead of the hop and expanding window. Initial presentations and pending widget/letter destinations wait for startup completion and, when enabled, app unlock. Startup runs once per launch and does not replay when the app returns from the background.

`preview.mp4` records the previous 18pt jump using the original PNG launch artwork. It has not been regenerated for the 28pt jump and transparent vector assets; the user is checking the revised behavior locally.

Validation: the previous 18pt animation passed the Debug simulator build/run and recording checks in light and dark appearances. After the user reported a build failure, the current 28pt jump and transparent vector assets passed the Debug simulator build with no additional build-setting overrides. No app launch or screenshot capture was performed for this revision. Routing and startup presentation gating are unchanged.

The reported failure came from 34 app and 23 test `* 2.swift` copies being compiled alongside their byte-identical originals. The copies are preserved on disk and explicitly excluded from the corresponding target memberships in `project.pbxproj`, so ordinary Xcode builds no longer require a command-line exclusion.

See `docs/ui-guidelines.md` §起動時の表示 for the behavior specification.
