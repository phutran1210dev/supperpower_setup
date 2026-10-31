# Subagents from everything-claude-code (MIT), plus the security-auditor
# (templates/security-auditor.md, unless --no-security-audit): .claude/agents (as-is),
# .github/agents, .agents/agents, .gemini/agents and .cursor/agents (each
# platform's own format, platform_agent) and .codex/agents (TOML). ECC's tool
# choices carry over: an agent it keeps read-only stays read-only everywhere.
# The lock records each file written, so re-runs and uninstall leave agents of
# your own alone.

# A general-purpose subset of ECC's agents; doc-updater and code-explorer are
# left out (the code map covers them). Stack-specific ones: lib/stacks.sh.
ECC_AGENTS="planner architect code-reviewer security-reviewer tdd-guide build-error-resolver refactor-cleaner
  silent-failure-hunter pr-test-analyzer type-design-analyzer code-simplifier comment-analyzer commit-reviewer"

# Agents and skills newer than ECC_REF come from ECC_NEXT_REF, a pinned commit on
# ECC's main, while the ECC_REF checkout doesn't have them; a later tag that
# ships them is used instead. ECC_NEXT_SOURCE: a local checkout of that commit.
ECC_NEXT_REF="b38be6a7f6350964d59328b52f0624e1d1d552d1"
ECC_NEXT_AGENTS="commit-reviewer ruby-reviewer"
ECC_NEXT_SKILLS="rails-patterns"
ECC_NEXT_DIR=""

# needs_ecc — this run uses everything-claude-code at all (its agents or skills)
needs_ecc() {
  { [ "$AGENTS" -eq 1 ] && [ -n "$(agent_dirs)" ]; } || [ -n "$(ecc_skill_names)" ]
}

fetch_ecc() {
  local src="$ECC_SOURCE"
  if [ -z "$src" ]; then
    src="$TMP_DIR/ecc"
    # sparse + blobless: only agents/ and this run's skills are downloaded;
    # fall back to a plain clone
    local paths=(/agents/ /LICENSE /package.json) name
    for name in $(ecc_skill_names); do paths+=("/skills/$name/"); done
    if ! { git clone --quiet --depth 1 --filter=blob:none --sparse --branch "$ECC_REF" "$ECC_REPO_URL" "$src" 2>/dev/null \
           && git -C "$src" sparse-checkout set --no-cone "${paths[@]}" >/dev/null 2>&1; }; then
      rm -rf "$src"
      git_clone --depth 1 --branch "$ECC_REF" "$ECC_REPO_URL" "$src" \
        || die "could not clone $ECC_REPO_URL at '$ECC_REF' (or pass --no-agents)"
    fi
  fi
  [ -d "$src/agents" ] || die "$src does not look like an everything-claude-code checkout"
  ECC_DIR="$src"
  ECC_VERSION="$(checkout_version "$src" package.json)"
  fetch_ecc_next
}

# ecc_next_paths — this run's ECC_NEXT_* files that the ECC_REF checkout lacks
ecc_next_paths() {
  local name
  if [ "$AGENTS" -eq 1 ]; then
    for name in $ECC_AGENTS $(stack_agent_names); do
      case " $ECC_NEXT_AGENTS " in *" $name "*) [ -f "$ECC_DIR/agents/$name.md" ] || echo "/agents/$name.md" ;; esac
    done
  fi
  for name in $(ecc_skill_names); do
    case " $ECC_NEXT_SKILLS " in *" $name "*) [ -f "$ECC_DIR/skills/$name/SKILL.md" ] || echo "/skills/$name/" ;; esac
  done
  return 0
}

# fetch_ecc_next — ECC_NEXT_DIR: just those files at ECC_NEXT_REF (sparse,
# blobless, one commit). Unreachable, they are skipped with agent_sources' and
# install_ecc_skills' warnings.
fetch_ecc_next() {
  local paths src="${ECC_NEXT_SOURCE:-}"
  paths="$(ecc_next_paths)"
  [ -n "$paths" ] || return 0
  if [ -z "$src" ]; then
    src="$TMP_DIR/ecc-next"
    # shellcheck disable=SC2086 # one path per word
    if ! { git init --quiet "$src" && git -C "$src" remote add origin "$ECC_REPO_URL" \
           && git -C "$src" sparse-checkout set --no-cone $paths >/dev/null 2>&1 \
           && git -C "$src" fetch --quiet --depth 1 --filter=blob:none origin "$ECC_NEXT_REF" 2>/dev/null \
           && git -C "$src" checkout --quiet FETCH_HEAD 2>/dev/null; }; then
      rm -rf "$src"
      return 0
    fi
  fi
  [ -d "$src" ] || return 0
  ECC_NEXT_DIR="$src"
  ECC_VERSION="$ECC_VERSION + main @ ${ECC_NEXT_REF:0:7}"
}

