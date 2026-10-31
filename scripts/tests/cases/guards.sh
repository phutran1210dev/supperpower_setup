# The secret-file and search guard hooks, run directly against the shared install.

test_guard_paths() {
  local g="$P/.claude/hooks/secret-guard.pl"
  : > "$P/.env"; : > "$P/.env.example"; : > "$P/src/server.key"
  check "Read .env" blocked "$g" claude '{"tool_name":"Read","tool_input":{"file_path":"'"$P"'/.env"}}'
  check "Read .env.local (needn't exist)" blocked "$g" claude '{"tool_name":"Read","tool_input":{"file_path":"config/.env.local"}}'
  check "Read *.key" blocked "$g" claude '{"tool_name":"Read","tool_input":{"file_path":"src/server.key"}}'
  check "Read ~/.ssh/id_rsa" blocked "$g" claude '{"tool_name":"Read","tool_input":{"file_path":"'"$HOME"'/.ssh/id_rsa"}}'
  check "Read .env.example is allowed" allowed "$g" claude '{"tool_name":"Read","tool_input":{"file_path":".env.example"}}'
  check "Read id_rsa.pub is allowed" allowed "$g" claude '{"tool_name":"Read","tool_input":{"file_path":"id_rsa.pub"}}'
  check "Read src/app.ts is allowed" allowed "$g" claude '{"tool_name":"Read","tool_input":{"file_path":"src/app.ts"}}'
  check "Grep for .env in src is allowed" allowed "$g" claude '{"tool_name":"Grep","tool_input":{"pattern":"\\.env","path":"src"}}'
  check "Grep inside .env is blocked" blocked "$g" claude '{"tool_name":"Grep","tool_input":{"pattern":"KEY","path":".env"}}'
  check "Write code mentioning .env is allowed" allowed "$g" claude '{"tool_name":"Write","tool_input":{"file_path":"src/a.js","content":"read(\".env\")"}}'
  check "Glob for .env* is blocked" blocked "$g" claude '{"tool_name":"Glob","tool_input":{"pattern":"**/.env*"}}'
}

test_guard_commands() {
  local g="$P/.claude/hooks/secret-guard.pl" cwd="\"cwd\":\"$P\""
  check "cat .env" blocked "$g" claude '{"tool_name":"Bash","tool_input":{"command":"cat .env"},'"$cwd"'}'
  check "cp .env elsewhere" blocked "$g" claude '{"tool_name":"Bash","tool_input":{"command":"cp .env /tmp/x"},'"$cwd"'}'
  check "cat .env* (glob)" blocked "$g" claude '{"tool_name":"Bash","tool_input":{"command":"cat .env*"},'"$cwd"'}'
  check "head ~/.ssh/id_rsa" blocked "$g" claude '{"tool_name":"Bash","tool_input":{"command":"head ~/.ssh/id_rsa"},'"$cwd"'}'
  check "source .env && npm test" blocked "$g" claude '{"tool_name":"Bash","tool_input":{"command":"source .env && npm test"},'"$cwd"'}'
  check "cat \$PWD/src/server.key" blocked "$g" claude '{"tool_name":"Bash","tool_input":{"command":"cat '"$P"'/src/server.key"},'"$cwd"'}'
  # regression: the words of a command only count when they name a real file
  check "grep '\\.env' src is allowed" allowed "$g" claude '{"tool_name":"Bash","tool_input":{"command":"grep -rn '\''\\\\.env'\'' src"},'"$cwd"'}'
  check "grep -n .env README is allowed" allowed "$g" claude '{"tool_name":"Bash","tool_input":{"command":"grep -n .env.local README.md"},'"$cwd"'}'
  check "echo .env >> .gitignore is allowed" allowed "$g" claude '{"tool_name":"Bash","tool_input":{"command":"echo .envrc >> .gitignore"},'"$cwd"'}'
  check "cat .env.example is allowed" allowed "$g" claude '{"tool_name":"Bash","tool_input":{"command":"cat .env.example"},'"$cwd"'}'
  check "npm test is allowed" allowed "$g" claude '{"tool_name":"Bash","tool_input":{"command":"npm test"},'"$cwd"'}'
  check "cat .env from another cwd without one is allowed" allowed "$g" claude '{"tool_name":"Bash","tool_input":{"command":"cat .env"},"cwd":"'"$P"'/src"}'
}

test_guard_secretsignore() {
  local g="$P/.claude/hooks/secret-guard.pl"
  printf '# team rules\nprivate/**\n!config/dev.key\n' > "$P/.secretsignore"
  check ".secretsignore deny" blocked "$g" claude '{"tool_name":"Read","tool_input":{"file_path":"private/notes.txt"}}'
  check ".secretsignore allow" allowed "$g" claude '{"tool_name":"Read","tool_input":{"file_path":"config/dev.key"}}'
  rm -f "$P/.secretsignore"
}

