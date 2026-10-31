# Antigravity (IDE and agy CLI): reads workspace skills and rules from
# .agents/; the always-on rule carries the bootstrap plus the Antigravity tool
# mapping. SessionStart hook, secret-file and search guards in
# .agents/hooks.json, whose entries are named, so ours are replaced by name.
# Agents (.agents/agents): lib/agents.sh.

AGY_HOOK=".agents/hooks/session-start.sh"
AGY_GUARD=".agents/hooks/secret-guard.pl"
AGY_SEARCH=".agents/hooks/search-guard.pl"

agy_hooks_clean() {
  echo "delete_key(\$d, 'superpowers-session-start');"
  echo "delete_key(\$d, 'superpowers-secret-guard');"
  echo "delete_key(\$d, 'superpowers-search-guard');"
}

setup_antigravity() {
  write_rule .agents/rules/superpowers.md 'trigger: always_on' block-antigravity.md
  write_session_hook "$AGY_HOOK" antigravity
  local edit cmd
  cmd="$(root_hook_command bash "$AGY_HOOK")"
  edit="$(agy_hooks_clean)
    \$d->{'superpowers-session-start'} = { SessionStart => [{ type => 'command', command => q{$cmd} }] };"
  if [ "$SECRET_GUARD" -eq 1 ]; then
    # view_file reads files, run_command runs shell commands
    write_secret_guard "$AGY_GUARD"
    cmd="$(root_hook_command perl "$AGY_GUARD" antigravity)"
    edit="$edit
      \$d->{'superpowers-secret-guard'} = { PreToolUse => [{ matcher => 'view_file|run_command',
        hooks => [{ type => 'command', command => q{$cmd} }] }] };"
  else
    rm -f "$PROJECT_DIR/$AGY_GUARD"
  fi
  if [ "$RIPGREP" -eq 1 ]; then
    write_search_guard "$AGY_SEARCH"
    cmd="$(root_hook_command perl "$AGY_SEARCH" antigravity)"
    edit="$edit
      \$d->{'superpowers-search-guard'} = { PreToolUse => [{ matcher => 'run_command',
        hooks => [{ type => 'command', command => q{$cmd} }] }] };"
  else
    rm -f "$PROJECT_DIR/$AGY_SEARCH"
  fi
  json_edit "$PROJECT_DIR/.agents/hooks.json" "$edit"
}

teardown_antigravity() {
  rm -f "$PROJECT_DIR/.agents/rules/superpowers.md" "$PROJECT_DIR/$AGY_HOOK" "$PROJECT_DIR/$AGY_GUARD" \
    "$PROJECT_DIR/$AGY_SEARCH"
  if [ -f "$PROJECT_DIR/.agents/hooks.json" ]; then
    json_edit "$PROJECT_DIR/.agents/hooks.json" "$(agy_hooks_clean)"
  fi
  rmdir "$PROJECT_DIR/.agents/rules" "$PROJECT_DIR/.agents/hooks" 2>/dev/null || true
}
