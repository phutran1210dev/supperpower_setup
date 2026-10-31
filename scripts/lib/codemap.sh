# The code map: codebase-memory-mcp (https://github.com/DeusData/codebase-memory-mcp,
# MIT), a graph of the project's functions, calls, routes and files that the
# agents query over MCP instead of searching and reading file after file. It
# parses 150+ languages with tree-sitter (shell included), runs locally with no
# telemetry, and serves a graph UI on 127.0.0.1 (`.agents/codebase-memory ui`).
# --no-code-map leaves it out.
#
# The binary (~320 MB unpacked, one static file) is per machine: a pinned,
# checksum-verified release goes into ~/.codebase-memory/versions/<version>, so
# every project shares one copy; nothing is put on PATH and its own installer
# (which edits user-level agent configs) is never run. The index lives in its
# cache (~/.cache/codebase-memory-mcp), outside the project; the server's file
# watcher keeps it current while an agent runs.
#
# CODEBASE_MEMORY_MIRROR       base URL serving the release files (default: GitHub releases)
# CODEBASE_MEMORY_SHA256       expected checksum when the mirror serves a different build
# CODEBASE_MEMORY_INSTALL_DIR  where binaries live (default: ~/.codebase-memory)

CM_VERSION="0.12.1"
CM_NAME="codebase-memory"
CM_WRAPPER=".agents/codebase-memory"
# the tools pre-approved where an agent supports it: the read-only ones, and
# index_repository, which writes only to its cache. delete_project, manage_adr
# (writes ADR files) and ingest_traces keep asking.
CM_TOOLS="search_graph search_code query_graph trace_path get_code_snippet get_file_outline
  get_graph_schema get_architecture compare_graphs list_projects index_status check_index_coverage
  detect_changes index_repository"
# the ones a subagent with a tools list is given: read-only, so ECC's read-only
# agents stay read-only (lib/agents.sh)
CM_AGENT_TOOLS="list_projects search_graph search_code query_graph trace_path get_code_snippet
  get_file_outline get_architecture detect_changes"

# cm_asset — "<file> <sha256>" of the release build for this machine
# (checksums.txt of the release). Windows is left out: MCP clients there can't
# start the shell wrapper.
cm_asset() {
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64)               echo "darwin-arm64.tar.gz 9bfcbe38414b47969a3e1d1c1999f5357409387c86fa3d24221b5458267660d2" ;;
    Darwin/x86_64)              echo "darwin-amd64.tar.gz ca6e64397a8ae80cec898a8205a6aa16750ac798acc05a0c3ed983837944a581" ;;
    Linux/x86_64)               echo "linux-amd64-portable.tar.gz 8c3d0341064301e78ecc84cf7348d4e2c6562a0f57448243ea560aaa34de36c1" ;;
    Linux/aarch64|Linux/arm64)  echo "linux-arm64-portable.tar.gz ed0f1f548cd79b121c401c2e9f7841c189a001af26d3768368088c24f6a53533" ;;
  esac
}

cm_home() { echo "${CODEBASE_MEMORY_INSTALL_DIR:-$HOME/.codebase-memory}"; }

# setup_code_map — the binary (unless this machine has it), the wrapper and
# the index; sets CM_STATUS for the stage row
setup_code_map() {
  if [ "$CODE_MAP" -eq 0 ]; then remove_code_map; CM_STATUS="skipped (--no-code-map)"; return 0; fi
  install_template codebase-memory.sh "$CM_WRAPPER" VERSION "$CM_VERSION"
  cm_install_binary || return 0
  cm_index
}

# cm_install_binary — fails (with CM_STATUS set) when there is no binary
cm_install_binary() {
  local dest asset file sha url
  dest="$(cm_home)/versions/$CM_VERSION"
  CM_STATUS="not installed (agents fall back to rg)"
  if [ -n "${SP_CM_NO_INSTALL:-}" ]; then return 1; fi
  [ -x "$dest/codebase-memory-mcp" ] && return 0
  asset="$(cm_asset)"
  [ -n "$asset" ] || { warn "no codebase-memory build for $(uname -s)/$(uname -m) — install it yourself"; return 1; }
  file="${asset% *}" sha="${CODEBASE_MEMORY_SHA256:-${asset#* }}"
  url="${CODEBASE_MEMORY_MIRROR:-https://github.com/DeusData/codebase-memory-mcp/releases/download/v$CM_VERSION}/codebase-memory-mcp-$file"
  fetch_release codebase-memory "$url" "$TMP_DIR/cm.tar.gz" "$sha" CODEBASE_MEMORY_MIRROR || return 1
  # unpacked next to its final place and moved in whole, so a failed run
  # never leaves half a binary for the wrapper to find
  rm -rf "$dest.sp-tmp" && mkdir -p "$dest.sp-tmp"
  tar -xzf "$TMP_DIR/cm.tar.gz" -C "$dest.sp-tmp"
  [ -x "$dest.sp-tmp/codebase-memory-mcp" ] || { rm -rf "$dest.sp-tmp"; warn "codebase-memory archive has no binary — not installed"; return 1; }
  rm -rf "$dest" && mv "$dest.sp-tmp" "$dest"
  ok "$(tilde "$dest")"
}

