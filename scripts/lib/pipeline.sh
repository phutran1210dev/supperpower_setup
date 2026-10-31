# Run output as a CI-style pipeline, on the terminal primitives of ui.sh: the
# logo header, numbered stage rows ([n/N] name  summary  ✓ 1.2s), a bottom
# progress bar, and the log lines every step writes (log, ok, warn, die).
#
# On a terminal with colors (pretty), the bar is always the last line: other
# output clears it, prints, and redraws it, and a stage's row is rewritten in
# place when the stage ends. Anywhere else (pipes, CI, NO_COLOR) each stage is
# one plain log line, printed when it ends:
#   [2/7] skills   ok  0.1s  15 skills -> .agents/skills

VERBOSE=0 WARN_COUNT=0
PIPE_TOTAL=0 PIPE_DONE=0 PIPE_NAME="" PIPE_T0="" PIPE_STAGE_T0="" PIPE_ELAPSED=""
PIPE_ACTIVE=0 PIPE_IN_STAGE=0 PIPE_ROW_LINES=0 PIPE_STAGE_WARN=0

# the SP monogram, colored amber → violet like the rest of the accents
LOGO=('▗▄▄▖ ▗▄▄▖' '▐▙▄▖ ▐▙▄▘' '▗▄▟▌ ▐▌  ')

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
since() { perl -e 'printf "%.1f", $ARGV[1] - $ARGV[0]' "$1" "$(now)"; }

log()  { pipe_print "$(sgr '1;34')==>$(sgr 0) $*"; }
# ok PATH — a file written; listed only with -v
ok()   { [ "$VERBOSE" -eq 1 ] || return 0; pipe_print "        $(sgr 32)✓$(sgr 0) $*"; }
warn() {
  WARN_COUNT=$((WARN_COUNT + 1)) PIPE_STAGE_WARN=1
  pipe_err "  $(sgr 33)!$(sgr 0) $*"
}
die()  { stage_fail; printf '%serror:%s %s\n' "$(sgr 31)" "$(sgr 0)" "$*" >&2; exit 1; }

# header MODE — the logo, title, versions and project (MODE: install | check | uninstall)
header() {
  local mode="$1" versions="$REF · ECC $ECC_REF" plain="$REF (ECC $ECC_REF" where
  [ "$mode" = install ] && mode=setup
  if [ "$RIPGREP" -eq 1 ]; then versions="$versions · rg $RG_VERSION" plain="$plain, rg $RG_VERSION"; fi
  plain="$plain)"
  where="$(tilde "$PROJECT_DIR")"
  if ! pretty; then
    echo "superpowers $mode $plain -> $PROJECT_DIR"
    return 0
  fi
  local title="superpowers · $mode"
  echo
  printf ' %s   %s%s%s\n' "$(gradient "${LOGO[0]}")" "$(sgr 1)" "$title" "$(sgr 0)"
  printf ' %s   %s%s%s\n' "$(gradient "${LOGO[1]}")" "$(sgr 2)" "$versions" "$(sgr 0)"
  printf ' %s   %s%s%s\n\n' "$(gradient "${LOGO[2]}")" "$(sgr 2)" "$(fit "$where" $(($(cols) - 15)) | sed 's/ *$//')" "$(sgr 0)"
}

pipeline_start() {
  PIPE_TOTAL="$1" PIPE_DONE=0 PIPE_ACTIVE=1 PIPE_IN_STAGE=0 PIPE_T0="$(now)"
  if pretty; then printf '\n'; pipe_bar; fi
}

# pipe_bar — draw the bottom bar on the current line (cursor stays on it)
pipe_bar() {
  local width=$(($(cols) - 20)) pct filled
  [ "$width" -gt 52 ] && width=52
  [ "$width" -lt 10 ] && width=10
  pct=$((PIPE_TOTAL > 0 ? PIPE_DONE * 100 / PIPE_TOTAL : 100))
  filled=$((width * pct / 100))
  printf '\r\033[K %s%s%s%s%s %3d%%  %s%ss%s' "$(sgr 35)" "$(printf '%*s' "$filled" '' | sed 's/ /━/g')" \
    "$(sgr '2')" "$(printf '%*s' $((width - filled)) '' | sed 's/ /░/g')" "$(sgr 0)" "$pct" "$(sgr 2)" "$(since "$PIPE_T0")" "$(sgr 0)"
}

