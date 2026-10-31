# ripgrep: the pinned download, --no-ripgrep, and the search section agents get.

test_ripgrep_download() {
  local d="$WORK/rgdl" mirror="$WORK/mirror" asset target sha
  # a fake release for this machine, served from a file:// mirror
  # shellcheck source=/dev/null
  . "$TESTS_DIR/../lib/ripgrep.sh"
  asset="$(rg_asset)"; asset="${asset% *}"; target="${asset%%.*}"
  if [ -z "$asset" ] || [ "${asset##*.}" = zip ]; then echo "  (skipped: no tar.gz build for this machine)"; return 0; fi
  mkdir -p "$mirror/ripgrep-$RG_VERSION-$target"
  printf '#!/bin/sh\necho "ripgrep %s (fixture)"\n' "$RG_VERSION" > "$mirror/ripgrep-$RG_VERSION-$target/rg"
  chmod +x "$mirror/ripgrep-$RG_VERSION-$target/rg"
  tar -czf "$mirror/ripgrep-$RG_VERSION-$asset" -C "$mirror" "ripgrep-$RG_VERSION-$target"
  sha="$(perl -MDigest::SHA -e 'print Digest::SHA->new(256)->addfile($ARGV[0], "b")->hexdigest' "$mirror/ripgrep-$RG_VERSION-$asset")"

  rm -rf "$d"
  PATH="$NO_RG_PATH" RIPGREP_MIRROR="file://$mirror" RIPGREP_SHA256=0000 bootstrap "$d" -t claude
  check "bad checksum: bootstrap still succeeds" test $? = 0
  check "bad checksum: warns" contains "$WORK/last.log" "failed its checksum"
  check_not "bad checksum: nothing installed" test -e "$d/.agents/bin/rg"

  PATH="$NO_RG_PATH" RIPGREP_MIRROR="file://$mirror" RIPGREP_SHA256="$sha" bootstrap "$d" -t claude
  check "installs .agents/bin/rg" test -x "$d/.agents/bin/rg"
  check "the binary runs" sh -c "'$d/.agents/bin/rg' --version | grep -q fixture"
  check ".agents/bin is git-ignored" test "$(cat "$d/.agents/bin/.gitignore")" = "*"
  check "ripgrep stage says where rg is" contains "$WORK/last.log" "$RG_VERSION -> .agents/bin (local)"
  # the guard finds the project's rg when none is on PATH
  check "guard uses .agents/bin/rg" sh -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -r x .\"}}' | PATH='$NO_RG_PATH' perl '$d/.claude/hooks/search-guard.pl' claude 2>&1 | grep -q '.agents/bin/rg PATTERN'"
  PATH="$NO_RG_PATH" RIPGREP_MIRROR="file:///nonexistent" bootstrap "$d" -t claude
  check "re-run keeps the installed rg (no download)" test -x "$d/.agents/bin/rg"
  check "--check ignores .agents/bin" bootstrap "$d" --check
  bootstrap "$d" --uninstall
  check_not "uninstall removes .agents/bin" test -e "$d/.agents/bin"
}

test_no_ripgrep() {
  local d="$WORK/norg"
  rm -rf "$d" && bootstrap "$d" -t claude,codex,cursor,antigravity,copilot
  check "re-run with --no-ripgrep" bootstrap "$d" -t claude,codex,cursor,antigravity,copilot --no-ripgrep
  check_not "no search rule" contains "$d/CLAUDE.md" '**Search:**'
  local f
  for f in .claude/hooks/search-guard.pl .codex/hooks/search-guard.pl .cursor/hooks/search-guard.pl \
           .agents/hooks/search-guard.pl .github/hooks/search-guard.pl .github/hooks/superpowers-search-guard.json; do
    check_not "removes $f" test -e "$d/$f"
  done
  check "Claude: only the secret guard left" json_has "$d/.claude/settings.json" '@{ $d->{hooks}{PreToolUse} } == 1'
  check "Antigravity: no search guard" json_has "$d/.agents/hooks.json" '!$d->{"superpowers-search-guard"}'
  check "lock records --no-ripgrep" contains "$d/.agents/superpowers.lock" "--no-ripgrep"
  check "--check reproduces --no-ripgrep" bootstrap "$d" --check
}

test_agents_search_with_rg() {
  local d="$WORK/agentsrg" f
  rm -rf "$d" && bootstrap "$d"
  check "array form: Glob and the code map added, no shell" contains "$d/.claude/agents/planner.md" 'tools: ["Read", "Grep", "Glob", "mcp__codebase-memory__list_projects", "mcp__codebase-memory__search_graph"'
  check_not "read-only agent gets no Bash" grep -q '^tools:.*Bash' "$d/.claude/agents/planner.md"
  check "comma form: own tools kept, the rest added" contains "$d/.claude/agents/architect.md" 'tools: Read, Write, Grep, Glob, mcp__codebase-memory__list_projects'
  check "auditor keeps its Bash" contains "$d/.claude/agents/security-auditor.md" 'tools: Read, Grep, Glob, Bash, mcp__codebase-memory__'
  check_not "no tool that writes the index" contains "$d/.claude/agents/planner.md" index_repository
  for f in .claude/agents/planner.md .claude/agents/security-auditor.md .github/agents/planner.md \
           .codex/agents/planner.toml .agents/agents/security-auditor.md .gemini/agents/planner.md; do
    check "$f: search rule" contains "$d/$f" "rg --files -g"
  done
  bootstrap "$d"
  check "rule appears once after a re-run" test "$(grep -c 'rg --files -g' "$d/.claude/agents/planner.md")" = 1
  bootstrap "$d" --no-ripgrep
  check "--no-ripgrep: tools as upstream" contains "$d/.claude/agents/planner.md" 'tools: ["Read", "Grep"]'
  check "--no-ripgrep: Copilot tools follow upstream" grep -qxF 'tools: ["read", "search"]' "$d/.github/agents/planner.md"
  check_not "--no-ripgrep: no search rule" contains "$d/.claude/agents/planner.md" "rg --files -g"
  bootstrap "$d" --no-code-map
  check "--no-code-map: no MCP tools" grep -qxF 'tools: ["Read", "Grep", "Glob"]' "$d/.claude/agents/planner.md"
}
