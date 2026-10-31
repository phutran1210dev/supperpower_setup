# MCP servers of ours in each agent's config: a server is ours when its JSON
# matches OURS (it runs our wrapper), so one of the user's own under the same
# name is never touched.

# mcp_put FILE KEY NAME ENTRY OURS — add our NAME server under KEY
# (mcpServers or servers); a NAME server of the user's own is left alone
# (JSON_SKIPPED=1)
mcp_put() {
  json_edit "$PROJECT_DIR/$1" "put_ours(\$d, '$2', '$3', $4, $5);"
  [ "$JSON_SKIPPED" -eq 1 ] && warn "$1 already has a $3 server of your own — left as is"
  return 0
}

mcp_remove() {
  [ -f "$PROJECT_DIR/$1" ] || return 0
  json_edit "$PROJECT_DIR/$1" "drop_ours(\$d, '$2', '$3', $4);"
}

# mcp_has FILE KEY NAME — FILE has a NAME server (after mcp_remove, any left
# is the user's own: leave its approvals alone)
mcp_has() {
  [ -f "$PROJECT_DIR/$1" ] || return 1
  SP_K="$2" SP_N="$3" perl -MJSON::PP -0777 -ne \
    'my $d = eval { JSON::PP->new->relaxed->decode($_) } or exit 1; exit(ref $d eq "HASH" && ref $d->{$ENV{SP_K}} eq "HASH" && exists $d->{$ENV{SP_K}}{$ENV{SP_N}} ? 0 : 1)' \
    "$PROJECT_DIR/$1"
}

# Codex: a managed [mcp_servers.NAME] block in .codex/config.toml, between
# "# NAME:begin" and "# NAME:end" (upsert_block keeps what Codex or the user
# added around it)
CODEX_CONFIG=".codex/config.toml"

# codex_mcp_put NAME SH_SCRIPT COMMENT — our server, run as `sh -c SH_SCRIPT`
codex_mcp_put() {
  local name="$1" file="$PROJECT_DIR/$CODEX_CONFIG" block="$TMP_DIR/$1.toml" script
  if [ -f "$file" ] && sed "/^# $name:begin\$/,/^# $name:end\$/d" "$file" | grep -qE "^\[mcp_servers\.$name\]"; then
    codex_mcp_remove "$name"
    warn "$CODEX_CONFIG already has a $name server of your own — left as is"
    return 0
  fi
  # TOML basic string: escape \ and "
  script="$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  {
    echo "# $name:begin"
    echo "# $3"
    echo "[mcp_servers.$name]"
    echo 'command = "sh"'
    echo "args = [\"-c\", \"$script\"]"
    echo "# $name:end"
  } > "$block"
  upsert_block "$file" "$block" "# $name:begin" "# $name:end"
}

codex_mcp_remove() {
  remove_block "$PROJECT_DIR/$CODEX_CONFIG" "# $1:begin" "# $1:end"
  rmdir "$PROJECT_DIR/.codex" 2>/dev/null || true
}
