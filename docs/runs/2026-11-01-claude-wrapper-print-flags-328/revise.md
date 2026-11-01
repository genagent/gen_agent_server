I made both fixes. Nothing has been run; the checks are for you to run.

One conflict: my original instructions said to accept only 100,000 to 1,000,000 and not any positive integer. I followed the review, so values like `200` now reach the CLI, which checks the range itself.

**1. Autocompact now accepts any positive integer**
- `lib/claude_wrapper/query.ex`:
  - The type is now `:auto | pos_integer()`.
  - The check accepts any integer above 0 and emits it as a plain number.
  - The range limits are removed. The error message now says "expected :auto or a positive integer token count".
  - The setter doc says the CLI checks the range, and that 2.1.316's help gives 100k to 1M.
- `test/claude_wrapper/query_test.exs`:
  - The accept test now covers `:auto`, `1`, `200`, `100_000` and `2_000_000`.
  - The reject test now uses `0`, `-1`, `150_000.0`, `"200000"` and `:manual`; I dropped `99_999` and `1_000_001`.
- `README.md`: I updated the autocompact table row and the validation note to match. I counted these as the range-specific documentation the review mentioned.

**2. Credo struct-field limit**
- `.credo.exs`: `max_fields` goes from 56 to 70. The new comment says the Query struct is a flat mapping of CLI options, one field per flag, and has 64 fields after #328.

Please run:
```bash
mix format
mix compile --warnings-as-errors
mix credo --strict
mix test
```
`mix claude.contract` also needs a run. The maximal query still uses `autocompact: 200_000`, so its specimens shouldn't change.
