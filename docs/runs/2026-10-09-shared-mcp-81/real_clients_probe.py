"""Optional bounded real Claude/Codex MCP probe; incurs provider usage.

Run after `MIX_ENV=prod mix release --overwrite` from the repository root.
The script starts one temporary Echo-only packaged release and never persists its token.
"""

import json
import os
import select
import secrets
import socket
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RELEASE = ROOT / '_build/prod/rel/gen_agent_server/bin/gen_agent_server'
with socket.socket() as sock:
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
token = secrets.token_urlsafe(32)
url = f'http://127.0.0.1:{port}/mcp'
env = os.environ.copy()
env.update({
    'GEN_AGENT_SERVER_SHARED_MCP_ENABLED': 'true',
    'GEN_AGENT_SERVER_SHARED_MCP_PORT': str(port),
    'GEN_AGENT_SERVER_SHARED_MCP_TOKEN': token,
    'GEN_AGENT_SERVER_SHARED_MCP_INSTANCES': '["server/default"]',
    'GEN_AGENT_SERVER_PROVIDERS': 'echo',
    'GEN_AGENT_SERVER_PEERS': 'false',
    'GEN_AGENT_TEST_TOKEN': token,
})
env.pop('GEN_AGENT_SERVER_CONFIG', None)
code = '{:ok, _} = Application.ensure_all_started(:gen_agent_server); IO.puts("shared-ready"); IO.gets("")'
proc = subprocess.Popen([str(RELEASE), 'eval', code], cwd=ROOT, env=env,
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True)
try:
    if not select.select([proc.stdout], [], [], 10)[0]:
        raise RuntimeError('release startup timed out')
    if proc.stdout.readline().strip() != 'shared-ready':
        raise RuntimeError('release failed to become ready')
    with tempfile.TemporaryDirectory(prefix='genagent_mcp_client_') as tmp:
        config = Path(tmp) / 'claude-mcp.json'
        config.write_text(json.dumps({'mcpServers': {'genagent': {
            'type': 'http', 'url': url,
            'headers': {'Authorization': 'Bearer ' + token}
        }}}))
        config.chmod(0o600)
        prompt = ('Call genagent MCP instances, then invoke the echo agent on '
                  'server/default with prompt real-client-probe. '
                  'Poll genagent MCP result until completed. '
                  'Report the invocation ID and final echo response. '
                  'Do not use Bash or modify files.')
        checks = [
            ('claude', ['claude', '-p', '--no-session-persistence',
                        '--strict-mcp-config', '--mcp-config', str(config),
                        '--allowedTools', 'mcp__genagent__instances,mcp__genagent__invoke,mcp__genagent__result',
                        '--max-budget-usd', '0.20', prompt]),
            ('codex', ['codex', 'exec', '--ephemeral', '--ignore-user-config',
                       '--skip-git-repo-check', '--approve-for-me',
                       '-c', f'mcp_servers.genagent.url="{url}"',
                       '-c', 'mcp_servers.genagent.bearer_token_env_var="GEN_AGENT_TEST_TOKEN"',
                       prompt]),
        ]
        for name, command in checks:
            try:
                result = subprocess.run(command, cwd=tmp, env=env,
                                        capture_output=True, text=True,
                                        timeout=120)
                combined = result.stdout + '\n' + result.stderr
                print(f'{name}: exit={result.returncode}, id_seen={"inv-" in combined}, '
                      f'echo_seen={"echo:" in combined}, '
                      f'error_seen={"error" in combined.lower()}')
                print(combined[-4000:].replace(token, '[REDACTED]'))
            except subprocess.TimeoutExpired:
                print(f'{name}: timed out after 120 seconds')
finally:
    if proc.poll() is None:
        proc.stdin.write('\n')
        proc.stdin.flush()
    proc.communicate(timeout=10)
    print(f'release exit={proc.returncode}')
