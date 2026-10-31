# ripgrep (https://github.com/BurntSushi/ripgrep): the search tool every agent
# is told to use (the instruction blocks) and steered to (search-guard, which
# blocks grep -r / find -name in shell commands). An rg already on PATH is used
# as-is; otherwise a pinned, checksum-verified release binary goes into
# .agents/bin/ — per machine and git-ignored, so nothing is installed globally.
#
# RIPGREP_MIRROR   base URL serving the release files (default: GitHub releases)
# RIPGREP_SHA256   expected checksum when the mirror serves a different build

RG_VERSION="15.2.0"
RG_BIN_DIR=".agents/bin"

# rg_asset — "<target>.<ext> <sha256>" of the release build for this machine
rg_asset() {
  case "$(uname -s)/$(uname -m)" in
    Darwin/arm64)                echo "aarch64-apple-darwin.tar.gz 3750b2e93f37e0c692657da574d7019a101c0084da05a790c83fd335bad973e4" ;;
    Darwin/x86_64)               echo "x86_64-apple-darwin.tar.gz af7825fcc69a2afc7a7aea55fc9af90e26421d8f20fe59df32e233c0b8a231c1" ;;
    Linux/x86_64)                echo "x86_64-unknown-linux-musl.tar.gz 33e15bcf1624b25cdd2a55813a47a2f95dbe126268203e76aa6a585d1e7b149c" ;;
    Linux/aarch64|Linux/arm64)   echo "aarch64-unknown-linux-musl.tar.gz 800b1e7206afe799dfb5a6901f23147cfaabe0e52210538100f61e86e1740915" ;;
    MINGW*/x86_64|MSYS*/x86_64|CYGWIN*/x86_64)
                                 echo "x86_64-pc-windows-msvc.zip 71b2fef860abe467217a538ff31de02f5258807c0129f771846f87bd029aafc5" ;;
    MINGW*/aarch64|MSYS*/aarch64|MINGW*/arm64|MSYS*/arm64)
                                 echo "aarch64-pc-windows-msvc.zip e4abca10c3a64ebea742667dd7009449d49403db5460dd6873e389fa2945360f" ;;
  esac
}

# setup_ripgrep — make sure an rg exists; sets RG_STATUS for the summary
setup_ripgrep() {
  local bin="$PROJECT_DIR/$RG_BIN_DIR" asset file sha url name
  if [ "$RIPGREP" -eq 0 ]; then remove_ripgrep; RG_STATUS="skipped (--no-ripgrep)"; return 0; fi
  if have rg; then
    RG_STATUS="$(rg --version | head -1 | awk '{print $2}') on PATH"
    return 0
  fi
  for name in rg rg.exe; do
    if [ -x "$bin/$name" ] && "$bin/$name" --version 2>/dev/null | head -1 | grep -qF "$RG_VERSION"; then
      RG_STATUS="$RG_VERSION $(arrow) $RG_BIN_DIR (local)"
      return 0
    fi
  done
  RG_STATUS="not installed (grep/find fallback)"
  if [ -n "${SP_RG_NO_DOWNLOAD:-}" ]; then return 0; fi
  asset="$(rg_asset)"
  [ -n "$asset" ] || { warn "no ripgrep build for $(uname -s)/$(uname -m) — install rg yourself"; return 0; }
  file="${asset% *}" sha="${RIPGREP_SHA256:-${asset#* }}"
  url="${RIPGREP_MIRROR:-https://github.com/BurntSushi/ripgrep/releases/download/$RG_VERSION}/ripgrep-$RG_VERSION-$file"
  fetch_release rg "$url" "$TMP_DIR/$file" "$sha" RIPGREP_MIRROR || return 0
  mkdir -p "$TMP_DIR/rg"
  case "$file" in
    *.zip) unzip -qo "$TMP_DIR/$file" -d "$TMP_DIR/rg" 2>/dev/null \
             || { warn "unzip not found — install rg yourself"; return 0; } ;;
    *)     tar -xzf "$TMP_DIR/$file" -C "$TMP_DIR/rg" ;;
  esac
  mkdir -p "$bin"
  for name in rg rg.exe; do
    if [ -f "$TMP_DIR/rg/ripgrep-$RG_VERSION-${file%%.*}/$name" ]; then
      cp "$TMP_DIR/rg/ripgrep-$RG_VERSION-${file%%.*}/$name" "$bin/$name"
      chmod +x "$bin/$name"
    fi
  done
  # binaries are per machine: keep them out of git
  echo '*' > "$bin/.gitignore"
  RG_STATUS="$RG_VERSION $(arrow) $RG_BIN_DIR (local)"
  ok "$RG_BIN_DIR/rg"
}

remove_ripgrep() {
  rm -f "$PROJECT_DIR/$RG_BIN_DIR/rg" "$PROJECT_DIR/$RG_BIN_DIR/rg.exe" "$PROJECT_DIR/$RG_BIN_DIR/.gitignore"
  rmdir "$PROJECT_DIR/$RG_BIN_DIR" 2>/dev/null || true
}

# search_rule — the instruction line every agent gets (empty with --no-ripgrep)
search_rule() {
  [ "$RIPGREP" -eq 1 ] || return 0
  echo "**Search:** use ripgrep — \`rg PATTERN [PATH]\` for content, \`rg --files -g 'GLOB'\` for file names — instead of \`grep -r\` or \`find\` in the shell (your built-in search tools are fine). If \`rg\` is not on PATH, run \`.agents/bin/rg\`."
}

# agent_search_rule — the section every subagent ends with: find with rg, then
# read only the lines a match points to rather than whole files
agent_search_rule() {
  echo "## Search"
  echo
  echo "Search and read with ripgrep: it is fast, skips \`.gitignore\`'d files, and keeps reads small."
  echo
  agent_code_map_rule
  echo "- File names: \`rg --files -g 'GLOB'\`."
  echo "- Content: \`rg -n PATTERN [PATH]\`, narrowed with \`-t TYPE\`, \`-g 'GLOB'\`, \`-w\` or \`-F\`; \`-l\` lists file names only, \`-C 3\` adds context."
  echo "- Read only the lines a match points to, not whole files."
  echo "- Never \`grep -r\` or \`find\` in the shell. If \`rg\` is not on PATH, run \`.agents/bin/rg\`."
}
