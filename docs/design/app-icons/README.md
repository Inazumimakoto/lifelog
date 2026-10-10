# lifelify blue icon artwork

The shipped app icon is now the [selected stem-and-dot design](selected-stem-dot/README.md), approved on 2026-10-10. The files and prompts below preserve an earlier exploration and are not the active app icon.

Earlier direction: Moment Mark (the third design in the Wantedly / Slack / Break The Web reference exploration).

## Files

- `lifelify-blue-white.png`: white background, charcoal mark, blue accent.
- `lifelify-blue-black.png`: black background, white mark, blue accent.

Both are opaque RGB PNG design masters, 1254 × 1254 pixels, generated with the built-in Image Gen tool. The two backgrounds are counterparts of the same selected design.

## Accent reference

`lifelog/Views/Today/TodayView.swift` uses `FloatingButton`, whose background is `Color.accentColor` in `lifelog/Views/Components/FloatingButton.swift`. The accent asset has no explicit RGB components.

A temporary UIKit / SwiftUI probe on the installed iOS 26.1 simulator resolved the light/default accent to sRGB **#0088FF** (0, 136, 255), and the dark accent to #0091FF (0, 145, 255). Both requested artworks use the light/default #0088FF as their shared generation target. The temporary simulator and probe were removed after measurement.

These are generated raster artworks: the sampled accent centers are (0, 133, 253) in the white version and (0, 133, 255) in the black version. Use the target #0088FF for a future exact-color production export. The original generated size is retained; an AppIcon export requires 1024 × 1024 pixels. These files are design deliverables, not asset-catalog entries.

## Final generation prompts

### White background

Use case: precise-object-edit. Asset: final selected lifelify app icon, WHITE BACKGROUND version. Edit the attached selected image, do not redesign. Preserve the exact silhouette, shape geometry, corner radii, proportions, angle, locations, and scale of BOTH the large bent black mark and the floating rounded-square accent. Preserve all whitespace and composition exactly. Change ONLY the colors and remove the extremely subtle color unevenness so the icon is a clean solid graphic. Background: pure solid white sRGB #FFFFFF. Main large bent mark: solid charcoal #232526, keeping its outline exactly. Small rounded square at upper right: change the current orange to exact solid sRGB #0088FF (RGB 0,136,255). This is the measured light-mode iOS 26.1 system accent blue used by the lifelify Today tab floating add button; the requested visual match matters. Uniform blue, no gradient, no cyan/teal cast. Full opaque square canvas, target 1024 x 1024 pixels. No transparency, no outer app mask or rounded tile, no external margin or frame. No text, caption, alternative designs, extra elements, shadows, texture, lighting or 3D. One icon only. A strict color edit of the supplied design, with contours and placement locked.

### Black background

Use case: precise-object-edit. Asset: final selected lifelify app icon, BLACK BACKGROUND counterpart to the supplied WHITE version. Edit the attached image ONLY by changing its background and main-mark colors. Preserve EXACTLY the existing silhouette, positions, sizes, angle, corner radii, proportions, whitespace and scale of the bent large mark AND the rounded-square BLUE accent. Do not invent or redraw a new symbol. Background becomes pure solid black #000000. The entire large bent charcoal mark becomes pure solid white #FFFFFF. The small rounded square at upper right MUST remain the same bright iOS accent BLUE sRGB #0088FF (RGB 0,136,255), with precisely its existing shape, size and position. This is the measured light/default system accent color used for the Today add button; it is intentionally shared across both background versions. Do not invert the blue. Uniform flat color fills, absolutely no sheen, gradient, grey shadow, texture, glow, lighting or 3D. Target 1024 x 1024 pixels, opaque square full-bleed icon. No transparency, outer rounded tile, frame, mockup, labels, words, added elements or multiple variants. Composition and geometry are locked to attached source. One strict recolored counterpart only.