test_guard_formats() {
  # Copilot: toolArgs as a JSON string; permissionDecision on stdout + exit 2
  guard "$P/.github/hooks/secret-guard.pl" copilot '{"toolName":"view","toolArgs":"{\"path\":\".env\"}"}'
  check "Copilot: exit 2" test "$GUARD_RC" = 2
  check "Copilot: permissionDecision deny" json_has <(echo "$GUARD_OUT") '$d->{permissionDecision} eq "deny" && $d->{permissionDecisionReason}'
  check "Copilot: allowed file" allowed "$P/.github/hooks/secret-guard.pl" copilot '{"toolName":"view","toolArgs":{"path":"src/a.ts"}}'
  # Cursor: top-level file_path / command; permission JSON + exit 2
  guard "$P/.cursor/hooks/secret-guard.pl" cursor '{"hook_event_name":"beforeReadFile","file_path":"'"$P"'/.env","content":"A=1"}'
  check "Cursor read: exit 2" test "$GUARD_RC" = 2
  check "Cursor read: permission deny" json_has <(echo "$GUARD_OUT") '$d->{permission} eq "deny" && $d->{agent_message}'
  check "Cursor shell: cat .env" blocked "$P/.cursor/hooks/secret-guard.pl" cursor '{"hook_event_name":"beforeShellExecution","command":"cat .env","cwd":"'"$P"'"}'
  check "Cursor read: source file" allowed "$P/.cursor/hooks/secret-guard.pl" cursor '{"hook_event_name":"beforeReadFile","file_path":"'"$P"'/src/a.ts","content":"x = process.env.KEY"}'
  # Codex: Claude-style input, exit 2 + stderr
  check "Codex: cat .env" blocked "$P/.codex/hooks/secret-guard.pl" codex '{"tool_name":"Bash","tool_input":{"command":"cat .env"},"cwd":"'"$P"'"}'
  check "Codex: ls" allowed "$P/.codex/hooks/secret-guard.pl" codex '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"cwd":"'"$P"'"}'
  # Antigravity: toolCall; decision JSON on stdout, exit 0
  guard "$P/.agents/hooks/secret-guard.pl" antigravity '{"toolCall":{"name":"view_file","args":{"AbsolutePath":"'"$P"'/.env"}},"workspacePaths":["'"$P"'"]}'
  check "Antigravity view_file: exit 0" test "$GUARD_RC" = 0
  check "Antigravity view_file: decision deny" json_has <(echo "$GUARD_OUT") '$d->{decision} eq "deny" && $d->{reason}'
  guard "$P/.agents/hooks/secret-guard.pl" antigravity '{"toolCall":{"name":"run_command","args":{"CommandLine":"cat .env","Cwd":"'"$P"'"}}}'
  check "Antigravity run_command: decision deny" json_has <(echo "$GUARD_OUT") '$d->{decision} eq "deny"'
  check "Antigravity: allowed command" allowed "$P/.agents/hooks/secret-guard.pl" antigravity '{"toolCall":{"name":"run_command","args":{"CommandLine":"npm test","Cwd":"'"$P"'"}}}'
  # the configured commands, from a subdirectory, as the agent would run them
  local cmd
  cmd="$(perl -MJSON::PP -e 'local $/; print JSON::PP->new->decode(<STDIN>)->{hooks}{PreToolUse}[0]{hooks}[0]{command}' < "$P/.codex/hooks.json")"
  echo '{"tool_name":"Bash","tool_input":{"command":"cat ../.env"},"cwd":"'"$P"'/src"}' | (cd "$P/src" && sh -c "$cmd") >/dev/null 2>&1
  check "Codex: configured command blocks from a subdirectory" test $? = 2
  cmd="$(perl -MJSON::PP -e 'local $/; print JSON::PP->new->decode(<STDIN>)->{"superpowers-secret-guard"}{PreToolUse}[0]{hooks}[0]{command}' < "$P/.agents/hooks.json")"
  GUARD_OUT="$(echo '{"toolCall":{"name":"view_file","args":{"AbsolutePath":"'"$P"'/.env"}}}' | (cd "$P/src" && sh -c "$cmd"))"
  check "Antigravity: configured command blocks from a subdirectory" json_has <(echo "$GUARD_OUT") '$d->{decision} eq "deny"'
  # a missing guard script must not block every tool call
  cmd="$(perl -MJSON::PP -e 'local $/; print JSON::PP->new->decode(<STDIN>)->{hooks}{PreToolUse}[0]{hooks}[0]{command}' < "$P/.codex/hooks.json")"
  echo '{}' | (cd "$WORK" && sh -c "$cmd") >/dev/null 2>&1
  check "Codex: no guard script → allowed" test $? = 0
}

