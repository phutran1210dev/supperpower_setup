# Install, re-run, deselect and uninstall; the shared full install ($P) the
# guard tests read.

test_install_all() {
  rm -rf "$P" && mkdir -p "$P/src"
  git -C "$P" init -q
  check "bootstrap succeeds" bootstrap "$P"
  local f
  for f in .agents/superpowers.lock .agents/skills/brainstorming/SKILL.md \
           .claude/skills/brainstorming/SKILL.md .github/skills/brainstorming/SKILL.md \
           CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md \
           .claude/hooks/secret-guard.pl .github/hooks/secret-guard.pl .cursor/hooks/secret-guard.pl \
           .codex/hooks/secret-guard.pl .agents/hooks/secret-guard.pl \
           .codex/hooks/superpowers-session-start.sh .agents/hooks/session-start.sh \
           .cursor/rules/superpowers.mdc .agents/rules/superpowers.md .devin/rules/superpowers.md \
           .claude/agents/planner.md .github/agents/planner.md .codex/agents/planner.toml .agents/agents/planner.md \
           .gemini/agents/planner.md .cursor/agents/planner.md; do
    check "creates $f" test -f "$P/$f"
  done
  for f in .claude/settings.json .codex/hooks.json .agents/hooks.json .cursor/hooks.json .cursor/cli.json \
           .github/hooks/superpowers-secret-guard.json .vscode/extensions.json; do
    check "$f is valid JSON" json_ok "$P/$f"
  done
  check "skill cross-references lose the plugin namespace" contains "$P/.agents/skills/brainstorming/SKILL.md" "use writing-plans."
  check "Claude: SessionStart hook" json_has "$P/.claude/settings.json" '$d->{hooks}{SessionStart}[0]{hooks}[0]{command} =~ /superpowers-session-start/'
  check "Claude: guard hook" json_has "$P/.claude/settings.json" '$d->{hooks}{PreToolUse}[0]{hooks}[0]{command} =~ /secret-guard.pl" claude$/'
  check "Claude: deny rules" json_has "$P/.claude/settings.json" 'grep { $_ eq "Read(**/.env)" } @{ $d->{permissions}{deny} }'
  check "Cursor: guard on reads" json_has "$P/.cursor/hooks.json" '$d->{hooks}{beforeReadFile}[0]{command} eq "perl .cursor/hooks/secret-guard.pl cursor"'
  check "Cursor: guard on shell" json_has "$P/.cursor/hooks.json" '$d->{hooks}{beforeShellExecution}[0]{command} =~ /secret-guard/'
  check "Cursor: CLI deny rules" json_has "$P/.cursor/cli.json" '@{ $d->{permissions}{deny} } == 9'
  check "Codex: guard on Bash" json_has "$P/.codex/hooks.json" '$d->{hooks}{PreToolUse}[0]{matcher} eq "Bash"'
  check "Codex: SessionStart" json_has "$P/.codex/hooks.json" '$d->{hooks}{SessionStart}[0]{matcher} =~ /startup/'
  check "Antigravity: guard on view_file/run_command" json_has "$P/.agents/hooks.json" '$d->{"superpowers-secret-guard"}{PreToolUse}[0]{matcher} eq "view_file|run_command"'
  check "Antigravity: SessionStart" json_has "$P/.agents/hooks.json" '$d->{"superpowers-session-start"}{SessionStart}[0]{command} =~ /session-start.sh/'
  check "Copilot: guard passes its format" contains "$P/.github/hooks/superpowers-secret-guard.json" "secret-guard.pl copilot"
  check "lock records targets" contains "$P/.agents/superpowers.lock" "targets: claude,codex,copilot,cursor,gemini,antigravity,devin"
  check "lock records options" contains "$P/.agents/superpowers.lock" "options: --ecc-ref"
  check "Claude agent kept as-is" contains "$P/.claude/agents/planner.md" "model: opus"
  # each platform gets the Claude tools under its own names, and no Claude model id
  # each platform gets the Claude tools under its own names; MCP tools in its
  # own form (none on Antigravity, where an unknown name hangs the subagent)
  check "Copilot agent: tool aliases + code map" contains "$P/.github/agents/planner.md" 'tools: ["read", "search", "codebase-memory/list_projects", "codebase-memory/search_graph"'
  check "Copilot agent: write tools map to edit" contains "$P/.github/agents/architect.md" 'tools: ["read", "edit", "search", "codebase-memory/'
  check "Antigravity agent: its tool names, no MCP" grep -qxF 'tools: ["view_file", "list_dir", "grep_search", "find_by_name"]' "$P/.agents/agents/planner.md"
  check "Antigravity agent: write tools" contains "$P/.agents/agents/architect.md" '"write_to_file", "grep_search"'
  check "Antigravity agent: opus is pro" grep -qx 'model: pro' "$P/.agents/agents/planner.md"
  check "Gemini agent: its tool names + code map" contains "$P/.gemini/agents/planner.md" 'tools: ["read_file", "read_many_files", "list_directory", "grep_search", "glob", "mcp_codebase-memory_list_projects"'
  check "Gemini agent: write tools" contains "$P/.gemini/agents/architect.md" '"list_directory", "write_file", "grep_search"'
  for f in .github/agents/planner.md .gemini/agents/planner.md; do
    check "$f: no Claude model id" test "$(grep -c '^model:' "$P/$f")" = 0
  done
  check_not "no agent gets a shell ECC did not give it" contains "$P/.github/agents/planner.md" '"execute"'
  check "Codex: read-only agent sandboxed, as ECC does" grep -qx 'sandbox_mode = "read-only"' "$P/.codex/agents/planner.toml"
  check "Codex: opus is high reasoning effort" grep -qx 'model_reasoning_effort = "high"' "$P/.codex/agents/planner.toml"
  check_not "Codex: an editing agent is not sandboxed" contains "$P/.codex/agents/architect.toml" sandbox_mode
  check "Cursor agent: session model" grep -qx 'model: inherit' "$P/.cursor/agents/planner.md"
  check "Cursor agent: read-only agent is readonly" grep -qx 'readonly: true' "$P/.cursor/agents/planner.md"
  check_not "Cursor agent: an editing agent is not" contains "$P/.cursor/agents/architect.md" readonly
  check_not "Cursor agent: no Claude tools line" contains "$P/.cursor/agents/planner.md" "tools:"
  check "Gemini agent: only keys its strict schema allows" test "$(sed -n '2,/^---$/p' "$P/.gemini/agents/planner.md" | grep -cvE '^(name|description|tools):|^---$')" = 0
  check "agents point at the Superpowers TDD skill" contains "$P/.codex/agents/planner.toml" "skill: test-driven-development"
  if command -v python3 >/dev/null && python3 -c 'import tomllib' 2>/dev/null; then
    check "Codex agent is valid TOML" python3 -c '
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
assert d["name"] == "planner" and "\"quotes\"" in d["description"]
assert "back\\slash" in d["developer_instructions"] and "\"\"\"" in d["developer_instructions"]' "$P/.codex/agents/planner.toml"
  fi
  check "summary printed" grep -q "^ready in " "$WORK/last.log"
  check_not "no ANSI colors with NO_COLOR" grep -q $'\033' "$WORK/last.log"
}

