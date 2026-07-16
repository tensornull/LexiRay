# Design QA — LexiRay Current Product Prototype

## Comparison Target

- Source visual truth: `build/ui-artifacts/candidate-a4d00eada15d-20260712-205225/contact-sheet.png`
- Source screens:
  - `build/ui-artifacts/candidate-a4d00eada15d-20260712-205225/dashboard.png`
  - `build/ui-artifacts/candidate-a4d00eada15d-20260712-205225/providers.png`
  - `build/ui-artifacts/candidate-a4d00eada15d-20260712-205225/settings-app-identity.png`
  - `build/ui-artifacts/candidate-a4d00eada15d-20260712-205225/language-english-to-simplified-chinese.png`
- Implementation screenshots:
  - `build/prototype-qa/dashboard-final.png`
  - `build/prototype-qa/providers-final.png`
  - `build/prototype-qa/settings-final.png`
  - `build/prototype-qa/panel-final.png`
- Viewport: `1271 × 672` for main-window comparisons; `660px` panel width for the focused floating-panel comparison.
- State: dark appearance, key main window, System Dictionary enabled, dashboard idle, Providers selected, Settings scrolled to Hotkeys/Floating Panel/History/App Identity, and a focused translated floating panel.

## Full-view Comparison Evidence

- Dashboard: `build/prototype-qa/dashboard-comparison.png`
- Providers: `build/prototype-qa/providers-comparison.png`
- Settings: `build/prototype-qa/settings-comparison.png`

The paired images place source on the left and prototype on the right at the same normalized viewport. Window bounds, titlebar height, sidebar width, content padding, card grid, section order, card radii, and dark semantic surfaces are aligned.

## Focused Comparison Evidence

- Floating panel: `build/prototype-qa/panel-comparison.png`
- App Identity region: `build/prototype-qa/settings-identity-comparison.png`

Focused comparison was needed because the panel toolbar, language controls, result actions, and identity metadata are too small to judge reliably in the main-window full views.

## Required Fidelity Surfaces

- Fonts and typography: uses the macOS system stack with matching semibold title/headline hierarchy, compact captions, and native-density body copy. No actionable wrapping or truncation remains at the tested viewports.
- Spacing and layout rhythm: main window, `224px` sidebar, `52px` titlebar, page margins, `20px` section rhythm, card padding, `8px`/`14px` radii, and `660px` panel width match the source structure. Content-driven panel height remains intentionally shorter when mock result copy is shorter.
- Colors and visual tokens: semantic dark window/sidebar/surface/input colors, system blue selection/accent, green success, orange warning, disabled opacity, borders, and panel elevation visually map to the source.
- Image quality and asset fidelity: the supplied LexiRay raster app icon and existing OpenAI/Anthropic/Gemini provider SVG assets are reused without redrawing. UI icons use one consistent Phosphor family as the closest web-safe match to SF Symbols; no handcrafted SVG, placeholder image, or CSS illustration replaces product imagery.
- Copy and content: app-specific labels, hotkeys, language defaults, provider names, settings sections, history title, and panel controls match current source behavior. Provider results and app path use isolated prototype mock values by design.
- States and interactions: Dashboard manual/selection/OCR entry points, loading/success, Provider add/configure/toggle/remove, Settings controls, Copy/Speak, Pin/Expand/Close, language swap, clear/retranslate, and keyboard history restore were exercised.
- Accessibility and resilience: controls expose semantic roles and labels, keyboard focus is visible, images have alt text, contrast remains legible, reduced motion is respected, and `900 × 650` testing showed no page or panel overflow.

## Comparison History

### Iteration 1 — blocked

- [P2] Selected sidebar rows showed an extra browser focus ring not present in native macOS selection.
- [P2] Provider/settings switches were visibly narrower than the SwiftUI switches.
- [P2] The floating-panel toolbar clipped `Retranslate` when the source badge was `Accessibility`.
- [P2] The panel source editor was compared unfocused while the source screenshot showed the focused blue border.

Fixes made:

- Replaced the external focus ring with a subtle inset selected-row focus treatment.
- Matched the native switch dimensions and thumb travel.
- Tightened panel control gaps, language control widths, badge padding, and button padding while retaining full labels.
- Recaptured the panel with the source editor focused.

Post-fix evidence:

- `build/prototype-qa/providers-comparison.png`
- `build/prototype-qa/settings-comparison.png`
- `build/prototype-qa/panel-comparison.png`
- `build/prototype-qa/panel-compact-900-final.png`

### Iteration 2 — passed

No actionable P0/P1/P2 visual or interaction mismatch remains in the covered current-product paths. Browser console warnings/errors: none.

## Follow-up Polish

- [P3] Browser overlay-scrollbar timing differs from the always-visible acceptance scrollbar.
- [P3] Phosphor icons are optically close but not identical to Apple SF Symbols.
- [P3] Acceptance fixture result length and prototype mock result length produce different content-driven panel heights.

## Implementation Checklist

- [x] Main navigation and window chrome match the current app.
- [x] Dashboard, Providers, Settings, floating-panel, and embedded History paths work.
- [x] Current source assets are reused.
- [x] Same-viewport full-view and focused comparisons completed.
- [x] P0/P1/P2 findings fixed and recaptured.
- [x] Browser console checked.

final result: passed
