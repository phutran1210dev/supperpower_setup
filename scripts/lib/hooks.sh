# Hook scripts shared by the agents that support hooks (templates in
# scripts/templates/), plus the native deny rules that back up the guard.

# shared hook an earlier version of the bootstrap wrote; removed on install/uninstall
LEGACY_SHARED_HOOK=".agents/hooks/superpowers-session-start.sh"

# Read() deny rules for agents with a project permissions file (Claude Code,
# Cursor CLI). A second layer under the guard hook: they hold even where hooks
# don't run (untrusted folder, no perl). Kept to unambiguous secrets, because
# deny wins over allow and .secretsignore can't override them.
SECRET_READ_GLOBS=('**/.env' '**/.env.local' '**/.env.*.local' '**/.env.production'
  '**/*.pem' '**/*.key' '**/*.p12' '**/id_rsa' '**/id_ed25519')

# secret_read_rules — the rules as a Perl list, for json_edit
secret_read_rules() {
  printf "'Read(%s)', " "${SECRET_READ_GLOBS[@]}"
}

# write_session_hook REL_PATH claude|cursor|antigravity — project-local
# replacement for the Superpowers plugin's session-start hook: injects the
# using-superpowers skill. Each harness reads a different output field, so the
# caller names its format (Codex reads Claude Code's).
write_session_hook() {
  install_template session-start.sh "$1" FORMAT "$2"
  remove_legacy_shared_hook
}

remove_legacy_shared_hook() {
  rm -f "$PROJECT_DIR/$LEGACY_SHARED_HOOK"
  rmdir "$(dirname "$PROJECT_DIR/$LEGACY_SHARED_HOOK")" 2>/dev/null || true
}

# write_secret_guard REL_PATH — a pre-tool-use hook that denies tool calls
# touching secret files. One script for every harness: the caller passes the
# format as its argument (see the template).
write_secret_guard() {
  install_template secret-guard.pl "$1"
}

# write_search_guard REL_PATH — a pre-tool-use hook on shell commands that
# denies grep -r / find -name with the rg equivalent (lib/ripgrep.sh). Same
# calling convention as the secret guard.
write_search_guard() {
  install_template search-guard.pl "$1"
}

# root_hook_command INTERPRETER REL_PATH [ARG] — a hook command for agents that
# run hooks in the session's working directory, which may be a subdirectory
# (Codex, Antigravity): resolves the project root through git, else the
# working directory. Does nothing if the script is missing, rather than failing
# every tool call.
root_hook_command() {
  printf 'f="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/%s"; [ ! -f "$f" ] || %s "$f"%s' \
    "$2" "$1" "${3:+ $3}"
}
