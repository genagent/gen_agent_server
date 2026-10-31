# gen_agent_server control extension

Optional, caller-started controller and evidence ledger for [gen_agent_server](../../README.md). A library: it adds no operations or supervised processes; callers start `GenAgentServer.Control.Ledger` and `GenAgentServer.Control.Controller` themselves. Add `{:gen_agent_server_control, path: "path/to/gen_agent_server/extensions/control"}` to a host. Examples run from this directory with `mix run examples/<name>.exs`; the design notes are in [docs/control-patterns.md](docs/control-patterns.md).

## Optional controller (explicit #40 stages)

`GenAgentServer.Control.Controller` adds caller-started independent work and explicit review stages
above Invocations and Ledger. Start a configured instance with `create_instance/2`,
open a fresh ledger run, then start one controller for that run:

```elixir
alias GenAgentServer.Control.Controller
{:ok, controller} = Controller.start_link(instance: "review", ledger: ledger, run: run)
{:ok, attempt} = Controller.submit(controller, "implementation", "smoke", spec)
{:ok, snapshot} = Controller.status(controller)
{:ok, snapshot} = Controller.result(controller) # same repeatable bounded projection
Controller.cancel(controller, attempt) # {:ok, :requested}; inspect later acknowledgement
```

`spec` is the exact Ledger attempt specification shown below, with `kind: :work`
or `kind: :review` and an inline `prompt`. A review must name a caller-recorded
Ledger revision in `subject_revision_id` belonging to the same task. Reviews allow
Echo or an explicitly configured `codex_sandbox: "read_only"` /
`claude_permission_mode: "read_only"` route. Missing settings (even if the provider
default is read-only), unknown permissions, plan and editing modes are rejected.
The sanitized description preserves explicit access provenance without changing
provider defaults. Task checkout must match both the manifest and sanitized
route cwd exactly; Echo describes cwd as nil because it has no filesystem
backend, so its checkout remains only the manifest attestation. Provider and
every supplied requested setting must match the route. Settings are assertions about configuration, not invocation overrides.
Unknown actual model stays nil. Each task/stage accepts one submission: an exact
route/spec repeat returns its existing attempt ID, changed input (including subject)
conflicts. Choose a distinct stage for another review or follow-up. Historical
subjects are allowed; Ledger current-revision gates remain authoritative. There
is no queue or automatic retry. The caller must use one controller per fresh run;
concurrent controllers for a run are outside this increment's contract.

The controller reserves a terminal ledger slot and full record byte ceiling before
invoking. It monitors and calls the original Invocations PID and ledger PID;
Invocations PID loss permanently fences new work and later completion delivery.
Only `:admitting` and `:pending` execution become `:unobserved`; observed completed,
failed, cancelled and admission-failed execution survive loss even when terminal
evidence could not fit. It never attaches to a replacement instance with the same name.
Ledger loss or a failed ledger call stops new work, while same-lifetime completion
can still update bounded local execution, text byte count and digest. Its terminal
stays unset with an explicit evidence error. Snapshots distinguish `owner_lost`
from `ledger_unavailable`; the legacy `unavailable` summary retains only the first
reason. Ledger call exits return `:ledger_unavailable`; a timeout records
`:ledger_call_uncertain`, not proof of death. Only the ledger monitor establishes
`:ledger_lost`. Neither condition automatically retries the uncertain ledger write.
Invocations remains the sole Ensemble inbox consumer. Completion notifications
are ingested immediately, preserving repeat reads after raw result eviction.
The opt-in raw `recipient_ref` reference is echoed in completion metadata and
stripped before Ensemble dispatch; it correlates admission/completion races.

