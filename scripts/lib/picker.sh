# Interactive checkbox picker (↑/↓ move, space toggle, enter confirm). Agents
# already in the project and agents detected on this machine start checked.
# Reads keys from /dev/tty so it works when stdin is redirected.

PICK_NAMES=() PICK_SEL=() PICK_DET=() PICK_CUR=0 PICK_MSG=""
PICK_TITLE="Which AI agents should Superpowers be set up for?"

picker_draw() {
  local i n=${#PICK_NAMES[@]} pointer mark label det
  printf '\033[36m?\033[0m \033[1m%s\033[0m\033[K\n' "$PICK_TITLE"
  printf '\033[2m  ↑/↓ move · space select · a all/none · enter confirm · q quit\033[0m\033[K\n'
  for ((i = 0; i < n; i++)); do
    label="$(target_label "${PICK_NAMES[i]}")"
    case "${PICK_DET[i]}" in
      2) det=$' \033[2m(in project)\033[0m' ;;
      1) det=$' \033[2m(detected)\033[0m' ;;
      *) det="" ;;
    esac
    if [ "${PICK_SEL[i]}" = 1 ]; then mark=$'\033[32m◉\033[0m'; else mark=$'\033[2m◯\033[0m'; fi
    if [ "$i" -eq "$PICK_CUR" ]; then
      pointer=$'\033[36m❯\033[0m'; label=$'\033[36m'"$label"$'\033[0m'
    else
      pointer=' '
    fi
    printf ' %s %s %s%s\033[K\n' "$pointer" "$mark" "$label" "$det"
  done
  printf '%s\033[K\n' "$PICK_MSG"
}

picker_restore() { printf '\033[?25h' > /dev/tty; }

# choose_targets — sets TARGETS from the picker
choose_targets() {
  local t i n key rest lines any all picked="" labels=""
  PICK_NAMES=() PICK_SEL=() PICK_DET=() PICK_CUR=0 PICK_MSG=""
  for t in $(target_list); do
    PICK_NAMES+=("$t")
    if is_installed_target "$t"; then PICK_DET+=(2); PICK_SEL+=(1)
    elif target_detected "$t"; then PICK_DET+=(1); PICK_SEL+=(1)
    else PICK_DET+=(0); PICK_SEL+=(0); fi
  done
  n=${#PICK_NAMES[@]}
  lines=$((n + 3))

  trap 'picker_restore; printf "\n\033[31m✖ Cancelled\033[0m\n" > /dev/tty; exit 130' INT TERM
  printf '\033[?25l' > /dev/tty
  picker_draw > /dev/tty

  while :; do
    IFS= read -rsn1 key < /dev/tty || key="q"
    if [ "$key" = $'\033' ]; then
      IFS= read -rsn2 rest < /dev/tty || rest=""
      key="ESC$rest"
    fi
    PICK_MSG=""
    case "$key" in
      "ESC[A"|"ESCOA"|k) PICK_CUR=$(((PICK_CUR - 1 + n) % n)) ;;
      "ESC[B"|"ESCOB"|j) PICK_CUR=$(((PICK_CUR + 1) % n)) ;;
      " "|x)
        if [ "${PICK_SEL[PICK_CUR]}" = 1 ]; then PICK_SEL[PICK_CUR]=0; else PICK_SEL[PICK_CUR]=1; fi ;;
      [1-9])
        if [ "$key" -le "$n" ]; then
          PICK_CUR=$((key - 1))
          if [ "${PICK_SEL[PICK_CUR]}" = 1 ]; then PICK_SEL[PICK_CUR]=0; else PICK_SEL[PICK_CUR]=1; fi
        fi ;;
      a|A)
        all=1
        for ((i = 0; i < n; i++)); do [ "${PICK_SEL[i]}" = 1 ] || all=0; done
        for ((i = 0; i < n; i++)); do PICK_SEL[i]=$((1 - all)); done ;;
      q|Q)
        picker_restore; trap - INT TERM
        printf '\033[%dA\033[J\033[31m✖\033[0m Cancelled\n' "$lines" > /dev/tty
        exit 130 ;;
      "")
        any=0
        for ((i = 0; i < n; i++)); do [ "${PICK_SEL[i]}" = 1 ] && any=1; done
        if [ "$any" = 1 ]; then break; fi
        PICK_MSG=$'\033[33m  Select at least one agent (space to select)\033[0m' ;;
    esac
    printf '\033[%dA' "$lines" > /dev/tty
    picker_draw > /dev/tty
  done

  picker_restore; trap - INT TERM
  for ((i = 0; i < n; i++)); do
    if [ "${PICK_SEL[i]}" = 1 ]; then
      picked="$picked,${PICK_NAMES[i]}"
      labels="$labels, $(target_label "${PICK_NAMES[i]}")"
    fi
  done
  TARGETS="${picked#,}"
  # collapse the menu into a one-line answer, like other CLI prompts
  printf '\033[%dA\033[J\033[32m✔\033[0m \033[1mAgents\033[0m  \033[36m%s\033[0m\n' "$lines" "${labels#, }" > /dev/tty
}
