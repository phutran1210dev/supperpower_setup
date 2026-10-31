# Devin Desktop (Windsurf before v3.9): reads .agents/skills natively and
# .devin/rules; an always-on rule carries the bootstrap. Devin also imports the
# legacy .windsurf/rules, so the rule earlier versions wrote there is removed
# rather than kept alongside (it would load twice).

LEGACY_WINDSURF_RULE=".windsurf/rules/superpowers.md"

setup_devin() {
  write_rule .devin/rules/superpowers.md 'trigger: always_on' block-full.md
  remove_legacy_windsurf_rule
}

remove_legacy_windsurf_rule() {
  rm -f "$PROJECT_DIR/$LEGACY_WINDSURF_RULE"
  rmdir "$PROJECT_DIR/.windsurf/rules" "$PROJECT_DIR/.windsurf" 2>/dev/null || true
}

teardown_devin() {
  rm -f "$PROJECT_DIR/.devin/rules/superpowers.md"
  rmdir "$PROJECT_DIR/.devin/rules" "$PROJECT_DIR/.devin" 2>/dev/null || true
  remove_legacy_windsurf_rule
}