`limits:` may lower hard ceilings: `unfinished: 8`, `retained: 64`, `helpers: 8`,
`helper_timeout_ms: 5_000`, `text_bytes: 4_096`. Monitored owned helpers keep
controller reads responsive during raw admission/cancellation. Helper expiry or
crash after starting admission is uncertainty, never a worker terminal or retry.
Uncertain attempts and evidence failures still consume unfinished capacity.
After uncertain admission, the invocation ID may remain unknown. Controller cancel
then returns `:not_admitted` until a completion notification supplies the ID; this
means the controller cannot target the invocation, not that cancellation is
unsupported or execution never started. The caller may inspect raw Invocations
outside the controller. No replay or attachment is attempted.
Ledger unavailability also refuses new controller cancellation requests with
`:ledger_unavailable`. A caller with a known invocation ID can explicitly cancel
through the raw API; this does not restore ledger evidence.
Cancellation is requested once; its acknowledgement is stored separately in
`cancel`, and authoritative terminal evidence comes only from completion.
A timeout never cancels work and cancellation never proves provider cleanup.

Each admitted attempt snapshot adds
`timing: %{admitted_at_unix_ms: integer, terminal_observed_after_ms: nil | nonnegative_integer}`.
The admission timestamp is wall-clock Unix milliseconds captured after successful
ledger admission. The duration uses a private monotonic clock start and measures
controller admission to its first authoritative completed, failed, cancelled or
definite admission-failed observation, in milliseconds. Reads, duplicate submits
and late events do not reset timing. Evidence validation or persistence failure
retains an observed duration. Uncertainty, unobserved/fenced execution and cancel
acknowledgement alone leave the duration nil; a later authoritative observation
from the original owner can fill it while that lifetime remains unfenced.
Malformed or uncorrelatable completion notifications do not establish a terminal
observation; an invalid accepted notification can leave the attempt uncertain
without a duration.
This is process-local observation timing, not provider CPU duration or global
cost. It has no restart durability, is absent from Ledger evidence, and exposes
no private monotonic timestamp.

Snapshots retain `kind` and `subject_revision_id` (nil for work), bounded terminal
text, invocation/session IDs and failure text,
without response events or arbitrary metadata. Nil and empty text remain distinct.
Oversized/invalid text or terminal metadata that cannot fit the ledger reservation
leaves the ledger attempt unfinished with an explicit `evidence_error`; available
text byte count and SHA-256 remain in the controller snapshot. No excerpt is
represented as full output. This may permanently block gates until the caller
supplies appropriate evidence directly to the ledger. No controller recovery or
resynchronization is provided. Bounds cover retained state, not transient raw
messages, provider execution or total VM memory.

The controller child is temporary. It kills its own helpers on shutdown and
never stops the shared instance or ledger. Data is process-lifetime only. Existing
revision/review/check/acceptance gates remain caller-driven through Ledger.
After completed work, the caller uses `Ledger.record_revision/3` to record the
actual artifact fingerprint and producing attempt. Submit a review with that
revision as its subject, then separately call `Ledger.record_review/3` with the
caller-decided verdict, `record_verification/3` with actual command evidence, and
`record_acceptance/3` with the host decision. Review output, including `APPROVE`,
creates none of these records and cannot bypass a failed mechanical check.

Run `mix run examples/control_controller_echo.exs` for two independent Echo tasks,
explicit caller revision/review/check/acceptance records, deduplicated submit and
repeatable evidence after raw eviction. These are synthetic example decisions.
#40 stays open: two actual mixed-provider (Claude/Codex) issue-batch acceptances
still remain. Route boundary tests use fake described providers with gated
Invocations; neither they nor Echo establish real mixed-provider acceptance.

## Optional evidence ledger (#40 foundation)

`GenAgentServer.Control.Ledger` is caller-started, evidence-only storage. It
does not dispatch work or run commands. Execution, permissions, admission and
concurrency, deadlines, cancellation and cleanup remain raw/caller responsibilities.
Recorded failures, timeouts and cancellation are caller attestations. Acceptance
records never publish anything. Full #40 remains open, including orchestration
and two paid mixed-provider batches; the Echo example does not satisfy those batches.