# cm_index — build or refresh the index (the watcher keeps it current after)
cm_index() {
  local out="$TMP_DIR/cm-index.json" counts
  if (cd "$PROJECT_DIR" && "./$CM_WRAPPER" cli --quiet index_repository "$(cm_repo_json)") > "$out" 2> "$TMP_DIR/cm-index.err" \
     && grep -q '"status":"indexed"' "$out"; then
    counts="$(perl -ne 'print "$1 nodes · $2 edges" if /"nodes":(\d+).*?"edges":(\d+)/' "$out")"
    CM_STATUS="$CM_VERSION · ${counts:-indexed}"
  else
    CM_STATUS="$CM_VERSION · not indexed"
    warn "codebase-memory could not index the project: $(cat "$out" "$TMP_DIR/cm-index.err" | grep -v '^\s*$' | tail -1)"
  fi
}

# cm_repo_json — {"repo_path": PROJECT_DIR} as JSON
cm_repo_json() { SP_P="$PROJECT_DIR" perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode({ repo_path => $ENV{SP_P} })'; }

remove_code_map() {
  rm -f "$PROJECT_DIR/$CM_WRAPPER"
}

# ---- MCP configs (lib/mcp.sh)
#
# How each client finds the wrapper, from its MCP docs:
#   VS Code, Cursor   ${workspaceFolder}; `command` must be a full path
#   Claude Code, Codex, Antigravity, Devin
#                     no project variable the others also accept (VS Code
#                     reads .mcp.json too and rejects ${CLAUDE_PROJECT_DIR}),
#                     and no documented start directory: sh walks up from
#                     wherever it starts to the wrapper
#   Gemini CLI        expands every $VAR in settings.json, so no walk-up; its
#                     project settings load from the directory it starts in
#   Copilot CLI       reads .mcp.json and .github/mcp.json, not .vscode/mcp.json
#                     (since 1.0.22), and expands only environment variables,
#                     not ${workspaceFolder} or ${userHome}: the walk-up, from
#                     the committed .github/mcp.json. The server must start in
#                     the project either way (codebase-memory takes its project
#                     from the working directory), so never the bare binary.
CM_WORKSPACE_COMMAND='${workspaceFolder}/.agents/codebase-memory'
CM_WALK_UP='d=$(pwd); until [ -x "$d/.agents/codebase-memory" ] || [ "$d" = / ]; do d=$(dirname "$d"); done; exec "$d/.agents/codebase-memory" serve'
CM_GEMINI_LAUNCH='exec .agents/codebase-memory serve'
# an entry is ours when it runs the wrapper
CM_OURS='qr{\.agents/codebase-memory}'

# cm_server COMMAND [SH_SCRIPT] — the server entry, as Perl: COMMAND serve, or
# `sh -c SH_SCRIPT` when given
cm_server() {
  local args="'serve'"
  [ -n "${2:-}" ] && args="'-c', q{$2}"
  echo "{ type => 'stdio', command => q{$1}, args => [$args] }"
}

cm_mcp() { mcp_put "$1" "$2" "$CM_NAME" "$3" "$CM_OURS"; }
cm_mcp_remove() { mcp_remove "$1" "$2" "$CM_NAME" "$CM_OURS"; }

# the instruction line in every agent's block (empty with --no-code-map)
code_map_rule() {
  [ "$CODE_MAP" -eq 1 ] || return 0
  echo "**Code map:** codebase-memory keeps a graph of this project's code (functions, calls, routes, files). For where a symbol is defined, who calls it, how code flows or what a change affects, ask it before searching: the \`$CM_NAME\` MCP tools \`search_graph\`, \`trace_path\`, \`get_code_snippet\`, \`get_architecture\`, \`detect_changes\`, with the \`project\` that \`list_projects\` shows for this folder (not listed: \`index_repository\` with this folder as \`repo_path\`). Without MCP: \`$CM_WRAPPER cli <tool> '<json>'\`, and \`$CM_WRAPPER project\` prints the name. Search with rg for text in config, docs and logs."
}

# the line subagents get in their Search section (lib/ripgrep.sh)
agent_code_map_rule() {
  [ "$CODE_MAP" -eq 1 ] || return 0
  echo "- How code works, where a symbol is defined or used, what a change affects: if \`$CM_WRAPPER\` exists, ask the code map first — the \`$CM_NAME\` MCP tools (\`search_graph\`, \`trace_path\`, \`get_code_snippet\`), or \`$CM_WRAPPER cli search_graph '{\"project\":\"<name>\",\"query\":\"<words>\"}'\` in the shell (\`$CM_WRAPPER project\` prints the name). It returns file and line ranges; read only those."
}

# ---- per agent: cm_setup_<target> / cm_teardown_<target>, run after the
# target's own setup_/teardown_ (lib/install.sh)

cm_setup_claude() {
  cm_mcp .mcp.json mcpServers "$(cm_server sh "$CM_WALK_UP")"
  # .mcp.json servers need approving: pre-approve ours and its safe tools
  # (Claude Code applies both once the folder is trusted), never a server of
  # the user's own under the same name
  [ "$JSON_SKIPPED" -eq 0 ] || return 0
  json_edit "$PROJECT_DIR/.claude/settings.json" "
    add_values(\$d, 'enabledMcpjsonServers', ['$CM_NAME']);
    add_values(\$d, 'permissions', 'allow', [$(cm_claude_tools)]);"
}

cm_claude_tools() {
  local t out=""
  for t in $CM_TOOLS; do out="$out'mcp__${CM_NAME}__$t', "; done
  echo "${out%, }"
}

cm_teardown_claude() {
  cm_mcp_remove .mcp.json mcpServers
  # a server left under our name is the user's own: keep its approvals
  if ! mcp_has .mcp.json mcpServers "$CM_NAME" && [ -f "$PROJECT_DIR/.claude/settings.json" ]; then
    json_edit "$PROJECT_DIR/.claude/settings.json" "
      drop_values(\$d, 'enabledMcpjsonServers', ['$CM_NAME']);
      drop_values(\$d, 'permissions', 'allow', [$(cm_claude_tools)]);"
  fi
  rmdir "$PROJECT_DIR/.claude" 2>/dev/null || true
}

cm_setup_codex() {
  codex_mcp_put "$CM_NAME" "$CM_WALK_UP" "codebase-memory code map, managed by the Superpowers bootstrap (Codex applies it in trusted projects)"
}
cm_teardown_codex() { codex_mcp_remove "$CM_NAME"; }

# VS Code: the workspace MCP config, and servers start on their own (the
# documented default, kept even where a user setting says otherwise). Copilot
# CLI: .github/mcp.json, the committed config it shares with the team, exposing
# only the tools Claude Code pre-approves (Copilot CLI runs tools without asking
# once the folder is trusted). The cloud agent takes its MCP servers from the
# repository settings on GitHub.com instead.
cm_setup_copilot() {
  cm_mcp .vscode/mcp.json servers "$(cm_server "$CM_WORKSPACE_COMMAND")"
  json_edit "$PROJECT_DIR/.vscode/settings.json" "\$d->{'chat.mcp.autostart'} //= 'newAndOutdated';"
  cm_mcp .github/mcp.json mcpServers "{ type => 'stdio', command => 'sh', args => ['-c', q{$CM_WALK_UP}],
    tools => [$(for t in $CM_TOOLS; do printf "'%s', " "$t"; done)] }"
}
cm_teardown_copilot() {
  cm_mcp_remove .vscode/mcp.json servers
  cm_mcp_remove .github/mcp.json mcpServers
  rmdir "$PROJECT_DIR/.github" 2>/dev/null || true
}

