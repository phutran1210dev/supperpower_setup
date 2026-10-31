# Stack-aware extras from everything-claude-code (MIT): the project's stacks are
# detected from its manifest files (package.json, go.mod, Cargo.toml, ...), and
# each brings ECC's reviewer and build-resolver agents for it plus the ECC
# skills those agents point at. Every project also gets a few general ECC
# skills Superpowers has no counterpart for (ECC_SKILLS_COMMON). Skills go in
# .agents/skills next to Superpowers' and are locked as skill: lines, so the
# instruction blocks, expose_skills and uninstall treat them like the others.
#
# --stacks LIST|auto|none picks the stacks by hand; the lock records the ones
# used, so --check (which re-runs on a copy without the manifests) reproduces
# them. --no-ecc-skills leaves the ECC skills out.

STACK_ALL="typescript react vue python django fastapi go rust java spring quarkus kotlin swift flutter cpp csharp php laravel ruby rails"
ECC_SKILLS_COMMON="api-design database-migrations error-handling deployment-patterns docker-patterns e2e-testing codebase-onboarding"

# stack_agents STACK / stack_skills STACK — what a stack brings (the skills are
# the ones its agents refer to, plus its testing skill where ECC has one)
stack_agents() {
  case "$1" in
    typescript) echo "typescript-reviewer" ;;
    react)      echo "react-reviewer react-build-resolver" ;;
    vue)        echo "vue-reviewer" ;;
    python)     echo "python-reviewer" ;;
    django)     echo "django-reviewer django-build-resolver" ;;
    fastapi)    echo "fastapi-reviewer" ;;
    go)         echo "go-reviewer go-build-resolver" ;;
    rust)       echo "rust-reviewer rust-build-resolver" ;;
    java)       echo "java-reviewer java-build-resolver" ;;
    kotlin)     echo "kotlin-reviewer kotlin-build-resolver" ;;
    swift)      echo "swift-reviewer swift-build-resolver" ;;
    flutter)    echo "flutter-reviewer dart-build-resolver" ;;
    cpp)        echo "cpp-reviewer cpp-build-resolver" ;;
    csharp)     echo "csharp-reviewer" ;;
    php)        echo "php-reviewer" ;;
    ruby)       echo "ruby-reviewer" ;;
  esac
}

stack_skills() {
  case "$1" in
    typescript) echo "coding-standards backend-patterns frontend-patterns" ;;
    react)      echo "react-patterns react-testing frontend-patterns accessibility" ;;
    vue)        echo "vue-patterns accessibility" ;;
    python)     echo "python-patterns python-testing" ;;
    django)     echo "django-patterns django-security django-tdd" ;;
    fastapi)    echo "fastapi-patterns" ;;
    go)         echo "golang-patterns golang-testing" ;;
    rust)       echo "rust-patterns rust-testing" ;;
    java)       echo "java-coding-standards" ;;
    spring)     echo "springboot-patterns" ;;
    quarkus)    echo "quarkus-patterns" ;;
    kotlin)     echo "kotlin-patterns kotlin-testing" ;;
    swift)      echo "swiftui-patterns swift-concurrency-6-2 swift-protocol-di-testing swift-actor-persistence" ;;
    flutter)    echo "flutter-dart-code-review dart-flutter-patterns accessibility" ;;
    cpp)        echo "cpp-coding-standards cpp-testing" ;;
    csharp)     echo "dotnet-patterns csharp-testing" ;;
    laravel)    echo "laravel-patterns laravel-security laravel-tdd" ;;
    rails)      echo "rails-patterns" ;;
  esac
}

# project_files — the project's files: git's view (tracked, plus untracked
# but not ignored, so node_modules/ and build output stay out), else a
# shallow walk
project_files() {
  if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    git -C "$PROJECT_DIR" ls-files --cached --others --exclude-standard 2>/dev/null
  else
    (cd "$PROJECT_DIR" && find . -maxdepth 6 \( -name node_modules -o -name vendor -o -name .git -o -name .venv -o -name venv \
       -o -name build -o -name dist -o -name target -o -name Pods -o -name .gradle \) -prune \
       -o -type f -print 2>/dev/null | sed 's|^\./||')
  fi
}

# the project's files while detect_stacks runs
STACK_FILES=""

# stack_files_matching FILE_RE — the project files whose path matches FILE_RE
stack_files_matching() { printf '%s\n' "$STACK_FILES" | grep -E "(^|/)($1)\$" || true; }

# stack_file_mentions FILE_RE CONTENT_RE — one of those files contains CONTENT_RE
stack_file_mentions() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] && grep -Eqi -- "$2" "$PROJECT_DIR/$f" 2>/dev/null && return 0
  done <<< "$(stack_files_matching "$1")"
  return 1
}

