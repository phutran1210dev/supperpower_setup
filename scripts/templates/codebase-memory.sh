#!/bin/sh
# Managed by the Superpowers bootstrap: runs codebase-memory-mcp @VERSION@, the
# code map, for this project. The agents' MCP configs start `serve` through
# it; `ui` opens the graph in a browser; `project` prints this project's name
# in the index; anything else goes to codebase-memory-mcp (`cli <tool> '<json>'`,
# `config`, ...). The binary lives per machine in ~/.codebase-memory, the index
# in its cache (~/.cache/codebase-memory-mcp).
root="$(cd "$(dirname "$0")/.." && pwd)"
bin="${CODEBASE_MEMORY_INSTALL_DIR:-$HOME/.codebase-memory}/versions/@VERSION@/codebase-memory-mcp"
[ -x "$bin" ] || bin="$(command -v codebase-memory-mcp 2>/dev/null || true)"
if [ -z "$bin" ]; then
  echo "codebase-memory @VERSION@ is not installed on this machine: re-run scripts/superpowers.sh" \
       "(or see https://github.com/DeusData/codebase-memory-mcp). Until then, search with rg." >&2
  exit 127
fi
# MCP clients differ in the directory they start servers in: pin the project
cd "$root" || exit 1

case "${1:-}" in
  serve) shift; exec "$bin" "$@" ;;

  project)
    "$bin" cli --quiet list_projects '{"format":"json"}' | SP_ROOT="$root" perl -MJSON::PP -MCwd=abs_path -0777 -ne '
      my $d = eval { decode_json($_) } or exit 1;
      my $want = abs_path($ENV{SP_ROOT});
      for (@{ $d->{projects} || [] }) {
        if ($_->{root_path} eq $ENV{SP_ROOT} || (abs_path($_->{root_path}) // "") eq $want) { print "$_->{name}\n"; exit 0 }
      }
      exit 1' && exit 0
    echo "not indexed yet: $0 cli index_repository '{\"repo_path\":\"$root\"}'" >&2
    exit 1 ;;

  ui)
    if [ "$("$bin" config get ui_enabled 2>/dev/null)" = false ]; then
      echo "the graph UI is turned off: $0 config set ui_enabled true" >&2
      exit 1
    fi
    port="$("$bin" config get ui_port 2>/dev/null)"
    url="http://127.0.0.1:${port:-9749}/"
    up() { curl -fs -o /dev/null "$url" 2>/dev/null; }
    show() {
      if command -v open > /dev/null 2>&1; then open "$url"
      elif command -v xdg-open > /dev/null 2>&1; then xdg-open "$url" > /dev/null 2>&1
      fi
    }
    # an agent's server may be serving it already
    if up; then echo "code map: $url"; show; exit 0; fi
    # the UI lives as long as a server does, and a server until its stdin
    # closes: hold a FIFO open, so it stops when this script does (Ctrl-C)
    dir="$(mktemp -d)" && mkfifo "$dir/in" || exit 1
    "$bin" < "$dir/in" > /dev/null 2>&1 &
    pid=$!
    exec 3> "$dir/in"
    rm -rf "$dir"
    trap 'kill "$pid" 2>/dev/null; exit 0' INT TERM HUP
    i=0
    until up; do
      i=$((i + 1))
      if [ "$i" -gt 100 ] || ! kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        echo "the graph UI did not start on $url (another program on the port? $0 config set ui_port N)" >&2
        exit 1
      fi
      sleep 0.1
    done
    echo "code map: $url  (Ctrl-C to stop)"
    show
    wait "$pid" ;;

  *) exec "$bin" "$@" ;;
esac
