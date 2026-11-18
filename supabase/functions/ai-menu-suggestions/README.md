# Menu suggestions

iOS only. The app sends 1–4 menu photos as base64 JPEGs with the remaining
macros. The model picks 5 dishes printed on the menu, estimates a restaurant
serving of each, and adds an optional tip for ordering it lighter. The app works
out what each dish leaves for the day, so the function adds no "exceeds" note.

Photos are sent inline and never stored or logged. The user is always verified,
because vision requests are costly.

## Models

- `gpt-6-luna` with low reasoning.
- One retry on `gpt-6.1-sol` when the menu is unreadable or no valid dish came
  back. Photos that are not a menu are not retried.

| Setting                      | Default       |
| ---------------------------- | ------------- |
| `OPENAI_MENU_MODEL`          | `gpt-6-luna`  |
| `OPENAI_MENU_FALLBACK_MODEL` | `gpt-6.1-sol` |
| `MENU_TIMEOUT_MS`            | 50000         |
| `MENU_MAX_OUTPUT_TOKENS`     | 3000          |

It reuses `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `SUPABASE_URL`, and
`SUPABASE_ANON_KEY`.
