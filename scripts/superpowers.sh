#!/usr/bin/env bash
# superpowers.sh — set up Superpowers (https://github.com/obra/superpowers) in a
# project, using each agent's documented project-level mechanism. Writes only
# inside the project: no plugins, marketplaces or user-level config, so it also
# works on locked-down machines. Re-runnable: re-runs update, sync the agent
# selection, and leave anything that isn't ours alone. The code map
# (codebase-memory-mcp, lib/codemap.sh) is the one thing it installs outside
# the project: a pinned binary per machine, shared by every project.
#
#   lib/        the steps, in layers; a file calls into its own layer or the
#               ones above it, never below, and no calls go round in a cycle:
#                 ui, pipeline                    terminal output
#                 files, json, fetch, lock        files, configs, downloads, the lock
#                 skills, security, agents, stacks, ripgrep, codemap, mcp, hooks,
#                 targets, legacy (+ targets/)    what gets set up
#                 install, check, picker          the modes (cmd_install, ...) and the picker
#   targets/    one file per agent: setup_<agent> + teardown_<agent>
#   tests/      offline test suite (tests/run.sh, cases in tests/cases/)
#   templates/  files copied into the project: hooks, wrapper, skill, agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

REPO_URL="https://github.com/obra/superpowers.git"
# Subagents and skills from everything-claude-code (MIT): lib/agents.sh, lib/stacks.sh.
ECC_REPO_URL="https://github.com/affaan-m/everything-claude-code.git"
# Security audits: Cloudflare's security-audit skill (MIT), pinned to a commit
# (the repo has no release tags). Adds the /release-audit skill and the
# security-auditor agent (scripts/templates).
SECURITY_AUDIT_REPO_URL="https://github.com/cloudflare/security-audit-skill.git"
BEGIN_MARK="<!-- superpowers:begin -->"
END_MARK="<!-- superpowers:end -->"

# Defaults. Versions are pinned so every teammate gets the same files.
PROJECT_DIR="."
TARGETS=""
TARGETS_SET=0
INTERACTIVE="auto"
REF="v7.0.1"
SOURCE=""
ECC_REF="v2.2.3"
ECC_SOURCE=""
SECURITY_AUDIT_REF="c1c8a8c1471069fb0e188eeaff69b8e8db6564a8"
SECURITY_AUDIT_SOURCE=""
SECURITY_AUDIT=1
LINK_MODE="symlink"
AGENTS=1
SECRET_GUARD=1
RIPGREP=1
CODE_MAP=1
STACKS="auto"
ECC_SKILLS=1
FORCE=0
UNINSTALL=0
CHECK=0
VERBOSE=0

