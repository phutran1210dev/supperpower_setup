# Gemini CLI: reads .agents/skills natively; GEMINI.md @-imports the bootstrap
# and the Gemini tool mapping, exactly like upstream's GEMINI.md. Gemini
# activates skills itself rather than as slash commands, so /release-audit is
# a custom command (.gemini/commands/*.toml, {{args}} = what follows it).

GEMINI_AUDIT_COMMAND=".gemini/commands/release-audit.toml"

setup_gemini() {
  {
    echo "$BEGIN_MARK"
    echo "@./.agents/skills/using-superpowers/SKILL.md"
    echo "@./.agents/skills/using-superpowers/references/gemini-tools.md"
    search_rule
    code_map_rule
    echo "$END_MARK"
  } > "$TMP_DIR/block-gemini.md"
  upsert_block "$PROJECT_DIR/GEMINI.md" "$TMP_DIR/block-gemini.md"
  if ! is_locked release-audit; then
    remove_gemini_audit_command
  elif [ -e "$PROJECT_DIR/$GEMINI_AUDIT_COMMAND" ] && ! is_gemini_audit_command && [ "$FORCE" -ne 1 ]; then
    warn "$GEMINI_AUDIT_COMMAND already exists and is not from the bootstrap — skipped (use --force)"
  else
    install_template gemini-release-audit.toml "$GEMINI_AUDIT_COMMAND"
  fi
}

# is_gemini_audit_command — the command file is ours: it starts with the
# template's first line
is_gemini_audit_command() {
  [ "$(head -1 "$PROJECT_DIR/$GEMINI_AUDIT_COMMAND" 2>/dev/null)" = "$(head -1 "$TEMPLATES_DIR/gemini-release-audit.toml")" ]
}

remove_gemini_audit_command() {
  is_gemini_audit_command || return 0
  rm -f "$PROJECT_DIR/$GEMINI_AUDIT_COMMAND"
  rmdir "$PROJECT_DIR/.gemini/commands" "$PROJECT_DIR/.gemini" 2>/dev/null || true
}

teardown_gemini() {
  remove_block "$PROJECT_DIR/GEMINI.md"
  remove_gemini_audit_command
}
