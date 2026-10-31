# Security audits, separate from Superpowers: Cloudflare's security-audit skill
# (MIT) and the /release-audit skill (templates/release-audit) in
# .agents/skills, the security-auditor agent (lib/agents.sh) and the
# git-ignored .security-audit/ folder for reports. The skill writes reports
# inside the repository only when version control ignores the whole directory
# (its SKILL.md, "Full audit setup"), hence the folder's own .gitignore, which
# is committed so every clone ignores the reports too.

SECURITY_AUDIT_SKILLS="security-audit release-audit"
SECURITY_AUDIT_IGNORE=".security-audit/.gitignore"
SECURITY_AUDIT_LICENSE=".agents/licenses/security-audit-skill.LICENSE"

fetch_security_audit() {
  local src="$SECURITY_AUDIT_SOURCE"
  if [ -z "$src" ]; then
    have git || die "git is required (or pass --security-audit-source PATH)"
    src="$TMP_DIR/security-audit"
    # fetch rather than clone: the ref is a commit, which clone --branch can't take
    if ! { git init --quiet "$src" && git -C "$src" fetch --quiet --depth 1 "$SECURITY_AUDIT_REPO_URL" "$SECURITY_AUDIT_REF" \
           && git -C "$src" checkout --quiet FETCH_HEAD; } 2> "$TMP_DIR/git.err"; then
      show_errors "$TMP_DIR/git.err"
      die "could not fetch $SECURITY_AUDIT_REPO_URL at '$SECURITY_AUDIT_REF' (or pass --no-security-audit)"
    fi
  fi
  [ -f "$src/skills/security-audit/SKILL.md" ] || die "$src does not look like a security-audit-skill checkout"
  SECURITY_AUDIT_DIR="$src"
  SECURITY_AUDIT_VERSION="$(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo local)"
}

# install_security_audit — after fetch_security_audit and install_skills:
# copies the two skills and appends their skill: lines (and the commit) to the
# lock, so expose_skills, the instruction blocks and uninstall treat them like
# the others. With --no-security-audit, install_skills has already removed
# the skills.
install_security_audit() {
  local name kept=""
  SECURITY_AUDIT_STATUS="skipped"
  if [ "$SECURITY_AUDIT" -eq 0 ]; then
    remove_security_audit_files
    return 0
  fi
  for name in $SECURITY_AUDIT_SKILLS; do
    claim_skill "$name" || continue
    case "$name" in
      security-audit) cp -R "$SECURITY_AUDIT_DIR/skills/security-audit" "$SKILLS_DIR/$name" ;;
      release-audit)  cp -R "$TEMPLATES_DIR/release-audit" "$SKILLS_DIR/$name" ;;
    esac
    kept="$kept$name"$'\n'
  done
  mkdir -p "$PROJECT_DIR/.agents/licenses"
  cp "$SECURITY_AUDIT_DIR/LICENSE" "$PROJECT_DIR/$SECURITY_AUDIT_LICENSE"
  install_template security-audit.gitignore "$SECURITY_AUDIT_IGNORE"
  lock_add security-audit "$SECURITY_AUDIT_VERSION"
  lock_add skill "$kept"
  SECURITY_AUDIT_STATUS="$(printf '%s' "$kept" | grep -c . || true) skills · security-audit-skill @ $SECURITY_AUDIT_VERSION"
  ok ".agents/skills/ (security-audit, release-audit)"
}

# remove_security_audit_files — the license and the reports folder's ignore
# file. The ignore file stays while the folder holds reports, so they can't
# be committed by accident.
remove_security_audit_files() {
  local dir="$PROJECT_DIR/.security-audit"
  rm -f "$PROJECT_DIR/$SECURITY_AUDIT_LICENSE"
  rmdir "$PROJECT_DIR/.agents/licenses" 2>/dev/null || true
  [ -f "$PROJECT_DIR/$SECURITY_AUDIT_IGNORE" ] || return 0
  [ -z "$(ls -A "$dir" | grep -vx '.gitignore')" ] || return 0
  cmp -s "$PROJECT_DIR/$SECURITY_AUDIT_IGNORE" "$TEMPLATES_DIR/security-audit.gitignore" || return 0
  rm -f "$PROJECT_DIR/$SECURITY_AUDIT_IGNORE"
  rmdir "$dir" 2>/dev/null || true
}
