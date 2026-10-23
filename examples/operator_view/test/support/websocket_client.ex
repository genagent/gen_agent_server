defmodule OperatorView.WebSocketClient do
  @moduledoc false
  # Minimal RFC 6455 client for endpoint tests: one upgrade request over TCP,
  # masked text frames out, unmasked text frames in. Enough to drive the
  # LiveView socket the way a browser would, including Origin and Cookie.

  @doc "Send an upgrade request. Returns the HTTP status and the open socket."
  def upgrade(port, path, headers) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    key = Base.encode64(:crypto.strong_rand_bytes(16))

    request = [
      "GET #{path} HTTP/1.1\r\n",
      "host: 127.0.0.1:#{port}\r\n",
      "connection: Upgrade\r\n",
      "upgrade: websocket\r\n",
      "sec-websocket-version: 13\r\n",
      "sec-websocket-key: #{key}\r\n",
      Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end),
      "\r\n"
    ]

    :ok = :gen_tcp.send(socket, request)
    {head, rest} = read_head(socket, "")
    ["HTTP/1.1", status | _reason] = head |> String.split("\r\n") |> hd() |> String.split(" ")
    {String.to_integer(status), %{socket: socket, buffer: rest}}
  end

  def close(%{socket: socket}), do: :gen_tcp.close(socket)

  @doc "Send one JSON message as a masked text frame."
  def send_json(%{socket: socket}, message) do
    payload = Jason.encode!(message)
    key = :crypto.strong_rand_bytes(4)
    frame = [<<1::1, 0::3, 1::4>>, frame_length(payload), key, mask(payload, key)]
    :ok = :gen_tcp.send(socket, frame)
  end

  @doc "Receive JSON messages until `fun` accepts one."
  def receive_json(client, fun, timeout \\ 2_000) do
    {text, client} = read_text(client, timeout)
    message = Jason.decode!(text)
    if fun.(message), do: {message, client}, else: receive_json(client, fun, timeout)
  end

  defp read_head(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [head, rest] ->
        {head, rest}

      [_partial] ->
        {:ok, data} = :gen_tcp.recv(socket, 0, 2_000)
        read_head(socket, buffer <> data)
    end
  end

  defp read_text(%{buffer: buffer} = client, timeout) do
    case frame(buffer) do
      {:ok, 1, payload, rest} ->
        {payload, %{client | buffer: rest}}

      {:ok, _other_opcode, _payload, rest} ->
        read_text(%{client | buffer: rest}, timeout)

      :more ->
        {:ok, data} = :gen_tcp.recv(client.socket, 0, timeout)
        read_text(%{client | buffer: buffer <> data}, timeout)
    end
  end

  defp frame(<<_fin::1, _rsv::3, opcode::4, 0::1, 126::7, size::16, rest::binary>>),
    do: payload(opcode, size, rest)

  defp frame(<<_fin::1, _rsv::3, opcode::4, 0::1, 127::7, size::64, rest::binary>>),
    do: payload(opcode, size, rest)

  defp frame(<<_fin::1, _rsv::3, opcode::4, 0::1, size::7, rest::binary>>) when size < 126,
    do: payload(opcode, size, rest)

  defp frame(_partial), do: :more

  defp payload(opcode, size, data) do
    case data do
      <<payload::binary-size(^size), rest::binary>> -> {:ok, opcode, payload, rest}
      _partial -> :more
    end
  end

  defp frame_length(payload) do
    case byte_size(payload) do
      size when size < 126 -> <<1::1, size::7>>
      size when size < 65_536 -> <<1::1, 126::7, size::16>>
      size -> <<1::1, 127::7, size::64>>
    end
  end

  defp mask(payload, <<a, b, c, d>>) do
    keys = [a, b, c, d]

    payload
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.map(fn {byte, index} -> Bitwise.bxor(byte, Enum.at(keys, rem(index, 4))) end)
    |> :binary.list_to_bin()
  end
end