for f in "$SCRIPT_DIR"/lib/*.sh "$SCRIPT_DIR"/targets/*.sh; do
  # shellcheck source=/dev/null
  . "$f"
done

usage() {
  cat <<EOF
Usage: $0 [options] [project-dir]

Options:
  -t, --targets LIST    Comma-separated agents to set up
                        ($ALL_TARGETS | all)
                        default: ask interactively (all when not in a terminal)
  -i, --interactive     Always show the agent picker
  -y, --yes             Never prompt; use --targets or all agents
  -r, --ref REF         Superpowers git tag/branch for the vendored skills (default: $REF)
  -s, --source PATH     Use a local Superpowers checkout instead of cloning
      --copy            Copy skills into .claude/skills and .github/skills instead
                        of symlinking (Windows)
      --no-agents       Skip the ECC subagents (.claude/, .github/, .codex/, .gemini/, .cursor/, .agents/agents)
      --stacks LIST     Stacks whose ECC reviewers, build fixers and skills to add
                        (auto | none | comma-separated: $(echo "$STACK_ALL" | tr " " ","))
                        default: auto, detected from the project's manifest files
      --no-ecc-skills   Skip the ECC skills (api-design, ... and the stacks' skills)
      --no-secret-guard Skip the hook that blocks reading secret files (.env, keys, ...)
      --no-ripgrep      Don't set up ripgrep (rg) or tell the agents to search with it
      --no-code-map     Skip the codebase-memory code map (MCP server, graph UI)
      --ecc-ref REF     everything-claude-code tag/branch for the subagents (default: $ECC_REF)
      --ecc-source PATH Use a local everything-claude-code checkout instead of cloning
      --no-security-audit
                        Skip the security-audit skill, /release-audit and the
                        security-auditor agent
      --security-audit-ref REF
                        security-audit-skill commit/branch (default: ${SECURITY_AUDIT_REF:0:7})
      --security-audit-source PATH
                        Use a local security-audit-skill checkout instead of cloning
  -f, --force           Overwrite existing skill dirs / agent files with the same name
  -v, --verbose         List every file written
      --check           Exit 1 if the generated files differ from what a re-run
                        with the lock's targets and options would write (for CI)
  -u, --uninstall       Remove everything the bootstrap added
  -h, --help            Show this help

Examples:
  $0 ~/code/my-app
  $0 -t claude,codex,cursor .
  $0 --ref main --ecc-ref main .   # latest instead of pinned
  $0 --check .                    # CI: are the generated files up to date?
  $0 --uninstall .
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -t|--targets) TARGETS="${2:?--targets needs a value}"; TARGETS_SET=1; shift 2 ;;
    -i|--interactive) INTERACTIVE="yes"; shift ;;
    -y|--yes) INTERACTIVE="no"; shift ;;
    -r|--ref) REF="${2:?--ref needs a value}"; shift 2 ;;
    -s|--source) SOURCE="${2:?--source needs a value}"; shift 2 ;;
    --copy) LINK_MODE="copy"; shift ;;
    --no-agents) AGENTS=0; shift ;;
    --stacks) STACKS="${2:?--stacks needs a value}"; shift 2 ;;
    --no-ecc-skills) ECC_SKILLS=0; shift ;;
    --no-secret-guard) SECRET_GUARD=0; shift ;;
    --no-ripgrep) RIPGREP=0; shift ;;
    --no-code-map) CODE_MAP=0; shift ;;
    --ecc-ref) ECC_REF="${2:?--ecc-ref needs a value}"; shift 2 ;;
    --ecc-source) ECC_SOURCE="${2:?--ecc-source needs a value}"; shift 2 ;;
    --no-security-audit) SECURITY_AUDIT=0; shift ;;
    --security-audit-ref) SECURITY_AUDIT_REF="${2:?--security-audit-ref needs a value}"; shift 2 ;;
    --security-audit-source) SECURITY_AUDIT_SOURCE="${2:?--security-audit-source needs a value}"; shift 2 ;;
    -f|--force) FORCE=1; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -u|--uninstall) UNINSTALL=1; shift ;;
    --check) CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *) PROJECT_DIR="$1"; shift ;;
  esac
done

have perl || die "perl is required (it ships with macOS, Linux and Git for Windows)"
# absolute when it exists already (the header shows it before anything is created)
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd || echo "$PROJECT_DIR")"
if [ "$CHECK" -eq 1 ]; then header check
elif [ "$UNINSTALL" -eq 1 ]; then header uninstall
else header install
fi

if [ "$UNINSTALL" -eq 0 ] && [ "$CHECK" -eq 0 ] && { [ "$INTERACTIVE" = "yes" ] \
     || { [ "$INTERACTIVE" = "auto" ] && [ "$TARGETS_SET" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; }; }; then
  { : > /dev/tty; } 2>/dev/null || die "no terminal available for --interactive; use --targets"
  choose_targets
fi

case "$TARGETS" in ""|all) TARGETS="$ALL_TARGETS" ;; esac
TARGETS="$(normalize_targets "$TARGETS")"
for t in $(echo "$TARGETS" | tr ',' ' '); do
  case ",$ALL_TARGETS," in *",$t,"*) ;; *) die "unknown target: $t" ;; esac
done

mkdir -p "$PROJECT_DIR"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
SKILLS_DIR="$PROJECT_DIR/.agents/skills"
LOCK_FILE="$PROJECT_DIR/$LOCK_REL"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [ "$CHECK" -eq 1 ]; then cmd_check
elif [ "$UNINSTALL" -eq 1 ]; then cmd_uninstall
else cmd_install
fi
