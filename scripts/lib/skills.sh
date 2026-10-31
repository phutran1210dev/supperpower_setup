# Superpowers skills: real files in .agents/skills (Codex, Cursor, Gemini,
# Antigravity and Devin read it), mirrored into .claude/skills and
# .github/skills, and tracked in the lock (lock.sh) as skill: lines so re-runs
# and uninstall touch only ours. The security and ECC skills (security.sh,
# stacks.sh) join them there.

# claim_skill NAME — make room for our NAME in .agents/skills: false, with a
# warning, when the skill there is the user's own (not in the last lock)
# and --force wasn't given
claim_skill() {
  if [ -e "$SKILLS_DIR/$1" ] && ! prev_locked skill | grep -qx "$1" && [ "$FORCE" -ne 1 ]; then
    warn ".agents/skills/$1 already exists and is not from the bootstrap — skipped (use --force)"
    return 1
  fi
  rm -rf "${SKILLS_DIR:?}/$1"
}

frontmatter_field() { # frontmatter_field FILE KEY
  awk -v k="$2" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v)
      gsub(/^["\x27]|["\x27]$/, "", v); print v; exit
    }' "$1"
}

skill_body() { # SKILL.md without its frontmatter
  awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } !fm' "$1"
}

fetch_superpowers() {
  local src="$SOURCE"
  if [ -z "$src" ]; then
    have git || die "git is required (or pass --source PATH)"
    git_clone --depth 1 --branch "$REF" "$REPO_URL" "$TMP_DIR/src" \
      || die "could not clone $REPO_URL at '$REF'"
    src="$TMP_DIR/src"
  fi
  [ -d "$src/skills/using-superpowers" ] || die "$src does not look like a Superpowers checkout"
  SRC_DIR="$src"
  SP_VERSION="$(checkout_version "$src" .claude-plugin/plugin.json)"
}

