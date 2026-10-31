# Offline stand-ins for everything the bootstrap fetches: Superpowers,
# everything-claude-code and security-audit-skill checkouts (--source /
# --ecc-source / --security-audit-source) and a codebase-memory release on a
# file:// mirror. Sourced by run.sh.

SP="$WORK/superpowers"
mkdir -p "$SP/.claude-plugin" "$SP/skills/using-superpowers/references" "$SP/skills/brainstorming" "$SP/skills/writing-plans"
echo '{ "version": "9.9.9" }' > "$SP/.claude-plugin/plugin.json"
cat > "$SP/skills/using-superpowers/SKILL.md" <<'EOF'
---
name: using-superpowers
description: Use when starting any conversation
---
# Using Superpowers
Check skills first. Quotes "here" and a back\slash.

## Platform Adaptation
- other harnesses

## The Rule
Invoke skills.
EOF
for f in codex-tools gemini-tools antigravity-tools; do echo "# $f" > "$SP/skills/using-superpowers/references/$f.md"; done
printf -- '---\nname: brainstorming\ndescription: Use before creative work\n---\nThen use superpowers:writing-plans.\n' > "$SP/skills/brainstorming/SKILL.md"
printf -- '---\nname: writing-plans\ndescription: Use for multi-step tasks\n---\nWrite the plan.\n' > "$SP/skills/writing-plans/SKILL.md"

ECC="$WORK/ecc"
mkdir -p "$ECC/agents"
# every agent and skill the bootstrap can take, for any stack
# shellcheck source=/dev/null
. "$TESTS_DIR/../lib/agents.sh"
# shellcheck source=/dev/null
. "$TESTS_DIR/../lib/stacks.sh"
ECC_STACK_AGENTS="$(for s in $STACK_ALL; do stack_agents "$s"; done)"
ECC_ALL_SKILLS="$(for s in $STACK_ALL; do stack_skills "$s"; done | tr " " "\n" | sort -u)"
echo '{ "version": "1.2.3" }' > "$ECC/package.json"
echo 'MIT License' > "$ECC/LICENSE"
for a in $ECC_AGENTS $ECC_STACK_AGENTS; do
  cat > "$ECC/agents/$a.md" <<EOF
---
name: $a
description: "The $a agent, with \"quotes\""
tools: ["Read", "Grep"]
model: opus
---
You are the $a. Use skill: tdd-workflow. Patterns: see skill: \`security-review\`.
A back\\slash and triple quotes: """
EOF
done
# ECC's real files use the comma form
perl -pi -e 's/^tools: .*/tools: Read, Write, Grep/' "$ECC/agents/architect.md"
for s in $ECC_SKILLS_COMMON $ECC_ALL_SKILLS; do
  mkdir -p "$ECC/skills/$s"
  printf -- '---\nname: %s\ndescription: ECC %s skill\n---\nKnow-how.\n' "$s" "$s" > "$ECC/skills/$s/SKILL.md"
done

# what ECC_REF predates comes from ECC_NEXT_REF: the fake tag lacks it, a second
# checkout (ECC_NEXT_SOURCE) has it
ECC_NEXT="$WORK/ecc-next"
mkdir -p "$ECC_NEXT/agents" "$ECC_NEXT/skills"
for a in $ECC_NEXT_AGENTS; do mv "$ECC/agents/$a.md" "$ECC_NEXT/agents/"; done
for s in $ECC_NEXT_SKILLS; do mv "$ECC/skills/$s" "$ECC_NEXT/skills/"; done
export ECC_NEXT_SOURCE="$ECC_NEXT"

SA="$WORK/security-audit-skill"
mkdir -p "$SA/skills/security-audit"
echo 'MIT License' > "$SA/LICENSE"
cat > "$SA/skills/security-audit/SKILL.md" <<'EOF'
---
name: security-audit
description: Security guidance and vulnerability review for codebases.
---
# Security Audit
EOF
echo '// validator' > "$SA/skills/security-audit/validate-findings.cjs"

# A fake codebase-memory release for this machine, served from a file:// mirror:
# it logs each call (args + cwd); `cli index_repository` answers like the real
# one (CM_FAKE_FAIL: an error), `list_projects` lists the directory it runs in
# and `config get ui_enabled` says $CM_FAKE_UI (default true).
# shellcheck source=/dev/null
. "$TESTS_DIR/../lib/codemap.sh"
CM_MIRROR="$WORK/cmmirror" CM_LOG="$WORK/codebase-memory.log"
CM_FILE="$(cm_asset)"; CM_FILE="${CM_FILE% *}"
mkdir -p "$CM_MIRROR/pkg"
cat > "$CM_MIRROR/pkg/codebase-memory-mcp" <<EOF
#!/bin/sh
echo "\$* | cwd=\$(pwd)" >> "$CM_LOG"
case "\$1" in cli|config) shift ;; esac
[ "\$1" = --quiet ] && shift
case "\$1" in
  index_repository)
    if [ -n "\${CM_FAKE_FAIL:-}" ]; then echo '{"error":"boom: parser crashed"}'; exit 1; fi
    echo '{"project":"fake","nodes":12,"edges":34,"status":"indexed"}' ;;
  list_projects) printf '{"projects":[{"name":"fake-project","root_path":"%s"}]}\n' "\$(pwd)" ;;
  get) case "\$2" in ui_enabled) echo "\${CM_FAKE_UI:-true}" ;; ui_port) echo 9749 ;; esac ;;
esac
exit 0
EOF
chmod +x "$CM_MIRROR/pkg/codebase-memory-mcp"
echo 'MIT License' > "$CM_MIRROR/pkg/LICENSE"
tar -czf "$CM_MIRROR/codebase-memory-mcp-$CM_FILE" -C "$CM_MIRROR/pkg" codebase-memory-mcp LICENSE
CODEBASE_MEMORY_SHA256="$(perl -MDigest::SHA -e 'print Digest::SHA->new(256)->addfile($ARGV[0], "b")->hexdigest' "$CM_MIRROR/codebase-memory-mcp-$CM_FILE")"
export CODEBASE_MEMORY_MIRROR="file://$CM_MIRROR" CODEBASE_MEMORY_SHA256
CM_BIN="$HOME/.codebase-memory/versions/$CM_VERSION/codebase-memory-mcp"
