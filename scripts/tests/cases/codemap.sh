# The codebase-memory code map: binary install, wrapper, MCP entries per agent.

test_code_map_install() {
  local d="$WORK/cm"
  rm -rf "$d" && mkdir -p "$d" && : > "$CM_LOG"
  check "bootstrap succeeds" bootstrap "$d" -t claude
  check "binary installed per machine" test -x "$CM_BIN"
  check "license kept beside it" test -f "$(dirname "$CM_BIN")/LICENSE"
  check "wrapper" test -x "$d/.agents/codebase-memory"
  check "wrapper pins the version" contains "$d/.agents/codebase-memory" "versions/$CM_VERSION/codebase-memory-mcp"
  check "project indexed from its root" contains "$CM_LOG" "cli --quiet index_repository {\"repo_path\":\"$d\"} | cwd=$d"
  check "stage shows the graph size" contains "$WORK/last.log" "$CM_VERSION · 12 nodes · 34 edges"
  check "summary points at the UI" contains "$WORK/last.log" ".agents/codebase-memory ui"
  check "instruction in CLAUDE.md" contains "$d/CLAUDE.md" "**Code map:** codebase-memory"
  check "subagents told too" contains "$d/.claude/agents/planner.md" "if \`.agents/codebase-memory\` exists"
  check "server in .mcp.json" contains "$d/.mcp.json" '.agents/codebase-memory\" serve'
  check "server enabled" test "$(json_get "$d/.claude/settings.json" '{enabledMcpjsonServers}')" = '["codebase-memory"]'
  check "read-only tool approved" contains "$d/.claude/settings.json" '"mcp__codebase-memory__search_graph"'
  check "index tool approved" contains "$d/.claude/settings.json" '"mcp__codebase-memory__index_repository"'
  check_not "delete_project keeps asking" contains "$d/.claude/settings.json" 'delete_project'
  check_not "manage_adr keeps asking" contains "$d/.claude/settings.json" 'manage_adr'
  # a re-run finds the binary: no download, so no mirror needed
  CODEBASE_MEMORY_MIRROR=file:///nonexistent bootstrap "$d" -t claude
  check_not "no download on re-run" contains "$WORK/last.log" "could not download"
  check "--check up to date" bootstrap "$d" --check
}

test_code_map_all_agents() {
  local d="$WORK/cmall" f
  rm -rf "$d" && mkdir -p "$d"
  bootstrap "$d" -t all
  check "VS Code: workspace path" test "$(json_get "$d/.vscode/mcp.json" '{servers}{"codebase-memory"}{command}')" = '${workspaceFolder}/.agents/codebase-memory'
  check "VS Code: serve" test "$(json_get "$d/.vscode/mcp.json" '{servers}{"codebase-memory"}{args}')" = '["serve"]'
  check "VS Code: autostart" test "$(json_get "$d/.vscode/settings.json" '{"chat.mcp.autostart"}')" = newAndOutdated
  # Copilot CLI reads .mcp.json and .github/mcp.json, not .vscode/mcp.json (and
  # expands no VS Code variable)
  check "Copilot CLI: .github/mcp.json walks up to the wrapper" test "$(json_get "$d/.github/mcp.json" '{mcpServers}{"codebase-memory"}{command}')" = sh
  check "Copilot CLI: no VS Code variable" sh -c "! grep -q '\${' '$d/.github/mcp.json'"
  check "Copilot CLI: tools limited to the approved ones" contains "$d/.github/mcp.json" '"search_graph"'
  check_not "Copilot CLI: delete_project not exposed" contains "$d/.github/mcp.json" delete_project
  mkdir -p "$d/src/deep" && : > "$CM_LOG"
  (cd "$d/src/deep" && sh -c "$(json_get "$d/.github/mcp.json" '{mcpServers}{"codebase-memory"}{args}[1]')" < /dev/null > /dev/null 2>&1)
  check "Copilot CLI: starts the server from a subdirectory, in the project" contains "$CM_LOG" "| cwd=$d"
  check "Cursor: workspace path" test "$(json_get "$d/.cursor/mcp.json" '{mcpServers}{"codebase-memory"}{command}')" = '${workspaceFolder}/.agents/codebase-memory'
  check "Codex: managed block" contains "$d/.codex/config.toml" '[mcp_servers.codebase-memory]'
  check "Codex: walks up to the wrapper" contains "$d/.codex/config.toml" 'exec \"$d/.agents/codebase-memory\" serve'
  check "Gemini: from the project" test "$(json_get "$d/.gemini/settings.json" '{mcpServers}{"codebase-memory"}{args}[1]')" = 'exec .agents/codebase-memory serve'
  check "Antigravity" contains "$d/.agents/mcp_config.json" '.agents/codebase-memory\" serve'
  check "Devin" contains "$d/.devin/mcp_config.json" '.agents/codebase-memory\" serve'
  for f in AGENTS.md GEMINI.md .github/copilot-instructions.md .cursor/rules/superpowers.mdc .agents/rules/superpowers.md .devin/rules/superpowers.md; do
    check "instruction in $f" contains "$d/$f" "**Code map:**"
  done
  check "--check up to date" bootstrap "$d" --check

  bootstrap "$d" -t all --no-code-map
  check "lock records --no-code-map" contains "$d/.agents/superpowers.lock" "options: --no-code-map"
  check "wrapper removed" test ! -e "$d/.agents/codebase-memory"
  check ".mcp.json removed" test ! -e "$d/.mcp.json"
  check "VS Code entry removed" test ! -e "$d/.vscode/mcp.json"
  check "Copilot CLI entry removed" test ! -e "$d/.github/mcp.json"
  check "Cursor entry removed" test ! -e "$d/.cursor/mcp.json"
  check_not "Codex block removed" contains "$d/.codex/config.toml" 'codebase-memory'
  check_not "Gemini entry removed" contains "$d/.gemini/settings.json" 'codebase-memory'
  check_not "Antigravity entry removed" test -e "$d/.agents/mcp_config.json"
  check_not "approvals removed" contains "$d/.claude/settings.json" 'codebase-memory'
  check_not "instruction removed" contains "$d/CLAUDE.md" "Code map"
  check_not "subagent line removed" contains "$d/.claude/agents/planner.md" "codebase-memory"
  check "--check up to date with --no-code-map" bootstrap "$d" --check

  bootstrap "$d" -t claude
  check "back on: deselected agents' entries stay gone" test ! -e "$d/.cursor/mcp.json"
  check "back on: claude's server" contains "$d/.mcp.json" 'codebase-memory'
}

