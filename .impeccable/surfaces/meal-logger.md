# Meal logger

Mode: Operate. Native iOS; iPhone and iPad.

Approved target: `docs/design/meal-logging/01-quiet-review.png`. The user accepted this direction and authorized implementation on 7 October 2026. Preserve the existing brand and platform conventions; this is a logger redesign, not an app-wide visual replacement.

The common review state shows the food, editable portion, unresolved detail, one calorie total, nutrition disclosure, Add food, and Log meal. Camera, Photos, Library and Scan label belong to entry. Quantity, optional clarification and detailed nutrition use native navigation destinations.

One-food review displays the total once in the content. Multi-food review displays per-food calories and a persistent meal total above the primary action. Use the existing bottom safe-area inset; allow larger text and longer meals to scroll.

Clarification is optional. Unknown preparation stays visible; known facts are not invented. Failed clarification can restore the previous estimate. Changing the source requires a fresh estimate; valid portion confirmation recalculates locally and supplies context for later corrections.

Save to Library is an optional post-log action. Logging should return to the previous screen without a mandatory success page.

Review against the approved composition while accommodating native navigation, safe areas, Dynamic Type and semantic theme colors. Check light and dark appearance, a compact iPhone, a larger iPhone and iPad. Simulator checks do not establish physical-device or VoiceOver acceptance.
