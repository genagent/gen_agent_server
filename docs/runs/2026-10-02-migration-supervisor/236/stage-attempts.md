# Supervisor guide stage attempts

The runner's final JSON contains only the last attempt for a repeated stage.
These session IDs and actual model IDs were read from each completed handoff
summary before the next revision overwrote it. Each attempt used one named
managed instance, and the handoff script stopped that instance in `after`.

| Attempt | Provider and actual model | Session | Result |
| --- | --- | --- | --- |
| Triage | Claude `claude-opus-5-5` | `766c92d8-d86c-4f1a-b1be-cb04514a146e` | Five findings confirmed; private plan path redacted from saved text. |
| First implementation | Codex `gpt-6-astra` | `01a0fbf5-0f63-7d72-879a-b21d48ee1468` | Guide and tests edited. |
| First review | Claude `claude-opus-5-5` | `1786d780-6f86-4320-9382-fe48413f6285` | Request changes: queued user turn could be mistaken for synthesis. |
| First revision | Codex `gpt-6-astra` | `01a0fbfe-cb2d-70e3-8375-55e63af71e97` | `pre_turn/2` gate and two regression cases. |
| Second review | Claude `claude-opus-5-5` | `ed926fe9-6479-45d5-9585-e319a6b1be08` | Request changes: queue rejection could strand synthesis. |
| Second revision | Codex `gpt-6-astra` | `01a0fc03-2c0f-72c2-922e-ab933bcd55d3` | Rejection becomes terminal; cleanup test. |
| Third review | Claude `claude-opus-5-5` | `d3a8c9cd-610f-4ab9-ba36-ba781b35307d` | Approve with a provider-overload ambiguity. |
| Final review-only | Claude `claude-opus-5-5` | `512d6047-7102-47e8-95ed-af184807a6c5` | Approve after caller narrowed the queue shape and added a provider-overload test. |

Requested models matched actual models in each attempt. The guide tests used
a scripted local backend. The caller ran package checks outside the model
sessions; see the parent run record.
