# The supported agents: names, detection, and the VS Code extension
# recommendations. Each agent's setup_<name> / teardown_<name> lives in
# scripts/targets/<name>.sh; its code map entry in lib/codemap.sh.

ALL_TARGETS="claude,codex,copilot,cursor,gemini,antigravity,devin"

target_list() { echo "$ALL_TARGETS" | tr ',' ' '; }
has_target() { case ",$TARGETS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
any_target() { local t; for t in "$@"; do has_target "$t" && return 0; done; return 1; }

# target_setup NAME / target_teardown NAME — everything of ours for one agent
target_setup() { "setup_$1"; code_map_target "$1"; }
target_teardown() { "teardown_$1"; "cm_teardown_$1"; }

# normalize_targets LIST — old names → current ones (Windsurf became Devin
# Desktop), so --targets windsurf and older locks keep working
normalize_targets() { echo "$1" | tr ',' '\n' | sed 's/^windsurf$/devin/' | paste -sd ',' -; }

target_label() {
  case "$1" in
    claude)      echo "Claude Code" ;;
    codex)       echo "Codex (CLI / IDE)" ;;
    copilot)     echo "GitHub Copilot (VS Code / CLI)" ;;
    cursor)      echo "Cursor" ;;
    gemini)      echo "Gemini CLI" ;;
    antigravity) echo "Antigravity" ;;
    devin)       echo "Devin Desktop (ex-Windsurf)" ;;
  esac
}

# target_summary NAME — what a tool's pipeline stage set up
target_summary() {
  local guards=" · guards"
  [ "$SECRET_GUARD" -eq 0 ] && [ "$RIPGREP" -eq 0 ] && guards=""
  case "$1" in
    claude)      echo "skills · hooks$guards · CLAUDE.md" ;;
    codex)       echo "hooks$guards · AGENTS.md" ;;
    copilot)     echo "skills$guards · instructions" ;;
    cursor)      echo "hooks$guards · rules" ;;
    gemini)      if is_locked release-audit; then echo "GEMINI.md · /release-audit"; else echo "GEMINI.md"; fi ;;
    antigravity) echo "hooks$guards · rules" ;;
    devin)       echo ".devin/rules" ;;
  esac
}

# Best-effort guess of which agents are installed on this machine.
target_detected() {
  case "$1" in
    claude)      have claude || [ -d "$HOME/.claude" ] ;;
    codex)       have codex || [ -d "$HOME/.codex" ] ;;
    copilot)     have copilot || ls "$HOME/.vscode/extensions" 2>/dev/null | grep -qi 'github.copilot' ;;
    cursor)      have cursor || [ -d "/Applications/Cursor.app" ] || [ -d "$HOME/.cursor" ] ;;
    gemini)      have gemini || [ -d "$HOME/.gemini" ] ;;
    antigravity) have agy || [ -d "/Applications/Antigravity.app" ] || [ -d "$HOME/.gemini/antigravity" ] ;;
    devin)       have devin || have windsurf || [ -d "/Applications/Devin.app" ] || [ -d "/Applications/Windsurf.app" ] \
                   || [ -d "$HOME/.devin" ] || [ -d "$HOME/.codeium/windsurf" ] ;;
  esac
}

# Agents the project already has (from the lock), so a teammate re-running the
# picker keeps them even when that tool isn't installed on their machine.
# (LOCK_FILE isn't set yet: the picker runs first)
installed_targets() {
  normalize_targets "$(lock_get targets "$PROJECT_DIR/$LOCK_REL")" | tr ',' ' '
}
is_installed_target() { case " $(installed_targets) " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

setup_vscode_extensions() {
  local recs=""
  has_target claude  && recs="$recs\"anthropic.claude-code\","
  has_target codex   && recs="$recs\"openai.chatgpt\","
  has_target copilot && recs="$recs\"GitHub.copilot-chat\","
  [ -n "$recs" ] || return 1
  json_edit "$PROJECT_DIR/.vscode/extensions.json" "add_values(\$d, 'recommendations', [${recs%,}]);"
}

# unrecommend EXTENSION_ID — drop a recommendation when its agent is deselected
# (uninstall leaves .vscode/ alone)
unrecommend() {
  [ "$UNINSTALL" -eq 1 ] && return 0
  [ -f "$PROJECT_DIR/.vscode/extensions.json" ] || return 0
  json_edit "$PROJECT_DIR/.vscode/extensions.json" "drop_values(\$d, 'recommendations', ['$1']);"
}