test_session_hooks() {
  local out
  out="$(bash "$P/.claude/hooks/superpowers-session-start.sh")"
  check "Claude: additionalContext JSON" json_has <(echo "$out") '$d->{hookSpecificOutput}{additionalContext} =~ /using-superpowers/ && $d->{hookSpecificOutput}{additionalContext} =~ /back\\slash/'
  out="$(bash "$P/.cursor/hooks/superpowers-session-start.sh")"
  check "Cursor: additional_context JSON" json_has <(echo "$out") '$d->{additional_context} =~ /Check skills first/'
  out="$(bash "$P/.codex/hooks/superpowers-session-start.sh")"
  check "Codex: additionalContext JSON" json_has <(echo "$out") '$d->{hookSpecificOutput}{hookEventName} eq "SessionStart"'
  out="$(bash "$P/.agents/hooks/session-start.sh")"
  check "Antigravity: injectSteps JSON" json_has <(echo "$out") '$d->{injectSteps}[0]{systemMessage}{systemMessage} =~ /Check skills first/'
  # the configured commands, run the way the agent would: from a subdirectory
  local cmd
  cmd="$(perl -MJSON::PP -e 'local $/; print JSON::PP->new->decode(<STDIN>)->{hooks}{SessionStart}[0]{hooks}[0]{command}' < "$P/.codex/hooks.json")"
  out="$(cd "$P/src" && sh -c "$cmd")"
  check "Codex: hook command finds the root from a subdirectory" json_has <(echo "$out") '$d->{hookSpecificOutput}{additionalContext}'
  cmd="$(perl -MJSON::PP -e 'local $/; print JSON::PP->new->decode(<STDIN>)->{"superpowers-session-start"}{SessionStart}[0]{command}' < "$P/.agents/hooks.json")"
  out="$(cd "$P/src" && sh -c "$cmd")"
  check "Antigravity: hook command finds the root from a subdirectory" json_has <(echo "$out") '$d->{injectSteps}'
}

