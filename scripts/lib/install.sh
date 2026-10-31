# The two top-level flows: install (also re-run / update) and uninstall, run
# as pipeline stages (lib/pipeline.sh). --check is lib/check.sh.

cmd_install() {
  local t removed="" n
  lock_snapshot
  resolve_stacks
  # agents a previous run set up but this run didn't select
  for t in $(normalize_targets "$(prev_locked targets)" | tr ',' ' '); do
    has_target "$t" || removed="$removed, $t"
  done
  n=$((6 + $(echo "$TARGETS" | tr ',' '\n' | grep -c .) + 1))
  [ -n "$removed" ] && n=$((n + 1))
  pipeline_start "$n"

  stage_begin fetch
  cleanup_legacy
  fetch_superpowers
  # every download before anything rewrites the lock: a failed fetch leaves
  # the project as it was
  if [ "$SECURITY_AUDIT" -eq 1 ]; then fetch_security_audit; fi
  if needs_ecc; then fetch_ecc; fi
  stage_end "superpowers $SP_VERSION"

  stage_begin skills
  install_skills
  if needs_ecc; then install_ecc_skills; fi
  stage_end "$(lock_count skill) skills $(arrow) .agents/skills"

  stage_begin security
  install_security_audit
  # the instruction blocks list every locked skill, the security ones included
  write_blocks
  stage_end "$SECURITY_AUDIT_STATUS"

  stage_begin agents
  install_agents
  n="$(lock_count agent)"
  if [ "$n" -eq 0 ]; then stage_end "skipped"
  elif [ "$AGENTS" -eq 1 ]; then stage_end "$n subagents · ECC $ECC_VERSION"
  else stage_end "$n subagents"
  fi

  stage_begin ripgrep
  setup_ripgrep
  stage_end "$RG_STATUS"

  stage_begin "code map"
  setup_code_map
  stage_end "$CM_STATUS"

  for t in $(target_list); do
    has_target "$t" || continue
    stage_begin "$t"
    target_setup "$t"
    stage_end "$(target_summary "$t")"
  done

  stage_begin vscode
  if setup_vscode_extensions; then stage_end "extension recommendations"; else stage_end "skipped"; fi
  if [ "$LINK_MODE" = "symlink" ] && { has_target claude || has_target copilot; } && [ -d "$PROJECT_DIR/.git" ] \
     && [ "$(git -C "$PROJECT_DIR" config --get core.symlinks || echo true)" = "false" ]; then
    warn "git core.symlinks=false — teammates on Windows should re-run with --copy"
  fi

  if [ -n "$removed" ]; then
    stage_begin cleanup
    for t in $(echo "${removed#, }" | tr -d ' ' | tr ',' ' '); do target_teardown "$t"; done
    stage_end "removed: ${removed#, }"
  fi
  pipeline_end
  print_summary
}

# summary_row LABEL VALUE — one label/value line of the summary
summary_row() { printf '   %s%-8s%s %s\n' "$(sgr 2)" "$1" "$(sgr 0)" "$2"; }

print_summary() {
  local t tools=0 skills agents guards="" steps=() i update
  tools="$(echo "$TARGETS" | tr ',' '\n' | grep -c .)"
  skills="$(lock_count skill)"
  agents="$(lock_count agent)"
  if pretty; then
    printf ' %s✦ Ready%s  %s tools · %s skills · %s subagents · %s warnings\n\n' \
      "$(sgr '1;35')" "$(sgr 0)" "$tools" "$skills" "$agents" "$WARN_COUNT"
  else
    printf '\nready in %ss: %s tools, %s skills, %s subagents, %s warnings\n\n' \
      "$PIPE_ELAPSED" "$tools" "$skills" "$agents" "$WARN_COUNT"
  fi

  if [ "$SECRET_GUARD" -eq 1 ] && any_target claude copilot cursor codex antigravity; then guards="secrets blocked"; fi
  if [ "$RIPGREP" -eq 1 ] && any_target claude copilot cursor codex antigravity; then
    guards="${guards:+$guards · }searches $(arrow) rg"
  fi
  summary_row guards "${guards:-none}"
  summary_row stacks "$([ -n "$STACKS" ] && echo "$STACKS" | sed 's/,/ · /g' || echo "none (--stacks LIST to add some)")"

  steps+=("commit the generated files")
  has_target claude && steps+=("Claude Code: trust the folder")
  has_target codex && steps+=("Codex: trust the project, approve hooks in /hooks")
  has_target cursor && steps+=("Cursor: needs bash and perl on PATH")
  case "$RG_STATUS" in not\ installed*) steps+=("install ripgrep (rg), or re-run with RIPGREP_MIRROR") ;; esac
  case "${CM_STATUS:-}" in not\ installed*) steps+=("install codebase-memory, or re-run with CODEBASE_MEMORY_MIRROR") ;; esac
  if [ "$SECURITY_AUDIT" -eq 1 ] && ! have node; then steps+=("install Node.js for /release-audit's report validators"); fi
  steps+=("ask \"Let's build a todo app\"")
  for i in "${!steps[@]}"; do
    if [ "$i" -eq 0 ]; then summary_row next "$((i + 1))  ${steps[i]}"
    else summary_row "" "$((i + 1))  ${steps[i]}"
    fi
  done

  summary_row run "/brainstorming  /writing-plans  /systematic-debugging"
  has_target codex && summary_row "" "Codex: \$brainstorming  \$writing-plans"
  if [ "$CODE_MAP" -eq 1 ]; then summary_row map "$CM_WRAPPER ui  (the code graph in your browser)"; fi
  if [ "$SECURITY_AUDIT" -eq 1 ]; then
    summary_row audit "/release-audit staging|uat|prod  (reports in .security-audit/)"
  fi
  # the full -t list when it fits; a re-run in a terminal preselects the
  # project's agents anyway
  update="$0 -t $TARGETS --ref <tag> ."
  [ $((${#update} + 12)) -le 80 ] || update="$0 --ref <tag> ."
  summary_row update "$update"
  echo
}

cmd_uninstall() {
  local t name was
  lock_snapshot
  was=" $(normalize_targets "$(prev_locked targets)" | tr ',' ' ') "
  pipeline_start $(($(target_list | wc -w) + 2))
  # every tool's teardown runs, so leftovers of a lost lock are cleaned too
  for t in $(target_list); do
    stage_begin "$t"
    target_teardown "$t"
    case "$was" in *" $t "*) stage_end "removed" ;; *) stage_end "not set up" ;; esac
  done

  stage_begin skills
  remove_legacy_shared_hook
  remove_ripgrep
  remove_code_map
  remove_security_audit_files
  name="$(lock_count skill)"
  for t in $(locked_skills); do rm -rf "${SKILLS_DIR:?}/$t"; done
  [ -d "$PROJECT_DIR/.superpowers" ] && rm -rf "$PROJECT_DIR/.superpowers"
  stage_end "$name skills · ripgrep · code map"

  stage_begin agents
  name="$(lock_count agent)"
  remove_agents
  rmdir "$PROJECT_DIR/.claude" "$PROJECT_DIR/.github" "$PROJECT_DIR/.codex" 2>/dev/null || true
  rm -f "$LOCK_FILE"
  rmdir "$SKILLS_DIR" "$PROJECT_DIR/.agents" 2>/dev/null || true
  stage_end "$name subagents · lock file"
  pipeline_end
  if pretty; then printf ' %s✦ Removed%s  .vscode/ settings were left in place\n\n' "$(sgr '1;35')" "$(sgr 0)"
  else printf '\nremoved in %ss (.vscode/ settings were left in place)\n' "$PIPE_ELAPSED"
  fi
}
