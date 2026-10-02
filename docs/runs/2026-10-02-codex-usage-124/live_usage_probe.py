import json
import subprocess
from pathlib import Path

directory = Path('/tmp/gen_agent_issue_124_probe')
directory.mkdir(exist_ok=True)

def run(args, name):
    result = subprocess.run(args, cwd=directory, capture_output=True, text=True, timeout=180)
    (directory / f'{name}.jsonl').write_text(result.stdout)
    (directory / f'{name}.stderr').write_text(result.stderr)
    if result.returncode:
        raise RuntimeError(f'{name} failed with exit {result.returncode}; see local stderr file')
    events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
    thread = next((event.get('thread_id') for event in events if event.get('type') == 'thread.started'), None)
    completed = [event for event in events if event.get('type') == 'turn.completed']
    if not thread or len(completed) != 1:
        raise RuntimeError(f'{name} had no thread ID or exactly one completion')
    return thread, completed[0].get('usage')

first_path = directory / 'first.jsonl'
if first_path.exists():
    first_events = [json.loads(line) for line in first_path.read_text().splitlines() if line.startswith('{')]
    thread = next(event['thread_id'] for event in first_events if event.get('type') == 'thread.started')
    first = next(event['usage'] for event in first_events if event.get('type') == 'turn.completed')
else:
    thread, first = run(['codex', 'exec', '--json', '--ignore-user-config', '--skip-git-repo-check', '--sandbox', 'read-only', '-m', 'gpt-6-luna', 'Reply with exactly ONE.'], 'first')
resumed_thread, second = run(['codex', 'exec', 'resume', '--json', '--ignore-user-config', '--skip-git-repo-check', '-m', 'gpt-6-luna', thread, 'Reply with exactly TWO.'], 'second')
print(json.dumps({'same_thread': thread == resumed_thread, 'first_usage': first, 'second_usage': second}, indent=2))
