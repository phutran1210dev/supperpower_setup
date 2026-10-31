# Run output: the plain log format, the terminal pipeline (rows rewritten in
# place, the bottom bar, narrow and short screens) and download progress.

test_pipeline_primitives() {
  pipe_run 'pipeline_start 2; stage_begin fetch; stage_end "x y"; stage_begin skills; warn "careful"
            stage_end "15 skills"; pipeline_end; echo "warnings=$WARN_COUNT"'
  check "stage row" sh -c "sed -n 1p '$WORK/pipe.out' | grep -Eq '^\[1/2\] fetch +ok +[0-9.]+s +x y$'"
  check "warning under its stage" sh -c "sed -n 2p '$WORK/pipe.out' | grep -qx '  ! careful'"
  check "stage with a warning" sh -c "sed -n 3p '$WORK/pipe.out' | grep -Eq '^\[2/2\] skills +warn +[0-9.]+s +15 skills$'"
  check "warnings counted" contains "$WORK/pipe.out" "warnings=1"
  check_not "no escapes in plain mode" grep -q $'\033' "$WORK/pipe.out"
  pipe_run 'pipeline_start 1; stage_begin agents; die "boom"'
  check "die exits 1" test $? = 1
  check "die marks the stage failed" sh -c "grep -Eq '^\[1/1\] agents +FAIL' '$WORK/pipe.out' && grep -qx 'error: boom' '$WORK/pipe.out'"
  pipe_run 'pipeline_start 1; stage_begin skills; ok "a/file"; stage_end done'
  check_not "ok is quiet without -v" contains "$WORK/pipe.out" "a/file"
  pipe_run 'VERBOSE=1; pipeline_start 1; stage_begin skills; ok "a/file"; stage_end done'
  check "ok lists files with -v" contains "$WORK/pipe.out" "✓ a/file"
}

has_script() { script -q /dev/null true >/dev/null 2>&1 < /dev/null || script -qc true /dev/null >/dev/null 2>&1 < /dev/null; }

# in_tty CMD... — run CMD in a pseudo-terminal (colors on), transcript to $WORK/tty.out;
# returns 1 when `script` is unavailable
in_tty() {
  if script -q /dev/null true >/dev/null 2>&1 < /dev/null; then
    env -u NO_COLOR TERM=xterm-256color script -q /dev/null "$@" > "$WORK/tty.out" 2>&1 < /dev/null
  elif script -qc true /dev/null >/dev/null 2>&1 < /dev/null; then
    env -u NO_COLOR TERM=xterm-256color script -qc "$(printf '%q ' "$@")" /dev/null > "$WORK/tty.out" 2>&1 < /dev/null
  else
    return 1
  fi
}

# tty_segments — the transcript with escapes removed, one line per \r or \n segment
tty_segments() { perl -CSD -pe 's/\e\[[0-9;?]*[A-Za-z]//g; s/\r/\n/g' "$WORK/tty.out"; }

test_plain_output_format() {
  local d="$WORK/format"
  rm -rf "$d" && bootstrap "$d" -t claude,codex
  perl -pe 's/[0-9]+\.[0-9]+s\b/Ns/g' "$WORK/last.log" > "$WORK/masked.log"
  local want="superpowers setup v7.0.1 (ECC v2.2.3, rg 15.2.0) ->
[1/9] fetch    ok
[2/9] skills   ok
[3/9] security ok
[4/9] agents   ok
[5/9] ripgrep  ok
[6/9] code map ok
[7/9] claude   ok
[8/9] codex    ok
[9/9] vscode   ok
ready in Ns: 2 tools, 12 skills, 28 subagents, 0 warnings"
  check "stages in order" perl -e '
    open my $f, "<", $ARGV[0] or die; my @log = <$f>; my $i = 0;
    for my $want (split /\n/, $ARGV[1]) { $i++ while $i < @log && index($log[$i], $want) != 0; exit 1 if $i >= @log; $i++ }' \
    "$WORK/masked.log" "$want"
  check "next steps" contains "$WORK/last.log" "1  commit the generated files"
  check "Codex step" contains "$WORK/last.log" "Codex: trust the project, approve hooks in /hooks"
  check "update line" grep -q '^ *update ' "$WORK/last.log"
  check "lines fit in 80 columns" perl -CSD -ne 'chomp; exit 1 if length > 80; END { exit 0 }' "$WORK/last.log"
  check_not "no per-file lines without -v" contains "$WORK/last.log" "✓ .claude/settings.json"
  check_not "no escapes" grep -q $'\033' "$WORK/last.log"
}

test_verbose_lists_files() {
  rm -rf "$WORK/verbose" && bootstrap "$WORK/verbose" -t claude -v
  check "-v lists files" contains "$WORK/last.log" "✓ .claude/settings.json"
}

