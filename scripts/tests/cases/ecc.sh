# everything-claude-code: the review agents, stack detection and the ECC skills.

test_ecc_review_agents() {
  local d="$WORK/eccreview" a
  rm -rf "$d" && mkdir -p "$d"
  bootstrap "$d" -t claude
  for a in silent-failure-hunter pr-test-analyzer type-design-analyzer code-simplifier comment-analyzer; do
    check "$a installed" test -f "$d/.claude/agents/$a.md"
  done
  check "security-review points at security-audit" contains "$d/.claude/agents/security-reviewer.md" 'see skill: `security-audit`.'
  check "tdd-workflow points at Superpowers' TDD" contains "$d/.claude/agents/security-reviewer.md" 'skill: test-driven-development.'
  for a in api-design database-migrations error-handling deployment-patterns docker-patterns e2e-testing codebase-onboarding; do
    check "skill $a" test -f "$d/.agents/skills/$a/SKILL.md"
  done
  check "ECC skills exposed to Claude" test -L "$d/.claude/skills/api-design"
  check "ECC skills in the instructions" contains "$d/CLAUDE.md" '| `api-design` | ECC api-design skill |'
  check "no stack: none" grep -Eq '^ *stacks +none \(--stacks LIST to add some\)' "$WORK/last.log"
  check "lock records no stacks" contains "$d/.agents/superpowers.lock" "--stacks none"
  check_not "no stack agents" test -e "$d/.claude/agents/typescript-reviewer.md"

  bootstrap "$d" -t claude --no-security-audit
  check "without security-audit: reference left as is" contains "$d/.claude/agents/security-reviewer.md" 'see skill: `security-review`.'

  bootstrap "$d" -t claude --no-ecc-skills
  check "--no-ecc-skills: skills removed" test ! -e "$d/.agents/skills/api-design"
  check "--no-ecc-skills: link removed" test ! -L "$d/.claude/skills/api-design"
  check_not "--no-ecc-skills: not in the instructions" contains "$d/CLAUDE.md" 'api-design'
  check "--no-ecc-skills: agents stay" test -f "$d/.claude/agents/silent-failure-hunter.md"
  check "--no-ecc-skills recorded" contains "$d/.agents/superpowers.lock" "--no-ecc-skills"
  check "--check up to date" bootstrap "$d" --check

  bootstrap "$d" -t claude --no-agents
  check "--no-agents: ECC skills still come" test -f "$d/.agents/skills/api-design/SKILL.md"
  check "--no-agents: no ECC agents" test ! -e "$d/.claude/agents/silent-failure-hunter.md"
  check "--no-agents: ECC ref still recorded" contains "$d/.agents/superpowers.lock" "--ecc-ref"
}

test_stacks_detected() {
  local d="$WORK/stacks" a s
  rm -rf "$d" && mkdir -p "$d/web" "$d/services/api" "$d/node_modules/x"
  git -C "$d" init -q
  echo 'node_modules/' > "$d/.gitignore"
  echo '{ "dependencies": { "react": "^19.0.0" } }' > "$d/web/package.json"
  echo 'module example.com/api' > "$d/services/api/go.mod"
  # ignored: never a stack of the project's own
  echo '{ "dependencies": { "vue": "^3" } }' > "$d/node_modules/x/package.json"
  bootstrap "$d" -t claude
  check "summary lists the stacks" grep -Eq '^ *stacks +typescript · react · go$' "$WORK/last.log"
  check "lock records the stacks" contains "$d/.agents/superpowers.lock" "--stacks typescript,react,go"
  for a in typescript-reviewer react-reviewer react-build-resolver go-reviewer go-build-resolver; do
    check "agent $a" test -f "$d/.claude/agents/$a.md"
  done
  check_not "ignored files don't count" test -e "$d/.claude/agents/vue-reviewer.md"
  for s in react-patterns react-testing frontend-patterns accessibility coding-standards golang-patterns golang-testing api-design; do
    check "skill $s" test -f "$d/.agents/skills/$s/SKILL.md"
  done
  check "stack skill in the instructions" contains "$d/CLAUDE.md" '| `golang-patterns` |'
  check "--check up to date (the copy has no manifests)" bootstrap "$d" --check

  rm "$d/services/api/go.mod"
  bootstrap "$d" -t claude
  check "go gone: its agents removed" test ! -e "$d/.claude/agents/go-reviewer.md"
  check "go gone: its skills removed" test ! -e "$d/.agents/skills/golang-patterns"
  check "go gone: react stays" test -f "$d/.claude/agents/react-reviewer.md"
}

