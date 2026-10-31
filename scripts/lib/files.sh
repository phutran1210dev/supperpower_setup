# File helpers: managed blocks in instruction files, and templates copied into
# the project (JSON configs: json.sh; downloads: fetch.sh).

have() { command -v "$1" >/dev/null 2>&1; }

# upsert_block FILE BLOCK_FILE [BEGIN END] — insert or replace the managed
# block, between the lines BEGIN and END (default: the superpowers markers).
# BLOCK_FILE must start and end with them.
upsert_block() {
  local file="$1" block="$2" begin="${3:-$BEGIN_MARK}" end="${4:-$END_MARK}"
  mkdir -p "$(dirname "$file")"
  if [ -f "$file" ] && grep -qF "$begin" "$file"; then
    awk -v b="$begin" -v e="$end" -v f="$block" '
      $0 == b { while ((getline line < f) > 0) print line; skip = 1; next }
      $0 == e { skip = 0; next }
      !skip   { print }
    ' "$file" > "$file.sp-tmp" && mv "$file.sp-tmp" "$file"
  else
    { [ -s "$file" ] && printf '\n'; cat "$block"; } >> "$file"
  fi
  ok "${file#"$PROJECT_DIR"/}"
}

# remove_block FILE [BEGIN END] — drop the managed block (and the file, if
# nothing is left)
remove_block() {
  local file="$1" begin="${2:-$BEGIN_MARK}" end="${3:-$END_MARK}"
  [ -f "$file" ] && grep -qF "$begin" "$file" || return 0
  # drop the block and exactly what upsert_block put before it, so the file
  # is byte for byte what it was: one blank line after a file that ended in a
  # newline, or (block last) the newline that ended a file without one
  SP_B="$begin" SP_E="$end" perl -0777 -ne '
    my ($b, $e) = ($ENV{SP_B}, $ENV{SP_E});
    if (/\A(.*?)(?:^|(?<=\n))\Q$b\E\n.*?^\Q$e\E(?:\n|\z)(.*)\z/ms) {
      my ($pre, $post) = ($1, $2);
      if ($pre =~ /\n\n\z/) { chop $pre }
      elsif ($post eq "" && $pre =~ /\n\z/) { chop $pre }
      $_ = $pre . $post;
    }
    print;
  ' "$file" > "$file.sp-tmp" && mv "$file.sp-tmp" "$file"
  if ! grep -q '[^[:space:]]' "$file"; then rm -f "$file"; fi
  ok "cleaned ${file#"$PROJECT_DIR"/}"
}

# install_template NAME REL_PATH [KEY VALUE]... — copy scripts/templates/NAME
# into the project, replacing each @KEY@ with VALUE.
install_template() {
  local name="$1" rel="$2" file="$PROJECT_DIR/$2"; shift 2
  mkdir -p "$(dirname "$file")"
  cp "$TEMPLATES_DIR/$name" "$file"
  while [ $# -ge 2 ]; do
    SP_KEY="$1" SP_VALUE="$2" perl -pi -e 's/\@\Q$ENV{SP_KEY}\E\@/$ENV{SP_VALUE}/g' "$file"
    shift 2
  done
  case "$name" in *.sh|*.pl) chmod +x "$file" ;; esac
  ok "$rel"
}