test_code_map_own_server_kept() {
  local d="$WORK/cmown"
  rm -rf "$d" && mkdir -p "$d/.claude"
  echo '{"mcpServers":{"codebase-memory":{"command":"codebase-memory-mcp"}}}' > "$d/.mcp.json"
  echo '{"enabledMcpjsonServers":["codebase-memory"]}' > "$d/.claude/settings.json"
  bootstrap "$d" -t claude
  check "warns" contains "$WORK/last.log" ".mcp.json already has a codebase-memory server of your own"
  check "theirs kept" test "$(json_get "$d/.mcp.json" '{mcpServers}{"codebase-memory"}{command}')" = codebase-memory-mcp
  check_not "no tool approvals for theirs" contains "$d/.claude/settings.json" 'mcp__codebase-memory__'
  bootstrap "$d" --uninstall
  check "theirs kept by uninstall" test "$(json_get "$d/.mcp.json" '{mcpServers}{"codebase-memory"}{command}')" = codebase-memory-mcp
  check "their approval kept by uninstall" contains "$d/.claude/settings.json" '"codebase-memory"'
}

test_code_map_install_failure() {
  local d="$WORK/cmfail"
  rm -rf "$d" && mkdir -p "$d"
  check "bad checksum: still succeeds" env CODEBASE_MEMORY_INSTALL_DIR="$WORK/cmfresh" CODEBASE_MEMORY_SHA256=0000 bash "$BOOTSTRAP" -y -s "$SP" --ecc-source "$ECC" --security-audit-source "$SA" -t claude "$d"
  CODEBASE_MEMORY_INSTALL_DIR="$WORK/cmfresh" CODEBASE_MEMORY_SHA256=0000 bootstrap "$d" -t claude
  check "warns" contains "$WORK/last.log" "codebase-memory download failed its checksum"
  check "nothing installed" test ! -e "$WORK/cmfresh/versions/$CM_VERSION"
  check "no half-unpacked dir" test ! -e "$WORK/cmfresh/versions/$CM_VERSION.sp-tmp"
  check "next step" contains "$WORK/last.log" "install codebase-memory, or re-run with CODEBASE_MEMORY_MIRROR"
  check "agents still configured" contains "$d/.mcp.json" 'codebase-memory'
  CODEBASE_MEMORY_INSTALL_DIR="$WORK/cmfresh" CODEBASE_MEMORY_MIRROR=file:///nonexistent bootstrap "$d" -t claude
  check "download failure warns" contains "$WORK/last.log" "could not download file:///nonexistent"

  : > "$CM_LOG"
  CM_FAKE_FAIL=1 bootstrap "$d" -t claude
  check "index failure warns" contains "$WORK/last.log" "codebase-memory could not index the project: {\"error\":\"boom: parser crashed\"}"
  check "index failure: not indexed" contains "$WORK/last.log" "$CM_VERSION · not indexed"
}

test_code_map_wrapper() {
  local d="$WORK/cm" real="$WORK/cm"
  check "project: its name" test "$("$d/.agents/codebase-memory" project)" = fake-project
  : > "$CM_LOG"
  (cd /tmp && "$d/.agents/codebase-memory" serve < /dev/null) > /dev/null 2>&1
  check "serve: no args, from the project" contains "$CM_LOG" " | cwd=$real"
  : > "$CM_LOG"
  "$d/.agents/codebase-memory" cli search_graph '{"query":"x"}' > /dev/null 2>&1
  check "anything else passes through" contains "$CM_LOG" "cli search_graph {\"query\":\"x\"} | cwd=$real"
  check_not "ui off: says how to turn it on" env CM_FAKE_UI=false "$d/.agents/codebase-memory" ui
  CM_FAKE_UI=false "$d/.agents/codebase-memory" ui > "$WORK/ui.log" 2>&1
  check "ui off: message" contains "$WORK/ui.log" "config set ui_enabled true"
  env CODEBASE_MEMORY_INSTALL_DIR="$WORK/nowhere" "$d/.agents/codebase-memory" serve > "$WORK/missing.log" 2>&1
  check "not installed: exit 127" test $? -eq 127
  check "not installed: says so" contains "$WORK/missing.log" "codebase-memory $CM_VERSION is not installed on this machine"
}
