# Terminal primitives: whether output is styled, colors, widths and text
# helpers. Needs no other lib; pipeline.sh (stages, log lines) builds on it.
# Styled output is
# terminal-only (pipes and CI logs stay plain); NO_COLOR or TERM=dumb drops it.

# decided once, at load: inside $(...) stdout is a pipe, not the terminal
PRETTY=0
if [ -t 1 ] && [ -z "${NO_COLOR+x}" ] && [ "${TERM:-}" != "dumb" ]; then PRETTY=1; fi
pretty() { [ "$PRETTY" -eq 1 ]; }
# sgr CODE — an SGR escape on a colored terminal (never in pipes or logs)
sgr() { [ "$PRETTY" -eq 1 ] && printf '\033[%sm' "$1"; return 0; }
# arrow — → on a terminal, -> in plain logs
arrow() { if pretty; then printf '→'; else printf -- '->'; fi; }

# the terminal's size, read once from the terminal itself (tput inside $(...)
# can't see it and falls back to 80); COLUMNS / LINES override
TERM_COLS=80 TERM_ROWS=24
if [ "$PRETTY" -eq 1 ]; then
  read -r TERM_ROWS TERM_COLS < <(stty size < /dev/tty 2>/dev/null || echo "24 80")
  [ "${TERM_COLS:-0}" -gt 0 ] 2>/dev/null || TERM_COLS=80
  [ "${TERM_ROWS:-0}" -gt 0 ] 2>/dev/null || TERM_ROWS=24
fi
cols() { echo "${COLUMNS:-$TERM_COLS}"; }
rows() { echo "${LINES:-$TERM_ROWS}"; }

# fit TEXT WIDTH — TEXT cut to WIDTH characters (… marks the cut) and padded
# to WIDTH; counts characters, not bytes, so · and → line up
fit() { perl -CSA -e 'my ($s, $w) = @ARGV; $s = substr($s, 0, $w - 1) . "\x{2026}" if length($s) > $w; printf "%-*s", $w, $s' "$1" "$2"; }

# gradient TEXT — amber → violet across TEXT's characters (pretty only)
gradient() {
  perl -CSA -e 'my @c = split //, $ARGV[0]; my $n = @c > 1 ? $#c : 1; my $o = "";
    for my $i (0 .. $#c) {
      if ($c[$i] eq " ") { $o .= " "; next }
      my $t = $i / $n;
      $o .= sprintf "\e[38;2;%d;%d;%dm%s", 251 + (168 - 251) * $t, 191 + (85 - 191) * $t, 36 + (247 - 36) * $t, $c[$i];
    }
    print "$o\e[0m";' "$1"
}

# tilde PATH — PATH with $HOME shown as ~
tilde() { case "$1" in "$HOME"/*) echo "~${1#"$HOME"}" ;; *) echo "$1" ;; esac; }