test_cleanup_stage() {
  local d="$WORK/cleanup"
  rm -rf "$d" && bootstrap "$d"
  bootstrap "$d" -t claude
  check "cleanup is the last stage" grep -Eq '^\[9/9\] cleanup +ok .*removed: codex, copilot, cursor, gemini, antigravity, devin$' "$WORK/last.log"
}

test_tty_render() {
  local d="$WORK/tty" mirror="$WORK/badmirror"
  rm -rf "$d" "$mirror" && mkdir -p "$mirror"
  if ! in_tty env PATH="$NO_RG_PATH" RIPGREP_MIRROR="file://$mirror" COLUMNS=100 \
       bash "$BOOTSTRAP" -y -s "$SP" --ecc-source "$ECC" --security-audit-source "$SA" -t claude,codex "$d"; then
    echo "  (skipped: no script command)"; return 0
  fi
  check "logo" sh -c "perl -CSD -pe 's/\e\[[0-9;?]*[A-Za-z]//g' '$WORK/tty.out' | grep -q '▗▄▄▖ ▗▄▄▖'"
  check "pipeline bar reaches 100%" sh -c "tty_out=\$(perl -CSD -pe 's/\e\[[0-9;?]*[A-Za-z]//g' '$WORK/tty.out'); case \"\$tty_out\" in *━*100%*) exit 0;; esac; exit 1"
  check "warning printed once" test "$(tty_segments | grep -c 'could not download')" = 1
  check "ripgrep row ends with !" sh -c "perl -CSD -pe 's/\e\[[0-9;?]*[A-Za-z]//g; s/\r/\n/g' '$WORK/tty.out' | grep '\[5/9\] ripgrep' | tail -1 | grep -q '!'"
  check "summary" contains "$WORK/tty.out" "✦"
  in_tty env PATH="$NO_RG_PATH" RIPGREP_MIRROR="file://$mirror" COLUMNS=60 \
    bash "$BOOTSTRAP" -y -s "$SP" --ecc-source "$ECC" --security-audit-source "$SA" -t claude,codex "$d"
  check "stage rows and bar fit 60 columns" sh -c "perl -CSD -pe 's/\e\[[0-9;?]*[A-Za-z]//g; s/\r/\n/g' '$WORK/tty.out' | grep -E '^ \[[0-9]/[0-9]\]|━|░' | perl -CSD -ne 'chomp; exit 1 if length > 60'"
}

# serve_dir DIR [nolen] — a tiny HTTP server for DIR, sending the body slowly so
# progress can be seen; prints its port; "nolen" omits Content-Length
serve_dir() {
  perl -MIO::Socket::INET -e '
    my ($dir, $nolen) = @ARGV;
    my $s = IO::Socket::INET->new(Listen => 5, LocalAddr => "127.0.0.1", LocalPort => 0, ReuseAddr => 1) or die;
    $| = 1; print $s->sockport, "\n"; close STDOUT;
    while (my $c = $s->accept) {
      my $req = ""; while (<$c>) { $req .= $_; last if /^\r?\n$/ }
      my ($method, $path) = $req =~ m{^(\S+) (\S+)};
      my $f = "$dir$path";
      unless (-f $f) { print $c "HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\n\r\n"; close $c; next }
      print $c "HTTP/1.0 200 OK\r\n", ($nolen ? "" : "Content-Length: " . (-s $f) . "\r\n"), "\r\n";
      if ($method ne "HEAD") {
        open my $fh, "<:raw", $f; local $/; my $data = <$fh>;
        for (my $i = 0; $i < length $data; $i += 16384) { print $c substr($data, $i, 16384); select undef, undef, undef, 0.01 }
      }
      close $c;
    }' "$@" &
  SERVER_PID=$!
}

# rg_fixture DIR — a fake ripgrep release for this machine in DIR (2 MB, so
# the download takes a moment); sets FIXTURE_SHA, returns 1 without a tar.gz build
rg_fixture() {
  local mirror="$1" asset target
  # shellcheck source=/dev/null
  . "$TESTS_DIR/../lib/ripgrep.sh"
  asset="$(rg_asset)"; asset="${asset% *}"; target="${asset%%.*}"
  [ -n "$asset" ] && [ "${asset##*.}" != zip ] || return 1
  rm -rf "$mirror" && mkdir -p "$mirror/ripgrep-$RG_VERSION-$target"
  printf '#!/bin/sh\necho "ripgrep %s (fixture)"\n' "$RG_VERSION" > "$mirror/ripgrep-$RG_VERSION-$target/rg"
  chmod +x "$mirror/ripgrep-$RG_VERSION-$target/rg"
  head -c 2097152 /dev/urandom > "$mirror/ripgrep-$RG_VERSION-$target/pad.bin"
  tar -czf "$mirror/ripgrep-$RG_VERSION-$asset" -C "$mirror" "ripgrep-$RG_VERSION-$target"
  FIXTURE_SHA="$(perl -MDigest::SHA -e 'print Digest::SHA->new(256)->addfile($ARGV[0], "b")->hexdigest' "$mirror/ripgrep-$RG_VERSION-$asset")"
}

