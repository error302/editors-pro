# Editing workflow upgrade

The user requested working song/photo imports, professional filters/effects, editable text size/color, reliable saved projects, and cover thumbnails plus playable project previews. Monetisation planning follows the working core; billing is not part of this implementation.

## Implementation

1. Repair actual import/storage errors and reject unreadable or empty files without claiming success. Test with owned photo/audio/video fixtures.
2. Use the native filter catalog as authority, with real look recipes, intensity, bypass/reset, preserved manual adjustments, and coherent undo. Use one ordered pixel-processing path for preview and export.
3. Persist and expose text content, native-supported fonts, size, color and normalized position. Hydrate selection controls and invalidate paused-frame caches after mutations.
4. Render the project canvas and visible layers consistently. Use the same composed frames for editor preview and export.
5. Save native project state before publishing metadata; fail visibly on missing saved timelines. Generate an actual composed cover and a labelled short playable preview from an isolated saved-project engine, without replacing another active editor project. Cache by content and media fingerprints; publish completed artifacts atomically.
6. Verify focused regressions, native pixels/save-reopen, Android imports and an actual encoded output. Preserve existing projects and unrelated source changes.

## Evidence boundaries

UI tests, native pixel tests, Android picker/import tests, export decoding, package verification and device checks are recorded separately. Core media behavior is not established merely by building an APK. Monetisation proposals will be grounded in current platform rules and the features that have actually been verified.
