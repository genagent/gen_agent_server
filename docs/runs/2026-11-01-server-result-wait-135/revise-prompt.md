A reviewer (a separate agent that read your change but could not run it) requested changes. The host ran every gate and all pass: root 124 tests, examples, the echo smoke, and every extension (control 88, mcp 33, patterns 17, peers 19, public_source 7, schedule 5, selection 8). The failures you saw were the sandbox.

Fix defects 1 to 5 below as the reviewer describes. One correction from the operator: under "Not asked for", the reviewer calls the two-element handle_call({:result, id}, ...) dead code. It is not: extensions/control/test/gen_agent_server_control_controller_test.exs:1155 sends that tuple. Keep the clause and add a one-line comment saying why it is kept.

Then run mix format, mix compile --warnings-as-errors, mix test in the root, and mix test in extensions/mcp (MIX_OS_CONCURRENCY_LOCK=0), and report what you changed for each defect.

The review follows.

The full text of review.md followed here.
