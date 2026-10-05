defmodule GenAgentServer.Peers.Adapter do
  @moduledoc """
  Trusted provider adapter for externally owned peers. The ledger owns request
  identity, persistence and state; the adapter owns discovery, generation checks,
  native wire framing and reply parsing. Modules/options are operator context,
  never MCP arguments. The initial implementation is Claude Code on macOS.
  """
  @callback provider() :: String.t()
  @callback discover(keyword()) :: [map()]
  @callback verify(map(), keyword()) :: :ok | {:error, term()}
  @callback public(map()) :: map()
  @callback notice(map(), String.t()) :: String.t()
  @callback send(map(), String.t(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  @callback parse_reply(map()) :: {:ok, map()} | :ignored
  @callback reply_source?(map(), String.t(), keyword()) :: boolean()
end
