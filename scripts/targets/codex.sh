# Codex: reads .agents/skills natively; AGENTS.md block with the Codex tool
# mapping (codex-tools.md); SessionStart hook, secret-file and search guards
# (.codex/hooks.json). Agents (.codex/agents/*.toml): lib/agents.sh.
#
# Codex runs project hooks only once the project is trusted and each hook has
# been approved in /hooks (re-approved whenever it changes).

CODEX_HOOK=".codex/hooks/superpowers-session-start.sh"
CODEX_GUARD=".codex/hooks/secret-guard.pl"
CODEX_SEARCH=".codex/hooks/search-guard.pl"

codex_hooks_clean() {
  echo "drop_entries(\$d, 'hooks', 'SessionStart', qr{superpowers-session-start});"
  echo "drop_entries(\$d, 'hooks', 'PreToolUse', qr{secret-guard|search-guard});"
}

setup_codex() {
  upsert_block "$PROJECT_DIR/AGENTS.md" "$TMP_DIR/block-short.md"
  # Codex reads Claude Code's SessionStart output format
  write_session_hook "$CODEX_HOOK" claude
  local edit cmd
  cmd="$(root_hook_command bash "$CODEX_HOOK")"
  edit="$(codex_hooks_clean)
    add_entry(\$d, 'hooks', 'SessionStart', { matcher => 'startup|resume|clear|compact', hooks => [{ type => 'command',
      command => q{$cmd}, statusMessage => 'Loading Superpowers' }] });"
  if [ "$SECRET_GUARD" -eq 1 ]; then
    # Codex has no separate file-read tool: reads go through the shell
    write_secret_guard "$CODEX_GUARD"
    cmd="$(root_hook_command perl "$CODEX_GUARD" codex)"
    edit="$edit
      add_entry(\$d, 'hooks', 'PreToolUse', { matcher => 'Bash', hooks => [{ type => 'command',
        command => q{$cmd} }] });"
  else
    rm -f "$PROJECT_DIR/$CODEX_GUARD"
  fi
  if [ "$RIPGREP" -eq 1 ]; then
    write_search_guard "$CODEX_SEARCH"
    cmd="$(root_hook_command perl "$CODEX_SEARCH" codex)"
    edit="$edit
      add_entry(\$d, 'hooks', 'PreToolUse', { matcher => 'Bash', hooks => [{ type => 'command',
        command => q{$cmd} }] });"
  else
    rm -f "$PROJECT_DIR/$CODEX_SEARCH"
  fi
  json_edit "$PROJECT_DIR/.codex/hooks.json" "$edit"
}

teardown_codex() {
  unrecommend openai.chatgpt
  remove_block "$PROJECT_DIR/AGENTS.md"
  rm -f "$PROJECT_DIR/$CODEX_HOOK" "$PROJECT_DIR/$CODEX_GUARD" "$PROJECT_DIR/$CODEX_SEARCH"
  if [ -f "$PROJECT_DIR/.codex/hooks.json" ]; then
    json_edit "$PROJECT_DIR/.codex/hooks.json" "$(codex_hooks_clean)"
  fi
  rmdir "$PROJECT_DIR/.codex/hooks" "$PROJECT_DIR/.codex" 2>/dev/null || true
}