# ecc_file REL — REL in the ECC_REF checkout, else in ECC_NEXT_REF's
ecc_file() {
  if [ -e "$ECC_DIR/$1" ]; then echo "$ECC_DIR/$1"
  elif [ -n "$ECC_NEXT_DIR" ] && [ -e "$ECC_NEXT_DIR/$1" ]; then echo "$ECC_NEXT_DIR/$1"
  else return 1
  fi
}

# platform_agent copilot|antigravity|gemini|cursor FILE — a Claude agent in
# another platform's Markdown format: name, description and the Claude tools
# under that platform's names. Tools without an equivalent are left out: an
# unknown name hangs an Antigravity subagent and fails a Gemini agent's load.
# Claude model ids (opus, sonnet) mean nothing elsewhere: the agent inherits the
# session's model unless the platform has a matching tier.
#   copilot      aliases from Copilot's custom-agent reference (cloud, CLI, VS Code);
#                MCP tools as server/tool
#   antigravity  its tool names, no MCP; opus -> pro, haiku -> flash; keeps
#                skills:, which Antigravity agents preload
#   gemini       its tool names, MCP tools as mcp_server_tool; its strict schema
#                rejects any other key
#   cursor       no tools list (subagents inherit them all): model: inherit, and
#                readonly: true for an agent ECC gives no write tool (agent_read_only)
platform_agent() {
  SP_PLATFORM="$1" perl -e '
    my $p = $ENV{SP_PLATFORM};
    my $map = {
      copilot => { Read => "read", NotebookRead => "read", Grep => "search", Glob => "search",
        Bash => "execute", Write => "edit", Edit => "edit", MultiEdit => "edit", NotebookEdit => "edit",
        WebFetch => "web", WebSearch => "web", Task => "agent", Agent => "agent", TodoWrite => "todo" },
      antigravity => { Read => "view_file list_dir", Grep => "grep_search", Glob => "find_by_name",
        Bash => "run_command", Write => "write_to_file",
        Edit => "replace_file_content multi_replace_file_content", MultiEdit => "multi_replace_file_content",
        WebFetch => "read_url_content", WebSearch => "search_web", Task => "invoke_subagent", Agent => "invoke_subagent" },
      gemini => { Read => "read_file read_many_files list_directory", Grep => "grep_search", Glob => "glob",
        Bash => "run_shell_command", Write => "write_file", Edit => "replace", MultiEdit => "replace",
        WebFetch => "web_fetch", WebSearch => "google_web_search", TodoWrite => "write_todos" },
      cursor => {},
    }->{$p};
    my $mcp = { copilot => "%s/%s", gemini => "mcp_%s_%s" }->{$p};
    my $models = { antigravity => { opus => "pro", haiku => "flash" } }->{$p} // {};
    my $keep = $p eq "antigravity" ? qr/^(name|description|skills):/ : qr/^(name|description):/;
    my ($fm, $list, $tools, $writes) = (0, 0, 0, 0);
    while (my $line = <STDIN>) {
      if ($. == 1 && $line eq "---\n") { $fm = 1; print $line; next }
      if ($fm && $line eq "---\n") {
        if ($p eq "cursor") {
          print "model: inherit\n";
          print "readonly: true\n" if $tools && !$writes;
        }
        $fm = 0; print $line; next;
      }
      if (!$fm) { print $line; next }
      # a YAML list under a kept key (skills:) goes with it
      if ($line =~ /^\s+-\s/) { print $line if $list; next }
      $list = 0;
      if ($line =~ /^tools:\s*(.*?)\s*$/) {
        (my $v = $1) =~ s/^\[(.*)\]$/$1/;
        my (%seen, @out);
        $tools = 1;
        for my $t (map { s/^\s*["\x27]?|["\x27]?\s*$//gr } split /,/, $v) {
          $writes = 1 if $t =~ /^(Write|Edit|MultiEdit|NotebookEdit)$/;
          my $to = $t =~ /^mcp__(.+?)__(.+)$/ ? ($mcp ? sprintf($mcp, $1, $2) : "") : ($map->{$t} // "");
          push @out, grep { !$seen{$_}++ } split / /, $to;
        }
        print "tools: [" . join(", ", map { qq{"$_"} } @out) . "]\n" if @out;
      } elsif ($line =~ /^model:\s*["\x27]?(\w+)/) {
        print "model: $models->{$1}\n" if $models->{$1};
      } elsif ($line =~ $keep) {
        print $line;
        $list = 1;
      }
    }' < "$2"
}

# agent_read_only FILE — ECC limits the agent to tools that don't write files
# (planner, architect, the reviewers): it has a tools list without a write tool
agent_read_only() {
  local tools
  tools="$(frontmatter_field "$1" tools)"
  [ -n "$tools" ] && ! printf '%s' "$tools" | grep -Eq '(^|[^A-Za-z])(Write|Edit|MultiEdit|NotebookEdit)([^A-Za-z]|$)'
}

# Codex custom agents are TOML: name, description and the prompt as
# developer_instructions. Codex has no per-agent tools list and the model ids
# differ, so like ECC's own Codex agents: a read-only agent gets the read-only
# sandbox (older Codex applies it; newer ones keep the parent's) and the Claude
# tier becomes the reasoning effort (opus -> high, haiku -> low); the model
# itself is inherited from the session.
codex_agent() {
  local sandbox="" effort=""
  agent_read_only "$1" && sandbox="read-only"
  case "$(frontmatter_field "$1" model)" in
    opus) effort=high ;;
    haiku) effort=low ;;
  esac
  skill_body "$1" | SP_NAME="$(frontmatter_field "$1" name)" SP_DESC="$(frontmatter_field "$1" description)" \
    SP_SANDBOX="$sandbox" SP_EFFORT="$effort" perl -e '
    sub str { (my $s = shift) =~ s/([\\"])/\\$1/g; $s }
    sub unyaml { (my $s = shift) =~ s/\\(["\\])/$1/g; $s }  # "..." frontmatter escapes
    my $body = do { local $/; <STDIN> };
    $body =~ s/^\s+|\s+$//g;
    printf qq{name = "%s"\ndescription = "%s"\n}, str(unyaml($ENV{SP_NAME})), str(unyaml($ENV{SP_DESC}));
    print qq{model_reasoning_effort = "$ENV{SP_EFFORT}"\n} if $ENV{SP_EFFORT};
    print qq{sandbox_mode = "$ENV{SP_SANDBOX}"\n} if $ENV{SP_SANDBOX};
    printf qq{developer_instructions = """\n%s\n"""\n}, str($body);'
}

# agent_dirs — where the selected targets keep their agents
agent_dirs() {
  has_target claude && echo .claude/agents
  has_target copilot && echo .github/agents
  has_target codex && echo .codex/agents
  has_target antigravity && echo .agents/agents
  has_target gemini && echo .gemini/agents
  has_target cursor && echo .cursor/agents
  return 0
}

# agent_sources — fills the AGENT_SOURCES array with the agent files to install
# (fetch_ecc ran in the fetch stage); not a $(...) so its warnings are counted
agent_sources() {
  local name src
  AGENT_SOURCES=()
  if [ "$AGENTS" -eq 1 ]; then
    for name in $ECC_AGENTS $(stack_agent_names); do
      if src="$(ecc_file "agents/$name.md")"; then AGENT_SOURCES+=("$src")
      else warn "everything-claude-code has no agents/$name.md — skipped"
      fi
    done
  fi
  [ "$SECURITY_AUDIT" -eq 1 ] && AGENT_SOURCES+=("$TEMPLATES_DIR/security-auditor.md")
  return 0
}

# install_agents — writes the agents for the selected targets and appends
# agent: lines to the lock; removes agents a previous run wrote but this one
# didn't (target or agent set changed)
install_agents() {
  local prev dirs="" d src rel kept=""
  prev="$(prev_locked agent)"
  { [ "$AGENTS" -eq 1 ] || [ "$SECURITY_AUDIT" -eq 1 ]; } && dirs="$(agent_dirs | tr '\n' ' ')"
  if [ -n "$dirs" ]; then
    agent_sources
    for d in $dirs; do
      for src in ${AGENT_SOURCES[@]+"${AGENT_SOURCES[@]}"}; do
        rel="$d/$(basename "$src")"
        [ "$d" = ".codex/agents" ] && rel="$d/$(basename "$src" .md).toml"
        if [ -e "$PROJECT_DIR/$rel" ] && ! printf '%s\n' "$prev" | grep -qxF "$rel" && [ "$FORCE" -ne 1 ]; then
          warn "$rel already exists and is not from the bootstrap — skipped (use --force)"
          continue
        fi
        mkdir -p "$PROJECT_DIR/$d"
        agent_with_search "$src" > "$TMP_DIR/agent.md"
        # point ECC's TDD and security-review skill references at the ones
        # installed here (Superpowers' TDD, Cloudflare's security-audit)
        case "$d" in
          .claude/agents) cat "$TMP_DIR/agent.md" ;;
          .codex/agents)  codex_agent "$TMP_DIR/agent.md" ;;
          .github/agents) platform_agent copilot "$TMP_DIR/agent.md" ;;
          .agents/agents) platform_agent antigravity "$TMP_DIR/agent.md" ;;
          .gemini/agents) platform_agent gemini "$TMP_DIR/agent.md" ;;
          .cursor/agents) platform_agent cursor "$TMP_DIR/agent.md" ;;
        esac | SP_SEC="$([ "$SECURITY_AUDIT" -eq 1 ] && echo security-audit)" perl -pe 's/(skill: `?)tdd-workflow\b/${1}test-driven-development/g; s/(skill: `?)security-review\b/${1}$ENV{SP_SEC}/g if $ENV{SP_SEC}' > "$PROJECT_DIR/$rel"
        kept="$kept$rel"$'\n'
      done
      ok "$d/ ($(printf '%s' "$kept" | grep -c "^$d/") agents)"
    done
    if [ "$AGENTS" -eq 1 ]; then
      mkdir -p "$PROJECT_DIR/.agents/licenses"
      cp "$ECC_DIR/LICENSE" "$PROJECT_DIR/.agents/licenses/everything-claude-code.LICENSE"
      lock_add ecc "$ECC_VERSION"
    fi
    lock_add agent "$kept"
  fi
  for rel in $prev; do
    printf '%s' "$kept" | grep -qxF "$rel" || rm -f "$PROJECT_DIR/$rel"
  done
  [ "$AGENTS" -eq 1 ] && [ -n "$dirs" ] || remove_agents_license
  remove_empty_agent_dirs
}

# agent_with_search SRC — the agent with ripgrep wired in (unless --no-ripgrep):
# a tools list, when it has one, gains whichever of Read, Grep and Glob (Claude
# Code's Grep is ripgrep) it lacks, plus the code map's read-only MCP tools, in
# the list's own style; the body ends with agent_search_rule. No Bash: ECC's
# read-only agents (planner, architect, ...) stay without a shell. Without a
# tools list the agent has every tool already.
agent_with_search() {
  if [ "$RIPGREP" -eq 0 ]; then cat "$1"; return 0; fi
  SP_RULE="$(agent_search_rule)" \
  SP_MCP="$([ "$CODE_MAP" -eq 1 ] && for t in $CM_AGENT_TOOLS; do printf 'mcp__%s__%s ' "$CM_NAME" "$t"; done)" perl -e '
    my @need = (qw(Read Grep Glob), split " ", $ENV{SP_MCP});
    my $fm = 0;
    while (my $line = <STDIN>) {
      if ($. == 1 && $line eq "---\n") { $fm = 1 }
      elsif ($fm && $line eq "---\n") { $fm = 0 }
      elsif ($fm && $line =~ /^tools:\s*(.*?)\s*$/) {
        my $v = $1;
        my $array = $v =~ s/^\[(.*)\]$/$1/;
        my @have = grep { length } map { s/^\s*["\x27]?|["\x27]?\s*$//gr } split /,/, $v;
        my %has = map { $_ => 1 } @have;
        push @have, grep { !$has{$_} } @need;
        $line = $array ? "tools: [" . join(", ", map { qq{"$_"} } @have) . "]\n"
                       : "tools: " . join(", ", @have) . "\n";
      }
      print $line;
    }
    print "\n$ENV{SP_RULE}\n";' < "$1"
}

remove_agents() {
  local rel
  for rel in $(prev_locked agent); do rm -f "${PROJECT_DIR:?}/$rel"; done
  remove_agents_license
  remove_empty_agent_dirs
}

remove_agents_license() {
  rm -f "$PROJECT_DIR/.agents/licenses/everything-claude-code.LICENSE"
  rmdir "$PROJECT_DIR/.agents/licenses" 2>/dev/null || true
}

remove_empty_agent_dirs() {
  rmdir "$PROJECT_DIR/.claude/agents" "$PROJECT_DIR/.github/agents" \
    "$PROJECT_DIR/.codex/agents" "$PROJECT_DIR/.agents/agents" "$PROJECT_DIR/.gemini/agents" \
    "$PROJECT_DIR/.cursor/agents" 2>/dev/null || true
  # teardown_gemini leaves .gemini while our agents are still in it
  rmdir "$PROJECT_DIR/.gemini" 2>/dev/null || true
}
