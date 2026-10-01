defmodule GenAgentServer.Remote do
  @moduledoc false

  @doc false
  def expression(args) when is_list(args) do
    encoded_args = inspect(args, limit: :infinity, printable_limit: :infinity)
    "GenAgentServer.CLI.main(#{encoded_args}, :remote_cli)"
  end

  @doc false
  def run(release_bin, args) when is_binary(release_bin) and is_list(args) do
    System.cmd(release_bin, ["rpc", expression(args)], stderr_to_stdout: true)
  end
end