test_lost_lock_uninstall() {
  local d="$WORK/lostlock"; rm -rf "$d" && bootstrap "$d" -t claude
  rm "$d/.agents/superpowers.lock"
  bootstrap "$d" --uninstall
  check "uninstall without a lock: counts are 0" grep -Eq '^\[8/9\] skills +ok .*0 skills' "$WORK/last.log"
  check_not "uninstall without a lock: no grep error" contains "$WORK/last.log" "No such file"
}

test_rerun_idempotent() {
  manifest "$P" > "$WORK/m1"
  check "re-run succeeds" bootstrap "$P"
  manifest "$P" > "$WORK/m2"
  check "re-run changes nothing" diff "$WORK/m1" "$WORK/m2"
}

test_no_node() {
  # json_edit must not need node: a node that fails proves it isn't called
  local d="$WORK/nonode" shim="$WORK/shim"
  mkdir -p "$shim" && printf '#!/bin/sh\nexit 99\n' > "$shim/node" && chmod +x "$shim/node"
  rm -rf "$d"
  PATH="$shim:$PATH" bootstrap "$d" -t claude,cursor
  check "bootstrap succeeds" test $? = 0
  check "Claude settings written" json_has "$d/.claude/settings.json" '$d->{hooks}{PreToolUse}'
  check "Cursor hooks written" json_has "$d/.cursor/hooks.json" '$d->{hooks}{beforeReadFile}'
  check_not "no 'skipped' warning" contains "$WORK/last.log" "skipped"
}

test_user_config_kept() {
  local d="$WORK/user"
  rm -rf "$d" && mkdir -p "$d/.claude" "$d/.vscode" "$d/.cursor"
  cat > "$d/.claude/settings.json" <<'EOF'
{ "permissions": { "allow": ["Bash(npm test)"], "deny": ["Read(./secrets/**)"] },
  "hooks": { "PreToolUse": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "./mine.sh" }] }] },
  "model": "sonnet" }
EOF
  printf '{\n  // team picks\n  "recommendations": ["esbenp.prettier-vscode",],\n}\n' > "$d/.vscode/extensions.json"
  echo '{ "version": 1, "hooks": { "stop": [{ "command": "./done.sh" }] } }' > "$d/.cursor/hooks.json"
  echo '# Team notes' > "$d/AGENTS.md"
  check "bootstrap succeeds" bootstrap "$d" -t claude,cursor,codex
  check "own hook kept" json_has "$d/.claude/settings.json" 'grep { $_->{hooks}[0]{command} eq "./mine.sh" } @{ $d->{hooks}{PreToolUse} }'
  check "own deny kept" json_has "$d/.claude/settings.json" 'grep { $_ eq "Read(./secrets/**)" } @{ $d->{permissions}{deny} }'
  check "JSONC parsed, own recommendation kept" json_has "$d/.vscode/extensions.json" '"@{ $d->{recommendations} }" =~ /prettier/'
  check "JSONC original backed up" test -f "$d/.vscode/extensions.json.bak"
  check "own Cursor hook kept" json_has "$d/.cursor/hooks.json" '$d->{hooks}{stop}'
  bootstrap "$d" --uninstall
  check "uninstall: own hook kept" json_has "$d/.claude/settings.json" '@{ $d->{hooks}{PreToolUse} } == 1 && !$d->{hooks}{SessionStart}'
  check "uninstall: our deny rules gone, own kept" json_has "$d/.claude/settings.json" '"@{ $d->{permissions}{deny} }" eq "Read(./secrets/**)"'
  check "uninstall: other settings kept" json_has "$d/.claude/settings.json" '$d->{model} eq "sonnet" && @{ $d->{permissions}{allow} } == 1'
  check "uninstall: own Cursor hook kept" json_has "$d/.cursor/hooks.json" '!$d->{hooks}{sessionStart} && $d->{hooks}{stop}'
  check_not "uninstall: no Cursor CLI file left" test -e "$d/.cursor/cli.json"
  check "uninstall: AGENTS.md back to the user's" test "$(cat "$d/AGENTS.md")" = "# Team notes"
}