# detect_stacks — the stacks of the project at PROJECT_DIR, in STACK_ALL order
detect_stacks() {
  local found="" s
  STACK_FILES="$(project_files)"
  local py='pyproject\.toml|requirements[^/]*\.txt|setup\.py|setup\.cfg|Pipfile'
  local jvm='pom\.xml|build\.gradle|build\.gradle\.kts|settings\.gradle|settings\.gradle\.kts'
  for s in $STACK_ALL; do
    case "$s" in
      typescript) [ -n "$(stack_files_matching 'package\.json|tsconfig\.json')" ] ;;
      react)      stack_file_mentions 'package\.json' '"(react|next|react-native)"[[:space:]]*:' ;;
      vue)        stack_file_mentions 'package\.json' '"(vue|nuxt)"[[:space:]]*:' ;;
      python)     [ -n "$(stack_files_matching "$py")" ] ;;
      django)     [ -n "$(stack_files_matching 'manage\.py')" ] || stack_file_mentions "$py" '(^|[^a-z])django([^a-z_-]|$)' ;;
      fastapi)    stack_file_mentions "$py" '(^|[^a-z])fastapi([^a-z_-]|$)' ;;
      go)         [ -n "$(stack_files_matching 'go\.mod')" ] ;;
      rust)       [ -n "$(stack_files_matching 'Cargo\.toml')" ] ;;
      java)       [ -n "$(stack_files_matching 'pom\.xml|[^/]+\.java')" ] ;;  # build.gradle alone: Android is Kotlin
      spring)     stack_file_mentions "$jvm" 'spring-boot|org\.springframework' ;;
      quarkus)    stack_file_mentions "$jvm" 'quarkus' ;;
      kotlin)     [ -n "$(stack_files_matching 'build\.gradle\.kts|[^/]+\.kt')" ] ;;
      swift)      [ -n "$(stack_files_matching 'Package\.swift|[^/]+\.swift')" ] ;;
      flutter)    [ -n "$(stack_files_matching 'pubspec\.yaml')" ] ;;
      cpp)        [ -n "$(stack_files_matching 'CMakeLists\.txt|meson\.build|conanfile\.(txt|py)|vcpkg\.json')" ] ;;
      csharp)     [ -n "$(stack_files_matching '[^/]+\.(csproj|sln)')" ] ;;
      php)        [ -n "$(stack_files_matching 'composer\.json')" ] ;;
      laravel)    [ -n "$(stack_files_matching 'artisan')" ] || stack_file_mentions 'composer\.json' '"laravel/framework"' ;;
      ruby)       [ -n "$(stack_files_matching 'Gemfile|[^/]+\.gemspec')" ] ;;
      rails)      [ -n "$(stack_files_matching 'bin/rails')" ] || stack_file_mentions 'Gemfile' 'gem[[:space:]]+["'"'"']rails["'"'"']' ;;
    esac && found="$found,$s"
  done
  echo "${found#,}"
}

# resolve_stacks — STACKS (auto | none | a list) as the list this run uses
resolve_stacks() {
  local s
  case "$STACKS" in
    auto) STACKS="$(detect_stacks)" ;;
    none) STACKS="" ;;
    *)
      for s in $(echo "$STACKS" | tr ',' ' '); do
        case " $STACK_ALL " in *" $s "*) ;; *) die "unknown stack: $s (one of: $STACK_ALL)" ;; esac
      done
      # canonical order, no repeats, so the lock is the same however it was typed
      # (a loop, not $(... case ...): bash 3.2 can't parse that)
      local given=",$STACKS,"
      STACKS=""
      for s in $STACK_ALL; do
        case "$given" in *",$s,"*) STACKS="$STACKS,$s" ;; esac
      done
      STACKS="${STACKS#,}"
      ;;
  esac
}

# stack_agent_names / ecc_skill_names — this run's ECC agents and skills
stack_agent_names() {
  local s
  for s in $(echo "$STACKS" | tr ',' ' '); do stack_agents "$s"; done | tr ' ' '\n' | grep . | awk '!seen[$0]++'
  return 0
}

ecc_skill_names() {
  local s
  [ "$ECC_SKILLS" -eq 1 ] || return 0
  { echo "$ECC_SKILLS_COMMON"; for s in $(echo "$STACKS" | tr ',' ' '); do stack_skills "$s"; done; } \
    | tr ' ' '\n' | grep . | awk '!seen[$0]++'
  return 0
}

# install_ecc_skills — after install_skills: copies the ECC skills and appends
# their skill: lines to the lock (with --no-ecc-skills, or for a stack the
# project no longer has, install_skills has already removed them)
install_ecc_skills() {
  local name src kept=""
  for name in $(ecc_skill_names); do
    if ! src="$(ecc_file "skills/$name")" || [ ! -f "$src/SKILL.md" ]; then
      warn "everything-claude-code has no skills/$name — skipped"
      continue
    fi
    claim_skill "$name" || continue
    cp -R "$src" "$SKILLS_DIR/$name"
    kept="$kept$name"$'\n'
  done
  [ -n "$kept" ] || return 0
  lock_add skill "$kept"
  ok ".agents/skills/ ($(printf '%s' "$kept" | grep -c .) ECC skills)"
}
