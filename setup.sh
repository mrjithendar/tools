#!/usr/bin/env bash
# Install a DevOps tool from devops/<tool>.sh. Usage: setup.sh [tool]
# Install as a command with: sudo ln -s /tmp/tools/setup.sh /usr/bin/labauto
set -euo pipefail
REPO=https://github.com/mrjithendar/tools.git
DIR=/tmp/tools

if [[ -d "$DIR/.git" ]]; then
  git -C "$DIR" stash -q || true
  git -C "$DIR" pull -q
else
  git clone -q "$REPO" "$DIR"
fi

tools=()
for script in "$DIR"/devops/*.sh; do
  name="${script##*/}"
  tools+=("${name%.sh}")
done

tool="${1:-}"
if [[ -z "$tool" ]]; then
  echo -e "\e[1;33mSelect a tool to install (number or name):\e[0m"
  PS3='Select Tool> '
  select choice in "${tools[@]}"; do
    tool="${choice:-$REPLY}"
    break
  done
fi
tool="${tool%.sh}"

if [[ ! -f "$DIR/devops/$tool.sh" ]]; then
  echo -e "\e[1;31mTool not found: $tool\e[0m" >&2
  exit 1
fi
echo -e "\e[1;33m★★★ Installing $tool ★★★\e[0m"
exec bash "$DIR/devops/$tool.sh"