test_deselect() {
  local d="$WORK/deselect"
  rm -rf "$d" && bootstrap "$d"
  check "re-run with fewer targets" bootstrap "$d" -t claude
  local p
  for p in .codex .cursor .devin .github .agents/hooks.json .agents/hooks .agents/rules .agents/agents .gemini AGENTS.md GEMINI.md; do
    check_not "removes $p" test -e "$d/$p"
  done
  check "keeps Claude" test -f "$d/.claude/hooks/secret-guard.pl"
  check "VS Code: drops Codex/Copilot recommendations" json_has "$d/.vscode/extensions.json" '"@{ $d->{recommendations} }" eq "anthropic.claude-code"'
}

test_windsurf_migration() {
  local d="$WORK/windsurf"
  rm -rf "$d" && bootstrap "$d" -t claude
  # what an earlier version left: a windsurf target and its rule
  perl -pi -e 's/^targets: .*/targets: claude,windsurf/' "$d/.agents/superpowers.lock"
  mkdir -p "$d/.windsurf/rules" && echo old > "$d/.windsurf/rules/superpowers.md"
  check "--targets windsurf still accepted" bootstrap "$d" -t claude,windsurf
  check "rule moved to .devin/rules" test -f "$d/.devin/rules/superpowers.md"
  check_not "old .windsurf rule removed" test -e "$d/.windsurf"
  check "lock says devin" contains "$d/.agents/superpowers.lock" "targets: claude,devin"
  perl -pi -e 's/^targets: .*/targets: claude,windsurf/' "$d/.agents/superpowers.lock"
  check "an old lock's windsurf is deselectable" bootstrap "$d" -t claude
  check_not "Devin rule removed" test -e "$d/.devin"
}

test_own_skill_link_kept() {
  # a user's own skill, linked into .claude/skills the way the bootstrap does it
  local d="$WORK/ownlink"
  rm -rf "$d" && bootstrap "$d" -t claude
  mkdir -p "$d/.agents/skills/deploy" && echo mine > "$d/.agents/skills/deploy/SKILL.md"
  ln -s ../../.agents/skills/deploy "$d/.claude/skills/deploy"
  check "re-run succeeds" bootstrap "$d" -t claude
  check "own link kept" test -L "$d/.claude/skills/deploy"
}

test_failed_fetch_keeps_lock() {
  local d="$WORK/failfetch"
  rm -rf "$d" && bootstrap "$d" -t claude
  check_not "a bad security-audit source fails" bash "$BOOTSTRAP" -y -s "$SP" --ecc-source "$ECC" \
    --security-audit-source "$WORK/nowhere" -t claude "$d"
  check "lock still lists the agents" grep -q '^agent: .claude/agents/planner.md$' "$d/.agents/superpowers.lock"
  check "next run succeeds" bootstrap "$d" -t claude
  check_not "no 'not from the bootstrap' warnings" contains "$WORK/last.log" "not from the bootstrap"
}

test_uninstall() {
  local d="$WORK/uninstall"
  rm -rf "$d" && mkdir -p "$d" && echo '# mine' > "$d/README.md"
  bootstrap "$d"
  check "uninstall succeeds" bootstrap "$d" --uninstall
  check "only the user's files and .vscode are left" test "$(cd "$d" && find . -type f ! -path './.vscode/*' | sort | tr '\n' ' ')" = "./README.md "
}