cm_setup_cursor() { cm_mcp .cursor/mcp.json mcpServers "$(cm_server "$CM_WORKSPACE_COMMAND")"; }
cm_teardown_cursor() {
  cm_mcp_remove .cursor/mcp.json mcpServers
  rmdir "$PROJECT_DIR/.cursor" 2>/dev/null || true
}

cm_setup_gemini() { cm_mcp .gemini/settings.json mcpServers "$(cm_server sh "$CM_GEMINI_LAUNCH")"; }
cm_teardown_gemini() {
  cm_mcp_remove .gemini/settings.json mcpServers
  rmdir "$PROJECT_DIR/.gemini" 2>/dev/null || true
}

cm_setup_antigravity() { cm_mcp .agents/mcp_config.json mcpServers "$(cm_server sh "$CM_WALK_UP")"; }
cm_teardown_antigravity() { cm_mcp_remove .agents/mcp_config.json mcpServers; }

# the committed project MCP file (.devin/mcp_config.local.json is personal)
cm_setup_devin() { cm_mcp .devin/mcp_config.json mcpServers "$(cm_server sh "$CM_WALK_UP")"; }
cm_teardown_devin() {
  cm_mcp_remove .devin/mcp_config.json mcpServers
  rmdir "$PROJECT_DIR/.devin" 2>/dev/null || true
}

# code_map_target T — the target's MCP entry, or its removal with --no-code-map
code_map_target() {
  if [ "$CODE_MAP" -eq 1 ]; then "cm_setup_$1"; else "cm_teardown_$1"; fi
}