# pipe_print TEXT — print a line of output without breaking the bar or the
# current stage row
pipe_print() {
  if [ "$PIPE_ACTIVE" -eq 1 ] && pretty; then
    printf '\r\033[K%s\n' "$1"
    # a long line wraps: count the screen lines it took
    [ "$PIPE_IN_STAGE" -eq 1 ] && PIPE_ROW_LINES=$((PIPE_ROW_LINES + $(perl -CSA -e '
      (my $s = $ARGV[0]) =~ s/\e\[[0-9;?]*[A-Za-z]//g; my $n = int((length($s) + $ARGV[1] - 1) / $ARGV[1]);
      print $n > 1 ? $n : 1' "$1" "$(cols)")))
    pipe_bar
  else
    printf '%s\n' "$1"
  fi
}

# pipe_err TEXT — error output from a tool: through the pipeline on a terminal,
# else to stderr
pipe_err() {
  if [ "$PIPE_ACTIVE" -eq 1 ] && pretty; then pipe_print "$1"; else printf '%s\n' "$1" >&2; fi
}

# pipe_row MARK DETAIL [TIME] — (re)write the current stage's row. When the
# row has scrolled off the screen (a stage taller than the terminal) it can't
# be reached: a final row (with TIME) is printed as a new line instead, a
# progress update is dropped.
pipe_row() {
  local up=$((PIPE_ROW_LINES + 1)) width=$(($(cols) - 32)) row
  [ "$width" -gt 36 ] && width=36
  [ "$width" -lt 8 ] && width=8
  row="$(printf ' %s[%d/%d]%s %-11s %s %s %s%5s%s' "$(sgr 2)" $((PIPE_DONE + 1)) "$PIPE_TOTAL" "$(sgr 0)" \
    "$PIPE_NAME" "$(fit "$2" "$width")" "$1" "$(sgr 2)" "${3:+${3}s}" "$(sgr 0)")"
  if [ "$up" -lt "$(rows)" ]; then
    printf '\r\033[K\033[%dA\r\033[K%s\033[%dB\r' "$up" "$row" "$up"
  elif [ -n "${3:-}" ]; then
    printf '\r\033[K%s\n' "$row"
  fi
}

stage_begin() {
  PIPE_NAME="$1" PIPE_STAGE_T0="$(now)" PIPE_ROW_LINES=0 PIPE_STAGE_WARN=0 PIPE_IN_STAGE=1
  if pretty; then
    printf '\r\033[K\n'
    pipe_row "$(sgr 2)…$(sgr 0)" ""
    pipe_bar
  fi
}

# stage_end SUMMARY
stage_end() {
  local t mark word
  t="$(since "$PIPE_STAGE_T0")"
  if [ "$PIPE_STAGE_WARN" -eq 1 ]; then mark="$(sgr 33)!$(sgr 0)" word=warn
  else mark="$(sgr 32)✓$(sgr 0)" word=ok
  fi
  if pretty; then
    pipe_row "$mark" "$1" "$t"
  else
    printf '[%d/%d] %-8s %s  %ss  %s\n' $((PIPE_DONE + 1)) "$PIPE_TOTAL" "$PIPE_NAME" "$word" "$t" "$1"
  fi
  PIPE_DONE=$((PIPE_DONE + 1)) PIPE_IN_STAGE=0
  if pretty; then pipe_bar; fi
}

# stage_fail — mark the current stage failed (die calls this)
stage_fail() {
  [ "$PIPE_IN_STAGE" -eq 1 ] || return 0
  if pretty; then
    pipe_row "$(sgr 31)✖$(sgr 0)" "failed" "$(since "$PIPE_STAGE_T0")"
    printf '\r\033[K'
  else
    printf '[%d/%d] %-8s FAIL  %ss\n' $((PIPE_DONE + 1)) "$PIPE_TOTAL" "$PIPE_NAME" "$(since "$PIPE_STAGE_T0")"
  fi
  PIPE_ACTIVE=0 PIPE_IN_STAGE=0
}

# stage_progress DONE_BYTES [TOTAL_BYTES] — a download bar in the stage row
stage_progress() {
  pretty || return 0
  local done="$1" total="${2:-}" detail
  if [ -n "$total" ] && [ "$total" -gt 0 ]; then
    detail="$(perl -e 'my ($d, $t) = @ARGV; my $p = int($d * 100 / $t); $p = 100 if $p > 100;
      my $f = int(16 * $p / 100); printf "%s%s %3d%%  %.1f/%.1f MB", "█" x $f, "░" x (16 - $f), $p, $d / 1048576, $t / 1048576' "$done" "$total")"
  else
    detail="$(perl -e 'printf "%.1f MB", $ARGV[0] / 1048576' "$done")"
  fi
  pipe_row "$(sgr 2)…$(sgr 0)" "$detail"
  pipe_bar
}

pipeline_end() {
  PIPE_ELAPSED="$(since "$PIPE_T0")"
  if pretty; then PIPE_DONE="$PIPE_TOTAL"; pipe_bar; printf '\n\n'; fi
  PIPE_ACTIVE=0
}
