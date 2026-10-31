# Fetching what the bootstrap installs: git checkouts and checksum-verified
# release downloads. Error output is shown under the current stage.

# show_errors FILE — a tool's error output, line by line, under the stage
show_errors() {
  local line
  while IFS= read -r line; do pipe_err "  $line"; done < "$1"
}

# git_clone ARGS... — quiet clone; git's notices (e.g. "tag ... is not a
# commit" for annotated tags) are shown only when the clone fails.
git_clone() {
  git clone --quiet "$@" 2> "$TMP_DIR/git.err" && return 0
  show_errors "$TMP_DIR/git.err"
  return 1
}

# checkout_version DIR JSON — "v<version> @ <commit>" of a checkout, the
# version read from its JSON file (DIR-relative)
checkout_version() {
  local sha version
  sha="$(git -C "$1" rev-parse --short HEAD 2>/dev/null || echo local)"
  version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$1/$2" 2>/dev/null | head -1)"
  echo "v${version:-?} @ ${sha}"
}

sha256() { perl -MDigest::SHA -e 'print Digest::SHA->new(256)->addfile($ARGV[0], "b")->hexdigest' "$1"; }

# download URL FILE — curl URL to FILE (its error message in $TMP_DIR/curl.err).
# On a terminal the current stage row shows progress, as a bar and % when the
# server sends a Content-Length, else MB so far.
download() {
  local url="$1" file="$2" total="" pid
  if ! pretty; then curl -fsSL --retry 2 -o "$file" "$url" 2> "$TMP_DIR/curl.err"; return; fi
  total="$(curl -sIL "$url" 2>/dev/null | tr -d '\r' | awk 'tolower($1) == "content-length:" { n = $2 } END { print n }')"
  curl -fsSL --retry 2 -o "$file" "$url" 2> "$TMP_DIR/curl.err" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    stage_progress "$( (wc -c < "$file") 2>/dev/null | tr -d ' ' || echo 0)" "$total"
    sleep 0.1
  done
  wait "$pid"
}

# fetch_release WHAT URL FILE SHA256 MIRROR_VAR — download a release file and
# verify its checksum; on failure warn (how to install WHAT instead) and
# return 1
fetch_release() {
  local what="$1" url="$2" file="$3" sha="$4" mirror="$5"
  have curl || { warn "curl not found — install $what yourself"; return 1; }
  if ! download "$url" "$file"; then
    warn "could not download $url ($(tail -1 "$TMP_DIR/curl.err")) — install $what yourself, or set $mirror"
    return 1
  fi
  if [ "$(sha256 "$file")" != "$sha" ]; then
    warn "$what download failed its checksum — not installed"
    return 1
  fi
}