# download_run NOLEN — bootstrap -t claude in a terminal, ripgrep from a local HTTP mirror
download_run() {
  local d="$WORK/dl" port
  has_script && rg_fixture "$WORK/httpmirror" || return 2
  rm -f "$WORK/tty.out"
  serve_dir "$WORK/httpmirror" ${1:-} > "$WORK/port"
  for _ in 1 2 3 4 5 6 7 8 9 10; do port="$(cat "$WORK/port")"; [ -n "$port" ] && break; sleep 0.2; done
  rm -rf "$d"
  in_tty env PATH="$NO_RG_PATH" RIPGREP_MIRROR="http://127.0.0.1:$port" RIPGREP_SHA256="$FIXTURE_SHA" COLUMNS=100 \
    bash "$BOOTSTRAP" -y -s "$SP" --ecc-source "$ECC" --security-audit-source "$SA" -t claude "$d"
  local rc=$?
  kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null
  [ "$rc" -eq 0 ] && [ -x "$d/.agents/bin/rg" ]
}

test_download_progress() {
  download_run; local rc=$?
  if [ "$rc" -eq 2 ]; then echo "  (skipped: no script command or no tar.gz build for this machine)"; return 0; fi
  check "download succeeds" test "$rc" = 0
  check "row shows a percentage and MB" sh -c "perl -CSD -pe 's/\e\[[0-9;?]*[A-Za-z]//g; s/\r/\n/g' '$WORK/tty.out' | grep '\[5/8\] ripgrep' | grep -Eq '█*░* *[0-9]+%  [0-9.]+/[0-9.]+ MB'"
}

test_download_without_length() {
  download_run nolen; local rc=$?
  if [ "$rc" -eq 2 ]; then echo "  (skipped: no script command or no tar.gz build for this machine)"; return 0; fi
  check "download succeeds" test "$rc" = 0
  check "row shows MB" sh -c "perl -CSD -pe 's/\e\[[0-9;?]*[A-Za-z]//g; s/\r/\n/g' '$WORK/tty.out' | grep '\[5/8\] ripgrep' | grep -Eq '[0-9.]+ MB'"
  check_not "row shows no percentage" sh -c "perl -CSD -pe 's/\e\[[0-9;?]*[A-Za-z]//g; s/\r/\n/g' '$WORK/tty.out' | grep '\[5/8\] ripgrep' | grep -q '%'"
}

test_check_stages() {
  local d="$WORK/checkstages"
  rm -rf "$d" && bootstrap "$d" -t claude
  bootstrap "$d" --check
  check "copy stage" grep -Eq '^\[1/3\] copy +ok' "$WORK/last.log"
  check "rerun stage" grep -Eq '^\[2/3\] rerun +ok' "$WORK/last.log"
  check "compare: up to date" grep -Eq '^\[3/3\] compare +ok .*up to date$' "$WORK/last.log"
  perl -pi -e 's/^## Superpowers$/## Superpowers (edited)/' "$d/CLAUDE.md"
  bootstrap "$d" --check
  check "compare: drift" grep -Eq '^\[3/3\] compare +warn .*1 file differs$' "$WORK/last.log"
  check "compare: names the file" grep -q 'CLAUDE.md' "$WORK/last.log"
  bootstrap "$d" --uninstall
  check "uninstall: one stage per tool" grep -Eq '^\[1/9\] claude +ok .*removed$' "$WORK/last.log"
  check "uninstall: tools not set up" grep -Eq '^\[2/9\] codex +ok .*not set up$' "$WORK/last.log"
  check "uninstall: skills and agents stages" sh -c "grep -Eq '^\[8/9\] skills +ok' '$WORK/last.log' && grep -Eq '^\[9/9\] agents +ok' '$WORK/last.log'"
}

# screen_run COLS ROWS ARGS... — bootstrap in a COLS x ROWS pty (set with stty,
# COLUMNS unset, as in a real terminal); the final screen goes to $WORK/screen
screen_run() {
  local w="$1" h="$2"; shift 2
  has_script || return 2
  in_tty env -u COLUMNS -u LINES bash -c 'stty cols "$1" rows "$2" 2>/dev/null; shift 2; exec "$@"' _ "$w" "$h" \
    bash "$BOOTSTRAP" -s "$SP" --ecc-source "$ECC" --security-audit-source "$SA" "$@"
  local rc=$?
  perl "$TESTS_DIR/vt.pl" "$w" "$h" "$WORK/tty.out" > "$WORK/screen"
  return "$rc"
}

