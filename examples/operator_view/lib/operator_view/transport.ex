defmodule OperatorView.Transport do
  @moduledoc """
  How the observer reaches the release.

  `OperatorView.Reader` is the only caller and passes one of its fixed
  read-only operation names. Results use the server's Ops envelope: `{:ok, data}`
  with JSON-decoded data, or `{:error, error}` with a `code`.
  """

  @callback call(operation :: String.t(), args :: map(), timeout_ms :: pos_integer()) ::
              {:ok, term()} | {:error, map()}
end
