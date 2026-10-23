# Record what the observer application started before any integration test
# starts the server application in this VM.
boot = %{
  applications: Enum.map(Application.started_applications(), &elem(&1, 0)),
  registry: Process.whereis(GenAgentServer.Registry)
}

:persistent_term.put({:operator_view_test, :boot}, boot)
ExUnit.start()
