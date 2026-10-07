# EZHA meal logging redesign

Design proposal, 7 October 2026. No application code changed.

Recommendation: use concept 1, with separate entry and review states inside the existing logger. Users should be able to inspect the food, adjust it, and log it without navigating past unrelated controls. The user confirmed that clarification should be optional, with assumptions visible.

## Evidence and findings

The supplied [current screen](current-screen.jpeg) shows one populated logger state. This is a screenshot review supported by reading `LoggerView.swift` and the relevant review methods in `LoggerModel.swift`; it is not a live audit of the complete flow.

1. **Enter the meal — competes with review.** The completed description and three prominent pink attachment buttons remain visible above the result. They draw attention back to input after estimation has finished.
2. **Clarify the estimate — too much space and effort.** A separate question section combines preparation and added fat, a text field, Update estimate, and Keep estimate. It sits before the food being reviewed. Answering a small question requires composing text and managing several actions.
3. **Review and log — understandable, but crowded.** The food repeats the description; macros, deletion, quantity controls, and estimate details share one small area. More totals, Library saving, and draft actions follow below. The existing bottom action is already pinned with `safeAreaInset`; retain that behavior. The problem is competing content, not the absence of a persistent action.

Secondary labels and question actions look faint in the screenshot. Actual contrast, hit areas, focus order, and disabled states require testing in the running app; no accessibility compliance claim follows from this image.

## Proposed interaction

### Entry

Use the title “Add meal”, one description field with “What did you eat?”, and quiet Camera, Photos, and Library shortcuts. Put Scan label within a clearly labeled attachment menu. Retain fast access to these existing capabilities without three large colored tiles. Show a compact photo preview only after attachment.

The single primary action is “Estimate nutrition” for text or photo input. Library selection retains its existing quantity review path and does not require an AI estimate. Do not display empty review sections or a Save to Library toggle.

After estimation, dismiss the keyboard and transition to review within the same logger. Preserve the draft and its input when switching states.

### Review — recommended concept 1

Show the food name, editable portion, preparation uncertainty, estimated total, and one prominent “Log meal” button. Hide the composer and attachment shortcuts until the user chooses Add food or edits the source description from the food editor.

- “100 g” opens a focused portion editor with a decimal keyboard, a unit label, and Done. Valid portion changes recalculate nutrition immediately where the existing quantity math supports it.
- “Preparation not specified · Adjust” opens a focused editor for preparation and added fat. Keep it beside the food it affects. Show a real assumption when available; never infer “cooked” or “no added oil” from the calorie number alone.
- “Nutrition & estimate details” discloses protein, carbs, fat, and existing estimate notes. Use plain names rather than P/C/F abbreviations. Preserve any manual nutrition-label overrides inside this detailed editor.
- “Add food” returns to entry with existing items retained and exposes all input methods. It must not replace or duplicate the existing meal.
- “Log meal” saves the currently reviewed estimate without requiring preparation clarification. Remove the separate Keep estimate action. Show the calorie total once in the common single-food state.

For multiple foods, use a compact list of name, portion, per-item calories, and any relevant assumption. Show the meal total in the bottom action area so it remains available during scrolling. Item editing opens detail; removal belongs in Edit and may also have a swipe shortcut. Do not make a gesture the only way to remove an item.

Move Save to Library to an optional action after successful logging, or to meal details. It should not delay logging. Keep draft clearing in secondary actions with the existing confirmation behavior.

### Preparation editor

Use one focused destination inside the logger navigation stack, rather than stacking another modal over it. Show the affected food, portion, preparation choices, and an added-fat field when relevant. Do not select an unknown value automatically. Retain free-text detail entry for questions that cannot be represented reliably by structured choices.

For preparation changes that need AI, use one “Update estimate” action. Show progress and prevent saving a partially recalculated result. On failure, retain the draft and offer retry or an explicit return to the previous estimate. Returning without changes restores the review state immediately.

“Raw” and “Cooked” in concept 3 are alternatives for the specific example question, not a replacement for every possible AI review question. Selecting one would recalculate the estimate; the image intentionally shows neither selected.

## Three visual alternatives

| Concept | Main difference | Tradeoff |
| --- | --- | --- |
| [1 — Quiet review](01-quiet-review.png) | Flat surface, food first, one clear estimated total, focused editors | Portion adjustment requires opening the editor |
| [2 — Compact review](02-compact-review.png) | Native grouped rows with quantity controls directly visible | More controls remain on the review screen |
| [3 — Optional check](03-optional-check.png) | One short preparation question is visible beside the estimate | Clarification still competes with the main logging task |

All three preserve the pink identity, label nutrition as estimated, disclose uncertainty, and keep logging available. Generated mockups illustrate hierarchy; they are not Simulator captures or exact component specifications. In implementation, use native system controls and actual semantic theme colors, not baked image effects.

## iOS design basis

Apple recommends progressive disclosure to reduce the amount of content and choices initially displayed. That supports moving detailed nutrition and less frequent actions into focused destinations. [Apple Layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout).

Apple recommends a prominent style for the most likely action and keeping prominent buttons limited. Reserve the strongest pink treatment for Estimate nutrition in entry and Log meal in review. Use at least 44 × 44 pt touch regions with spacing around adjacent controls. [Apple Buttons guidance](https://developer.apple.com/design/human-interface-guidelines/buttons).

Use system text styles, Dynamic Type, semantic foreground/background colors, native SF Symbols, and labeled controls. Support dark appearance, increased contrast, VoiceOver, and Reduce Motion. [Apple Accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility).

Retain a visible cancellation control and guard dismissal when it would discard work. Keep the task inside one logger sheet with internal navigation for editing. [Apple Sheets guidance](https://developer.apple.com/design/human-interface-guidelines/sheets).

## Acceptance criteria for a later implementation

- At default text size on a representative iPhone, the one-food review shows the food, portion, uncertainty, estimate, and Log meal without scrolling. Larger text and longer meals may scroll naturally.
- The bottom action respects safe areas and the keyboard. No content becomes unreachable beneath it.
- An untouched, valid review requires one tap to log, including when preparation is unknown.
- Quantity, preparation, additional food, and source-description edits preserve the draft and keep totals current. Source changes retain the existing stale-estimate protection.
- Estimation, recalculation, saving, invalid quantities, empty results, and failed requests have clear states. Disable logging during active saving/recalculation and prevent duplicate submissions.
- Library meals remain usable through their existing offline path. Do not promise offline AI estimation.
- Verify on a compact iPhone and a larger iPhone, including dark appearance, accessibility text sizes, VoiceOver, and keyboard handling. Physical-device interaction remains a separate check.

The implementation decision is still open. These artifacts do not establish gesture behavior, contrast compliance, Dynamic Type layout, or successful backend logging.
