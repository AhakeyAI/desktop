# AhaKey Logi Web Shell Design Notes

This prototype treats Logi Options+ visual evidence as the primary reference. Existing AhaKey design specs are useful product notes, but they are not a visual authority for this Logi-inspired shell.

## Reference Weight

1. Logi screenshots and observed UI behavior.
2. Logi React/CSS tokens and component structure.
3. Real AhaKey product constraints: BLE, control ownership, sync, Agent, Voice.
4. Existing AhaKey AI-generated specs and SwiftUI drafts.
5. New interpretive design judgment.

If a lower-priority source conflicts with a Logi screenshot, the screenshot wins.

## Long-Term Rule

Home, onboarding, device overview, Settings, preferences, and form screens must not use heavy borders, stacked cards, or panel outlines to create hierarchy. Those patterns read as AI-generated admin UI and are lower quality than the Logi reference.

Use whitespace, object scale, icon rhythm, subtle dividers, typography, and the device object itself. Borders are allowed only when they are structurally necessary or visible in the reference.

Settings may use a small number of system-level structure lines: the window edge, the sidebar/content split, selected navigation tint, and native control outlines. Do not nest section borders, row borders, and theme-card borders inside each other. Prefer quiet grouped rows, light surface tint, spacing, and a clear selected check.

Studio and device configuration pages follow the same rule. Do not build hierarchy from "topbar frame + nav frame + canvas card + inspector card + inner cards." Allowed structure lines are the topbar action dividers, a small number of main-region separators, selected-state tint, and native control boundaries. Avoid independently framed nav icons, framed summary cards, row-level inspector cards, and borders nested inside borders.

Studio must not expose internal information architecture, editing logic, or tutorial-style operation guidance as user-facing copy. Phrases that explain how the app is structured or how the user should think about the workflow belong in specs, onboarding, or dedicated help modes, not in the default UI.

Studio's left rail is only for first-level navigation. Do not use it for secondary key directories, explanatory text, or training copy. When the right-side inspector is open on desktop, the rail should collapse to icons so the device canvas and inspector keep visual priority.

User-facing copy must not rely on middle-dot punctuation to create hierarchy or explanation. Use line breaks, label/value pairs, spacing, or lighter subtitles instead.

Platform brand names are context, not body copy. The currently selected workspace may be expressed in the top-right platform switcher, but those brand labels should not be repeated through page headings, inspector titles, helper text, or mock content.

## AhaKey Spec Caution

The older AhaKey surface/panel/border system is a constraint archive, not a style guide for this prototype. Do not automatically carry its card or panel language into the Logi-style Home experience.