# screen_clean NAME — stage rows appear once each, none left running (…), one bar
screen_clean() {
  check "$1: no stage row left running" sh -c "! grep -E '^ \[[0-9]+/[0-9]+\] [a-z]+ +…' '$WORK/screen'"
  check "$1: each stage row once" sh -c "test -z \"\$(grep -oE '^ \[[0-9]+/[0-9]+\] [a-z]+' '$WORK/screen' | sort | uniq -d)\""
  check "$1: one bar" test "$(grep -c '100%' "$WORK/screen")" = 1
}

test_screen_narrow() {
  local d="$WORK/narrow"; rm -rf "$d"
  screen_run 60 40 -y -t claude,codex "$d"
  if [ $? -eq 2 ]; then echo "  (skipped: no script command)"; return 0; fi
  screen_clean narrow
  check "narrow: nothing wider than 60" perl -CSD -ne 'chomp; exit 1 if length > 60' "$WORK/screen"
}

test_screen_long_warning() {
  local d="$WORK/longwarn" mirror="$WORK/emptymirror"; rm -rf "$d"; mkdir -p "$mirror"
  PATH="$NO_RG_PATH" RIPGREP_MIRROR="file://$mirror/$(printf 'x%.0s' $(seq 1 120))" screen_run 100 40 -y -t claude,codex "$d"
  if [ $? -eq 2 ]; then echo "  (skipped: no script command)"; return 0; fi
  screen_clean longwarn
  check "longwarn: ripgrep row marked !" grep -Eq '^ \[5/9\] ripgrep .*! ' "$WORK/screen"
  check "longwarn: warning intact" sh -c "tr -d '\n' < '$WORK/screen' | grep -q 'install rg yourself, or set RIPGREP_MIRROR'"
}

test_screen_tall_stage() {
  local d="$WORK/tall"; rm -rf "$d"
  screen_run 100 5 -y -v -t claude,copilot "$d"
  if [ $? -eq 2 ]; then echo "  (skipped: no script command)"; return 0; fi
  # rows that scrolled off are reprinted when done, so -v lines survive
  local want
  rm -rf "$d.plain" && bootstrap "$d.plain" -v -t claude,copilot
  want="$(grep -c '^        ✓ ' "$WORK/last.log")"
  check "tall: every file line intact ($want)" test "$(grep -c '^        ✓ ' "$WORK/screen")" = "$want"
  check "tall: each stage finished once" test "$(grep -cE '^ \[[0-9]/9\] [a-z]+ .*✓' "$WORK/screen")" = 9
  check "tall: one bar" test "$(grep -c '100%' "$WORK/screen")" = 1
}

test_screen_errors() {
  local d="$WORK/jsonerr"; rm -rf "$d" && mkdir -p "$d/.claude" && echo '[1,2]' > "$d/.claude/settings.json"
  screen_run 100 40 -y -t claude "$d"
  if [ $? -eq 2 ]; then echo "  (skipped: no script command)"; return 0; fi
  check "json error: cause visible" grep -q 'not a JSON object' "$WORK/screen"
  check "json error: stage failed" grep -Eq '^ \[7/8\] claude .*✖' "$WORK/screen"
  # a git that fails like a missing tag
  mkdir -p "$WORK/fakegit" && printf '#!/bin/sh\necho "warning: redirecting" >&2\necho "fatal: Remote branch v9 not found in upstream origin" >&2\nexit 128\n' > "$WORK/fakegit/git" && chmod +x "$WORK/fakegit/git"
  rm -rf "$d"
  PATH="$WORK/fakegit:$PATH" in_tty env -u COLUMNS bash -c 'stty cols 100 rows 40; exec "$@"' _ bash "$BOOTSTRAP" -y -t claude --ref v9 "$d"
  perl "$TESTS_DIR/vt.pl" 100 40 "$WORK/tty.out" > "$WORK/screen"
  check "git error: cause visible" grep -q 'fatal: Remote branch v9 not found' "$WORK/screen"
  check "git error: stage failed" grep -Eq '^ \[1/8\] fetch .*✖' "$WORK/screen"
}

test_plain_without_no_color() {
  local d="$WORK/nocolorunset"; rm -rf "$d"
  ( unset NO_COLOR; export TERM=xterm-256color; bash "$BOOTSTRAP" -y -v -s "$SP" --ecc-source "$ECC" --security-audit-source "$SA" -t claude,codex "$d" ) > "$WORK/piped.log" 2>&1
  check_not "piped output has no escapes, NO_COLOR unset" grep -q $'\033' "$WORK/piped.log"
}