```elixir
alias GenAgentServer.Control.Ledger
{:ok, ledger} = Ledger.start_link()
{:ok, run} = Ledger.open(ledger, %{name: "change", control_revision: "caller-v1",
  tasks: [%{name: "implementation", checkout: File.cwd!(), required_checks: ["test"]}]})
{:ok, attempt} = Ledger.record_attempt(ledger, run, "implementation", %{
  stage: "implement", kind: :work, provider: "echo", requested_settings: %{},
  instruction_revision: "prompt-v1", checkout: File.cwd!(), prompt: "hello"})
# Caller invokes via raw invoke(..., recipient: self()), then explicitly ingests:
:ok = Ledger.finish_attempt(ledger, run, attempt, %{status: :completed, text: "echo: hello"})
{:ok, snapshot} = Ledger.result(ledger, run) # repeatable; independent of raw eviction
```

Run `mix run examples/control_ledger_echo.exs` for a login-free example using the
existing raw recipient protocol, overlapping named tasks, explicit recording,
repeat reads and an assertion that evidence survives raw `max_results: 1` eviction.
The caller receives notifications directly; no new inbox consumer is introduced.
Caller scripts must project bounded evidence, handle raw admission failures and
own their resource cleanup. The ledger neither receives nor truncates raw responses.

Input maps have atom keys and reject unknown fields. The shapes above are required.
Work and review attempt specs optionally accept atom-key `expected_output`: a valid
UTF-8 string of 1..4,096 bytes, preserved exactly without trimming or normalization.
Empty strings, nil, malformed UTF-8 and non-strings return `:invalid_record`.
This is caller-declared acceptance guidance only: it does not augment prompts,
change provider options, match or validate output, or create approval/acceptance
records. Controller status/result expose the copied declaration as a string or nil
when omitted; adding, removing or changing it conflicts for an existing task/stage.
The full encoded attempt remains subject to Ledger record and total byte budgets,
with rejection before invocation and unchanged terminal reservations.

An attempt takes exactly one of `prompt` or `prompt_ref` (an external artifact
reference). `kind: :review` additionally requires `subject_revision_id`; work
attempts omit it. Requested settings are a flat map with string keys and scalar
string/integer/boolean/nil values. Revised specifications create separate attempt
IDs. Terminal `status` is `:completed`, `:failed`, `:admission_failed`, `:timed_out`
or `:cancelled`; optional fields are `text`, `actual_model`, `invocation_id`,
`session_id`, string `failure` and string-list `artifact_refs`. Missing text is
nil; present-empty text stays `""`. Unknown actual model remains nil, never the
requested model. Whole `Response.events` and arbitrary metadata are rejected.
Terminal evidence is immutable: exact normalized repeats are idempotent, different
payloads conflict. `result/2` includes all attempts and append-ordered gate records.

Each gate function takes `(ledger, run, record)` and returns `{:ok, record_id}`:

| Function | Required record fields | Optional fields |
| --- | --- | --- |
| `record_revision` | `task`, `produced_by_attempt_id`, `content_sha256`, `recorded_by` | `base_commit`, `artifact_refs` |
| `record_review` | `revision_id`, `review_attempt_id`, `verdict`, `recorded_by` | `excerpt` |
| `record_verification` | `revision_id`, `check_name`, `argv`, `cwd`, `exit_status`, `outcome`, `recorded_by` | `output`, `artifact_refs` |
| `record_acceptance` | `revision_id`, `decision`, `recorded_by` | `reason` |

