# gen_agent_server selection extension

Optional, pure route suggestions for [gen_agent_server](../../README.md). A library: it adds no operations or processes. Add `{:gen_agent_server_selection, path: "path/to/gen_agent_server/extensions/selection"}` to a host and call `GenAgentServer.Selection` directly.

## Optional route suggestions (issue #22, first increment)

`GenAgentServer.Selection.suggest/3` and `explain/3` return the same pure,
deterministic recommendation over caller-approved named routes. The caller
manager retains choice and admission. Roles/profiles describe behavior and IO;
provider, configured model and effort describe separate execution settings.
This helper does not infer one from the other or change route permissions.

```elixir
descriptor = %{"required_capabilities" => ["read"], "preferred_provider" => "codex"}
catalogue = %{
  "revision" => "routes-1",
  "candidates" => [
    %{"route" => "project-reader", "provider" => "codex",
      "model" => nil, "effort" => nil, "capabilities" => ["read"],
      "availability" => "unknown"}
  ]
}
policy = %{"revision" => "policy-1", "catalogue_revision" => "routes-1",
           "unknown_availability" => "allow"}
{:ok, explanation} = GenAgentServer.Selection.suggest(descriptor, catalogue, policy)
explanation.recommendation["route"] # "project-reader"
explanation.recommendation["availability"] # still "unknown"
```

Inputs use string keys. `required_capabilities` is required; optional `route`,
`provider`, `model` and `effort` strings are hard constraints. An explicit request
must match an eligible candidate or return `{:error, %{code: :no_route,
explanation: ...}}`. `preferred_provider` ranks eligible routes only; ties use
ascending route name. Explanations include alternative route names, fixed
exclusion codes, applied ordering rules and caller-supplied revisions. A mismatched
policy `catalogue_revision` returns `:catalogue_revision_mismatch`. Output size
is proportional to the caller's catalogue, with no enforced response-size cap.

Every candidate supplies a unique route name, provider, configured model/effort
(strings or `nil` for unknown), operator-attested capabilities and availability
(`"available"`, `"unavailable"`, `"unknown"`). Unknown availability defaults to
excluded unless policy explicitly allows it; unavailable routes remain excluded.
These attestations are not measured health or actual provider execution reports.
Malformed inputs and unknown fields return typed errors. Prompt/policy text,
role/profile and session/continuation fields are unsupported; continuations stay
with their original admitted selection outside this helper.

There are no runtime reads, model discovery, classifier calls, spawning,
fallback/retry or round robin. Suggestions reserve no capacity and do not replace
final admission or actual provider reporting. The broader issue #22 remains open.
