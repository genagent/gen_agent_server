The host compile fails:

    warning: ClaudeWrapper.Commands.Version.compare/2 is undefined or private
    Compilation failed due to warnings while using the --warnings-as-errors option

lib/mix/tasks/claude.contract.ex aliases ClaudeWrapper.Commands.Version as `Version` (the alias list near the top of the module), so `Version.compare/2` and any other `Version.` call you added resolve to that module instead of Elixir's Version. Call Elixir's module explicitly as `Elixir.Version` at every place you added a `Version.` call in this file. Change nothing else. The four new contract tests fail for the same reason.