Revision fingerprints are caller-attested lowercase SHA-256 strings covering
the intended content, including untracked contents, rather than merely HEAD.
The producer must be a completed work attempt for that task. Review requires a
completed review attempt naming exactly that subject revision; verdicts are
`:approve`, `:changes_requested` or `:unknown`. Verification records actual
caller-executed argv (list), absolute cwd equal to or within the task checkout, exit status
(0..255 or nil when unavailable), and outcome (`:passed`, `:failed`, `:timed_out`,
`:not_run`). Passed requires exit 0. Acceptance decisions are `:accepted` or
`:rejected`. Accepting requires the current revision, no unfinished attempts for
that task, the latest review approving, and the latest record for every required
check passing. The ledger stores those review/check IDs; callers cannot select an
older pass. New revisions inherit no gates. Historical records remain immutable;
`status/2` recomputes current eligibility and accepted status, so a later failed
check blocks acceptance even when a historical acceptance remains readable.
Accepted status also requires the latest host acceptance to reference exactly the
current review and required-check IDs. After a new pass or approving review,
eligibility can return to true while accepted stays false until the caller records
a new acceptance for that evidence set. Historical acceptances are never rewritten.

Verification containment compares path components after lexical normalization
(`Path.expand/1`) of both cwd and checkout. Package directories such as
`/work/alpha/extensions/ensemble` are allowed under `/work/alpha`, including
normalized inside paths containing `.` or `..`; relative paths, normalized escapes
and sibling prefix collisions such as `/work/alpha-other` are rejected. The supplied
cwd is retained unchanged as evidence. Paths need not exist; this performs no
realpath or symlink resolution and grants no filesystem authorization. Stage
attempts still require an exact match to the declared checkout string.

Defaults are hard finite ceilings, configurable downward with `start_link(limits:
keyword)`: `runs: 4`, `tasks_per_run: 8`, `attempts_per_run: 64`,
`records_per_run: 256`, `record_bytes: 65_536`, `total_bytes: 4_194_304`.
The manifest, each attempt, each terminal and each gate consume one record;
attempt admission reserves its terminal slot, included in reported record counts. Byte
accounting sums Erlang external sizes of immutable record envelopes, including
IDs; it bounds retained evidence, not total VM memory, projections or raw mailboxes.
Strings are at most 4,096 bytes, except prompt/text/output/excerpt up to the record
limit; lists have at most 32 entries and requested settings at most 16 pairs.
`:infinity` is rejected. Storage exhaustion returns `{:error, :quota_exhausted}`;
malformed fields return `{:error, :invalid_record}`. Ordinary `record_attempt/4`
and `record_attempt/5` with `[]` or `reserve_terminal: false` reserve no bytes;
a full byte budget or oversized finish preserves the unfinished attempt.
Use `Ledger.record_attempt(ledger, run, task, spec, reserve_terminal: true)` before
invoking work to reserve the full configured `record_bytes` ceiling for its terminal.
Admission requires the actual encoded attempt plus that reservation to fit alongside
all retained bytes and outstanding reservations across runs. Every manifest, attempt
and gate respects that shared capacity. Any valid encoded terminal within the record
ceiling can then finish, including after `close/2`, and releases exactly its own
reservation. Invalid or oversized evidence preserves it; identical duplicate finishes
and conflicting terminals do not charge or release again. Run snapshots and status
report actual `bytes` separately from outstanding `reserved_bytes`; opted-in attempts
also expose `reserved_bytes`, which becomes zero on finish. Record-count exhaustion
cannot consume an admitted attempt's reserved terminal slot. Options accept only `[]`
or a single boolean `reserve_terminal` pair; all other shapes, values, duplicate or
unknown keys return `{:error, :invalid_options}` with bounded validation.
Callers must still submit bounded evidence; ledger death loses reservations and data.

`close/2` stops new attempts/gates while permitting existing attempts to finish;
`forget/2` removes only an entire closed run without unfinished attempts. There
is no attempt eviction. Storage survives ordinary API caller death, but the linked
starter follows normal OTP link rules. Caller-owned supervision may use the
temporary child spec. Evidence lasts only while that ledger process lives; death
loses it, and a fresh ledger cannot recover old IDs. No disk persistence or replay.