test_stacks_manual() {
  local d="$WORK/stacksman"
  rm -rf "$d" && mkdir -p "$d"
  bootstrap "$d" -t claude --stacks django,python,django
  check "canonical order, no repeats" contains "$d/.agents/superpowers.lock" "--stacks python,django"
  check "python reviewer" test -f "$d/.claude/agents/python-reviewer.md"
  check "django resolver" test -f "$d/.claude/agents/django-build-resolver.md"
  check "django skills" test -f "$d/.agents/skills/django-tdd/SKILL.md"
  check "--check keeps them" bootstrap "$d" --check
  check_not "unknown stack fails" bootstrap "$d" -t claude --stacks cobol
  check "says which" contains "$WORK/last.log" "unknown stack: cobol"
  bootstrap "$d" -t claude --stacks none
  check "none: stack agents removed" test ! -e "$d/.claude/agents/python-reviewer.md"
  check "none: stack skills removed" test ! -e "$d/.agents/skills/django-tdd"

  # outside git: a shallow walk of the project
  rm -rf "$d" && mkdir -p "$d/crate" && echo '[package]' > "$d/crate/Cargo.toml"
  bootstrap "$d" -t claude
  check "no git: rust detected" test -f "$d/.claude/agents/rust-build-resolver.md"

  # an Android app: Gradle, but Kotlin sources, so Kotlin and not Java
  rm -rf "$d" && mkdir -p "$d/android/app/src" && : > "$d/android/build.gradle" && : > "$d/android/app/src/MainActivity.kt"
  bootstrap "$d" -t claude
  check "gradle + .kt: kotlin" contains "$d/.agents/superpowers.lock" "--stacks kotlin"
  check_not "gradle + .kt: not java" test -e "$d/.claude/agents/java-reviewer.md"
}

test_ecc_own_skill_kept() {
  local d="$WORK/eccown"
  rm -rf "$d" && mkdir -p "$d/.agents/skills/api-design" && echo 'mine' > "$d/.agents/skills/api-design/SKILL.md"
  bootstrap "$d" -t claude
  check "warns" contains "$WORK/last.log" ".agents/skills/api-design already exists and is not from the bootstrap"
  check "theirs kept" test "$(cat "$d/.agents/skills/api-design/SKILL.md")" = mine
  bootstrap "$d" --uninstall
  check "theirs kept by uninstall" test "$(cat "$d/.agents/skills/api-design/SKILL.md")" = mine
}

test_ecc_next() {
  local d="$WORK/eccnext"
  rm -rf "$d" && mkdir -p "$d" && git -C "$d" init -q
  printf 'source "https://rubygems.org"\ngem "rails", "~> 8.0"\n' > "$d/Gemfile"
  check "bootstrap succeeds" bootstrap "$d" -t claude,copilot
  check "ruby and rails detected" contains "$d/.agents/superpowers.lock" "--stacks ruby,rails"
  check "commit-reviewer from main" test -f "$d/.claude/agents/commit-reviewer.md"
  check "commit-reviewer for Copilot too" test -f "$d/.github/agents/commit-reviewer.md"
  check "ruby-reviewer from main" test -f "$d/.claude/agents/ruby-reviewer.md"
  check "rails-patterns from main" test -f "$d/.agents/skills/rails-patterns/SKILL.md"
  check "summary names the pinned main commit" contains "$WORK/last.log" "+ main @ ${ECC_NEXT_REF:0:7}"
  check "--check reproduces it" bootstrap "$d" --check

  # plain Ruby: the reviewer, not the Rails skill
  rm -rf "$d" && mkdir -p "$d" && : > "$d/mygem.gemspec"
  bootstrap "$d" -t claude
  check "gemspec: ruby only" contains "$d/.agents/superpowers.lock" "--stacks ruby"
  check_not "gemspec: no rails-patterns" test -e "$d/.agents/skills/rails-patterns"

  # a tag that already has them: main is not fetched
  local tag="$WORK/ecc-tagged"
  rm -rf "$tag" && cp -R "$ECC" "$tag" && cp "$ECC_NEXT"/agents/*.md "$tag/agents/"
  rm -rf "$d" && mkdir -p "$d"
  check "tag with the agents: succeeds without main" env ECC_NEXT_SOURCE="$WORK/none" \
    bash "$BOOTSTRAP" -y -s "$SP" --ecc-source "$tag" --security-audit-source "$SA" -t claude "$d"
  check "tag's commit-reviewer used" test -f "$d/.claude/agents/commit-reviewer.md"

  # main unreachable: those agents are skipped with a warning, the rest installs
  rm -rf "$d" && mkdir -p "$d"
  ECC_NEXT_SOURCE="$WORK/none" bootstrap "$d" -t claude
  check "main unreachable: warns" contains "$WORK/last.log" "commit-reviewer"
  check "main unreachable: the rest installs" test -f "$d/.claude/agents/planner.md"
  check_not "main unreachable: no commit-reviewer" test -e "$d/.claude/agents/commit-reviewer.md"
}

test_rails_single_quotes() {
  local d="$WORK/railsq"
  rm -rf "$d" && mkdir -p "$d" && printf "gem 'rails'\n" > "$d/Gemfile"
  bootstrap "$d" -t claude
  check "gem 'rails': rails detected" contains "$d/.agents/superpowers.lock" "--stacks ruby,rails"
}
