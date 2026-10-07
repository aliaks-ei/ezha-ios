# EZHA

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

Native SwiftUI app with a shared Swift package, EZHAKit. The existing project targets iPhone and iPad.

## Users and Purpose

People logging meals and reviewing their nutrition. The meal logger should make entering food, inspecting an estimate, adjusting a portion, and logging the meal quick and easy to focus on.

## Capabilities and Constraints

The existing logger supports descriptions, meal photos, nutrition-label input, saved foods and meals, quantity edits, and optional estimate clarification. Nutrition calculations, draft persistence, consent, cancellation, stale-estimate protection, and offline Library logging must remain intact during UI changes.

AI nutrition is an estimate. Show unresolved preparation or portion information beside the affected food. Do not invent a preparation assumption from a calorie value.

## Confirmed Decisions

For the meal logger redesign on 7 October 2026, the user chose the first visual proposal in `docs/design/meal-logging/01-quiet-review.png` and authorized implementation. Logging remains available without answering an optional preparation question, with uncertainty visible.

## Product Principles

- Start with the information and actions useful to the current task.
- Separate entry from review inside the logger.
- Use one prominent primary action per state.
- Disclose nutrition details and less frequent actions when needed.
- Preserve the draft and make failed clarification reversible.

## Brand and Accessibility

Preserve the existing EZHA pink accent and native iOS controls. Use system text styles, semantic foreground colors, Dynamic Type, safe areas, and accessible control labels. Allow scrolling when content or text size requires it; fitting every possible case without scrolling is not a requirement.

## Evidence

The supplied screen, three visual proposals, and interaction specification are in `docs/design/meal-logging/`. Native implementation and simulator verification are scoped to this logger redesign; physical-device acceptance remains separate.