test_search_guard() {
  local g="$P/.claude/hooks/search-guard.pl" c
  for f in CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md .cursor/rules/superpowers.mdc \
           .agents/rules/superpowers.md .devin/rules/superpowers.md; do
    check "$f tells the agent to use rg" contains "$P/$f" '`rg --files -g'
  done
  check "Claude: search guard on Bash" json_has "$P/.claude/settings.json" 'grep { $_->{matcher} && $_->{matcher} eq "Bash" && $_->{hooks}[0]{command} =~ /search-guard.pl" claude$/ } @{ $d->{hooks}{PreToolUse} }'
  check "Codex: search guard" json_has "$P/.codex/hooks.json" 'grep { $_->{hooks}[0]{command} =~ /search-guard/ } @{ $d->{hooks}{PreToolUse} }'
  check "Cursor: search guard on shell" json_has "$P/.cursor/hooks.json" 'grep { $_->{command} eq "perl .cursor/hooks/search-guard.pl cursor" } @{ $d->{hooks}{beforeShellExecution} }'
  check "Antigravity: search guard on run_command" json_has "$P/.agents/hooks.json" '$d->{"superpowers-search-guard"}{PreToolUse}[0]{matcher} eq "run_command"'
  check "Copilot: search guard config" contains "$P/.github/hooks/superpowers-search-guard.json" "search-guard.pl copilot"
  for c in 'grep -rn TODO .' 'grep -R foo src' 'egrep --recursive x .' 'cd src && grep -ri "a b" .' \
           "find . -name '*.ts'" 'find src -type f -iname x' 'sudo grep -r x /etc' '/usr/bin/grep -r x .'; do
    check "denies: $c" blocked "$g" claude "$(perl -MJSON::PP -e 'print encode_json({tool_name => "Bash", tool_input => {command => $ARGV[0]}})' "$c")"
  done
  for c in 'ps aux | grep node' 'git log | grep -i fix' 'git grep -n foo' 'grep foo README.md' 'rg -n foo src' \
           'find . -type f -mtime -1' 'find . -maxdepth 1 -type d' 'echo grep -r'; do
    check "allows: $c" allowed "$g" claude "$(perl -MJSON::PP -e 'print encode_json({tool_name => "Bash", tool_input => {command => $ARGV[0]}})' "$c")"
  done
  check "allows non-shell tools" allowed "$g" claude '{"tool_name":"Grep","tool_input":{"pattern":"x","path":"."}}'
  guard "$g" claude '{"tool_name":"Bash","tool_input":{"command":"grep -r x ."}}'
  check "reason names the rg command" sh -c "printf '%s' \"\$(printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -r x .\"}}' | perl '$g' claude 2>&1)\" | grep -q 'rg PATTERN'"
  guard "$P/.cursor/hooks/search-guard.pl" cursor '{"hook_event_name":"beforeShellExecution","command":"grep -r x .","cwd":"'"$P"'"}'
  check "Cursor: permission deny" json_has <(echo "$GUARD_OUT") '$d->{permission} eq "deny"'
  guard "$P/.agents/hooks/search-guard.pl" antigravity '{"toolCall":{"name":"run_command","args":{"CommandLine":"find . -name x","Cwd":"'"$P"'"}}}'
  check "Antigravity: decision deny, exit 0" json_has <(echo "$GUARD_OUT") '$d->{decision} eq "deny"'
  check "Codex: deny" blocked "$P/.codex/hooks/search-guard.pl" codex '{"tool_name":"Bash","tool_input":{"command":"grep -rn x ."}}'
  guard "$P/.github/hooks/search-guard.pl" copilot '{"toolName":"bash","toolArgs":"{\"command\":\"grep -r x .\"}"}'
  check "Copilot: permissionDecision deny" json_has <(echo "$GUARD_OUT") '$d->{permissionDecision} eq "deny"'
  # no rg anywhere: nothing to steer to, so nothing is blocked
  GUARD_OUT="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"grep -r x ."}}' | PATH="$NO_RG_PATH" perl "$g" claude 2>/dev/null)"
  check "allows grep -r when no rg exists" test $? = 0
}

test_no_secret_guard() {
  local d="$WORK/noguard"
  rm -rf "$d" && bootstrap "$d"
  check "re-run with --no-secret-guard" bootstrap "$d" --no-secret-guard
  local f
  for f in .claude/hooks/secret-guard.pl .github/hooks/secret-guard.pl .cursor/hooks/secret-guard.pl .cursor/cli.json \
           .codex/hooks/secret-guard.pl .agents/hooks/secret-guard.pl; do
    check_not "removes $f" test -e "$d/$f"
  done
  check "Claude: no secret guard, no deny rules" json_has "$d/.claude/settings.json" '!grep({ $_->{hooks}[0]{command} =~ /secret-guard/ } @{ $d->{hooks}{PreToolUse} }) && !$d->{permissions}{deny}'
  check "Codex: no secret guard hook" json_has "$d/.codex/hooks.json" '!grep { $_->{hooks}[0]{command} =~ /secret-guard/ } @{ $d->{hooks}{PreToolUse} }'
  check "Antigravity: no guard hook" json_has "$d/.agents/hooks.json" '!$d->{"superpowers-secret-guard"}'
  check "Cursor: no secret guard hooks" json_has "$d/.cursor/hooks.json" '!$d->{hooks}{beforeReadFile} && !grep { $_->{command} =~ /secret-guard/ } @{ $d->{hooks}{beforeShellExecution} }'
}
