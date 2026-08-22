setup() {
  BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
  export HOME_ORIG="$HOME"
  export TMP_HOME="$BATS_TMPDIR/dojo-home"
  rm -rf "$TMP_HOME"
  mkdir -p "$TMP_HOME"
  export HOME="$TMP_HOME"
  export DOJO_DIR="$BATS_TEST_DIRNAME/.."
  export TOKEN_OPTIMIZER_DATA_DIR="$BATS_TMPDIR/dojo-tokens-empty"
  rm -rf "$TOKEN_OPTIMIZER_DATA_DIR"
  mkdir -p "$TOKEN_OPTIMIZER_DATA_DIR"
}

@test "dojo-tokens.py: empty data -> silent, exit 0" {
  run python3 "$DOJO_DIR/dojo-tokens.py" --one-line
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dojo-tokens.py: sqlite fixture -> usage + fill + grade" {
  FIX="$BATS_TMPDIR/dojo-tokens-sqlite"
  rm -rf "$FIX"
  mkdir -p "$FIX/sessions/proj"
  python3 - "$FIX" <<'PY'
import os, sqlite3, sys
fix = sys.argv[1]
db = os.path.join(fix, "sessions", "proj", "ses_1.db")
c = sqlite3.connect(db)
c.execute("CREATE TABLE session_meta (key TEXT, value TEXT)")
c.execute("CREATE TABLE quality_cache (id INTEGER, resource_health REAL, session_efficiency REAL, fill_pct REAL, compactions INTEGER, tool_calls INTEGER, last_nudge_time REAL, nudge_count INTEGER, data TEXT, updated_at REAL)")
c.execute("INSERT INTO session_meta VALUES ('current_mode','general')")
c.execute("INSERT INTO quality_cache VALUES (1, 82, 91, 0.41, 2, 55, NULL, 0, '', 1787000000)")
c.commit(); c.close()
t = sqlite3.connect(os.path.join(fix, "trends.db"))
t.execute("CREATE TABLE session_log (id INTEGER, session_id TEXT, date TEXT, project TEXT, model TEXT, tokens_input INTEGER, tokens_output INTEGER, tokens_cache_read INTEGER, tokens_cache_write INTEGER, cost_usd REAL, resource_health REAL, session_efficiency REAL, tool_calls INTEGER, compactions INTEGER, mode TEXT, duration_seconds INTEGER, created_at REAL)")
t.execute("INSERT INTO session_log VALUES (1, 'ses_1', '2026-08-20', 'p', 'gpt-test', 50000, 7000, 200000, 3000, 0.12, 82, 91, 55, 2, 'general', 300, 1787000000)")
t.commit(); t.close()
PY
  TOKEN_OPTIMIZER_DATA_DIR="$FIX" run python3 "$DOJO_DIR/dojo-tokens.py"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "usage:"
  echo "$output" | grep -q "health 82/100"
  echo "$output" | grep -q "gpt-test"
  TOKEN_OPTIMIZER_DATA_DIR="$FIX" run python3 "$DOJO_DIR/dojo-tokens.py" --one-line
  echo "$output" | grep -q "fill 41%"
}

@test "dojo-tokens.py: claude json layout -> fill + health" {
  FIX="$BATS_TMPDIR/dojo-tokens-claude"
  rm -rf "$FIX"
  mkdir -p "$FIX"
  cat > "$FIX/quality-cache-sesA.json" <<'JSON'
{"resource_health": 88, "session_efficiency": 75, "fill_pct": 62, "tool_calls": 10}
JSON
  cat > "$FIX/live-fill.json" <<'JSON'
{"used_percentage": 64, "timestamp": 1788000000000, "session_id": "sesA"}
JSON
  TOKEN_OPTIMIZER_DATA_DIR="$FIX" run python3 "$DOJO_DIR/dojo-tokens.py" --one-line
  echo "$output" | grep -q "fill 64%"
  echo "$output" | grep -q "A"
}

@test "bootstrap.sh: shell profile block is idempotent (one marker)" {
  export CLAUDE_CONFIG_DIR="$TMP_HOME/.claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  "$DOJO_DIR/bootstrap.sh" >/dev/null 2>&1 || true
  "$DOJO_DIR/bootstrap.sh" >/dev/null 2>&1 || true
  count="$(grep -c '# >>> dojo >>>' "$TMP_HOME/.bashrc" || true)"
  [ "$count" -eq 1 ]
  grep -q '__dojo_ps1_tokens' "$TMP_HOME/.bashrc"
}

@test "dojo: status runs clean" {
  "$DOJO_DIR/dojo" status >/dev/null 2>&1
}

@test "doctor: claude doc links wired by bootstrap verify ok" {
  export CLAUDE_CONFIG_DIR="$TMP_HOME/.claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  "$DOJO_DIR/bootstrap.sh" >/dev/null 2>&1 || true
  run bash "$DOJO_DIR/dojo" doctor
  echo "$output" | grep -q 'CLAUDE.md linked to dojo'
  echo "$output" | grep -q 'RTK.md linked to dojo'
}

@test "doctor: tool under ~/.local/bin found without being on PATH" {
  mkdir -p "$TMP_HOME/.local/bin"
  printf '#!/bin/sh\necho "graphify 9.9.9"\n' > "$TMP_HOME/.local/bin/graphify"
  chmod +x "$TMP_HOME/.local/bin/graphify"
  run env PATH="/usr/bin:/bin" HOME="$TMP_HOME" bash "$DOJO_DIR/dojo" doctor
  echo "$output" | grep -q 'graphify (graphify 9.9.9)'
}

@test "opencode pins: ponytail renamed, no legacy name" {
  grep -q '@dietrichgebert/ponytail' "$DOJO_DIR/opencode/opencode.jsonc"
  ! grep -q 'opencode-ponytail' "$DOJO_DIR/opencode/opencode.jsonc"
}

@test "copilot statusline: json in -> readout, garbage -> silent" {
  run bash "$DOJO_DIR/copilot/statusline.sh" <<'JSON'
{"context_window": {"used_percentage": 42.5, "total_input_tokens": 12000, "total_output_tokens": 800}}
JSON
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ctx 42%"
  run bash "$DOJO_DIR/copilot/statusline.sh" <<'JUNK'
not json
JUNK
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}