install_skills() {
  local s name names kept=""
  mkdir -p "$SKILLS_DIR"
  for s in "$SRC_DIR"/skills/*/; do
    name="$(basename "$s")"
    claim_skill "$name" || continue
    cp -R "$s" "$SKILLS_DIR/$name"
    kept="$kept$name"$'\n'
  done
  # Skills cross-reference each other as `superpowers:<skill>` (the plugin
  # namespace). Project skills have no namespace, so rewrite to `<skill>`.
  names="$(printf '%s' "$kept" | paste -sd '|' -)"
  if [ -n "$names" ]; then
    for name in $(printf '%s' "$kept"); do
      { grep -rlE "superpowers:($names)" "$SKILLS_DIR/$name" 2>/dev/null || true; } | while IFS= read -r f; do
        perl -pi -e "s/superpowers:($names)\\b/\$1/g" "$f"
      done
    done
  fi
  # drop skills an older Superpowers version had but this one doesn't
  for name in $(prev_locked skill); do
    printf '%s' "$kept" | grep -qx "$name" || rm -rf "${SKILLS_DIR:?}/$name"
  done
  lock_start
  lock_add skill "$kept"
  ok ".agents/skills/ ($(printf '%s' "$kept" | grep -c .) skills) + $LOCK_REL"
}

# expose_skills DIR — mirror .agents/skills/<ours> into another skills dir
expose_skills() {
  local rel="$1" dir="$PROJECT_DIR/$1" name p
  mkdir -p "$dir"
  # ours, for skills the last run installed and this one didn't
  # (--no-security-audit, a skill an older Superpowers had); never a link of
  # the user's own
  for name in $(prev_locked skill); do
    is_locked "$name" && continue
    p="$dir/$name"
    if [ -L "$p" ]; then
      case "$(readlink "$p")" in *".agents/skills/"*) rm -f "$p" ;; esac
    elif [ -f "$p/.superpowers-managed" ]; then
      rm -rf "$p"
    fi
  done
  for name in $(locked_skills); do
    if [ -e "$dir/$name" ] || [ -L "$dir/$name" ]; then
      if [ ! -L "$dir/$name" ] && [ "$FORCE" -ne 1 ] && ! [ -f "$dir/$name/.superpowers-managed" ]; then
        warn "$rel/$name exists and is not from the bootstrap — skipped (use --force)"
        continue
      fi
      rm -rf "${dir:?}/$name"
    fi
    if [ "$LINK_MODE" = "symlink" ]; then
      ln -s "../../.agents/skills/$name" "$dir/$name"
    else
      cp -R "$SKILLS_DIR/$name" "$dir/$name"
      : > "$dir/$name/.superpowers-managed"
    fi
  done
  ok "$rel/ ($LINK_MODE → .agents/skills)"
}

# unexpose_skills DIR — remove our symlinks/copies (and DIR and its parent if empty)
unexpose_skills() {
  local dir="$PROJECT_DIR/$1" p
  [ -d "$dir" ] || return 0
  for p in "$dir"/*; do
    if [ -L "$p" ]; then
      case "$(readlink "$p")" in *".agents/skills/"*|*".superpowers/skills/"*) rm -f "$p" ;; esac
    elif [ -f "$p/.superpowers-managed" ]; then
      rm -rf "$p"
    fi
  done
  rmdir "$dir" "$(dirname "$dir")" 2>/dev/null || true
}

# write_block OUT FULL(0|1) [AGENT MAPPING] — the instructions block: the rule,
# the skill table and, when FULL, the using-superpowers body. Per the
# Superpowers porting guide, agents with their own tool names (Codex,
# Antigravity) get a pointer to their tool-mapping reference.
write_block() {
  local out="$1" full="$2" agent="${3:-}" mapping="${4:-}" name desc
  {
    echo "$BEGIN_MARK"
    echo "## Superpowers"
    echo
    echo "This project uses [Superpowers](https://github.com/obra/superpowers) ($SP_VERSION) —"
    echo "a library of process skills for coding agents. Managed by the Superpowers bootstrap; do not edit inside this block."
    echo
    echo "**Rule:** before any response or action — including clarifying questions — check whether a skill below applies."
    echo "If one does, load it (native skill tool if you have one, otherwise read \`.agents/skills/<name>/SKILL.md\` in full),"
    echo "announce \"Using <skill> to <purpose>\", and follow it exactly."
    search_rule
    code_map_rule
    if [ -n "$mapping" ]; then
      echo "**$agent:** skills are written with Claude Code tool names — read \`.agents/skills/using-superpowers/references/$mapping\` for the $agent equivalents."
    fi
    echo
    echo "| Skill | Use when |"
    echo "|---|---|"
    for name in $(locked_skills); do
      desc="$(frontmatter_field "$SKILLS_DIR/$name/SKILL.md" description | sed 's/|/\\|/g')"
      echo "| \`$name\` | $desc |"
    done
    if [ "$full" = "1" ]; then
      echo
      echo "### using-superpowers"
      # Drop "Platform Adaptation": it lists other harnesses' mapping files
      # (pi, hermes, ...) that don't apply to the agents reading this block.
      skill_body "$SKILLS_DIR/using-superpowers/SKILL.md" \
        | awk '/^## Platform Adaptation/ { skip = 1; next } skip && /^## / { skip = 0 } !skip'
    fi
    echo "$END_MARK"
  } > "$out"
}

# write_blocks — the block variants the agents use
write_blocks() {
  write_block "$TMP_DIR/block-short.md" 0 "Codex" "codex-tools.md"
  write_block "$TMP_DIR/block-claude.md" 0
  write_block "$TMP_DIR/block-full.md" 1
  write_block "$TMP_DIR/block-antigravity.md" 1 "Antigravity" "antigravity-tools.md"
}

# write_rule REL_PATH FRONTMATTER BLOCK — a whole-file rule: frontmatter + block
write_rule() {
  mkdir -p "$(dirname "$PROJECT_DIR/$1")"
  { printf -- '---\n%s\n---\n\n' "$2"; cat "$TMP_DIR/$3"; } > "$PROJECT_DIR/$1"
  ok "$1"
}
