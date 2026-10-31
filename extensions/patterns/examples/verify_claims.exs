# Run with: mix run examples/verify_claims.exs CLAIMS.json PROJECT_DIR [WORKERS]
#
# Verifies a batch of claims (for example review findings or bug reports)
# against a project with a pool of read-only Codex workers. CLAIMS.json is a
# list of objects with "id" and "title", plus optional "file", "line", and
# "summary". Prints one line per claim and writes CLAIMS.verified.json.

[claims_path, cwd | rest] = System.argv()
workers = rest |> List.first("3") |> String.to_integer()
claims = claims_path |> File.read!() |> Jason.decode!()

spec = %{
  "pattern" => "pool",
  "worker_count" => workers,
  "worker" => %{
    "provider" => "codex",
    "role" =>
      "You verify one claim about the code in this repository. Read the cited code yourself and do not trust the claim. " <>
        "Reply with a first line `VERDICT: CONFIRMED`, `VERDICT: REFUTED`, or `VERDICT: FIXED` (true earlier, no longer true), " <>
        "then at most 120 words of evidence with file:line. Do not narrate what you are about to do."
  }
}

prompts =
  Enum.map(claims, fn c ->
    location =
      if c["file"], do: "\nLocation: #{c["file"]}#{if c["line"], do: ":#{c["line"]}"}", else: ""

    "Claim: #{c["title"]}#{location}\n\nDetail: #{c["summary"] || ""}"
  end)

{:ok, report} = GenAgentServer.Run.run(spec, prompts, cwd: Path.expand(cwd), timeout: 1_800_000)

verified =
  Enum.zip_with(claims, report.results, fn claim, item ->
    verdict =
      case item.text && Regex.run(~r/VERDICT:\s*\**\s*(CONFIRMED|REFUTED|FIXED)/i, item.text) do
        [_, v] -> String.downcase(v)
        _ -> "unclear"
      end

    Map.merge(claim, %{
      "verdict" => if(item.status == :completed, do: verdict, else: "#{item.status}"),
      "evidence" => item.text || item.error,
      "elapsed_ms" => item.elapsed_ms
    })
  end)

:io.setopts(:standard_io, encoding: :unicode)

for v <- verified do
  IO.puts(
    "#{String.pad_trailing(v["verdict"], 9)} #{v["id"]}  (#{div(v["elapsed_ms"], 1000)} s)  #{v["title"]}"
  )
end

IO.puts("\n#{length(verified)} claims, #{report.elapsed_ms} ms total")
File.write!(Path.rootname(claims_path) <> ".verified.json", Jason.encode!(verified, pretty: true))
