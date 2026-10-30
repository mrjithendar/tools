#!/usr/bin/env bash
# Delete GitHub Actions self-hosted runner logs (_diag/**/*.log) on this host. Previews unless --apply is given.
#
#   bash clear-runner-logs.sh                  # list logs from the last 3 days
#   bash clear-runner-logs.sh --apply          # delete them
#   bash clear-runner-logs.sh --days 7 --apply # use another window
#   bash clear-runner-logs.sh --older --apply  # delete logs OLDER than the window, keep the recent ones
#   bash clear-runner-logs.sh DIR... --apply   # only these runner directories
#
# Finds $HOME/actions-runner, $HOME/actions-runner-<n> and $HOME/actions-runners/<repo>/<n>; as root, also those
# under /root and /home/*. Run it as the runner user or root. Logs a runner still has open are skipped: unlinking
# one would not free its disk space, and the runner would keep writing to a file nobody can read.
set -euo pipefail

DAYS=3
OLDER=0
APPLY=0
DIRS=()

die() { echo "error: $*" >&2; exit 1; }

while (($#)); do
  case $1 in
    --apply) APPLY=1 ;;
    --older) OLDER=1 ;;
    --days)
      [[ ${2:-} =~ ^[1-9][0-9]*$ ]] || die "--days needs a whole number of days"
      DAYS=$2
      shift
      ;;
    -h | --help) sed -n '2,/^$/s/^# \{0,1\}//p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) DIRS+=("$1") ;;
  esac
  shift
done

[[ $(uname -s) == Linux ]] || die "run this on the runner host"

if ((${#DIRS[@]} == 0)); then
  homes=("$HOME")
  if [[ $EUID == 0 ]]; then homes+=(/root /home/*); fi
  for home in "${homes[@]}"; do
    DIRS+=("$home"/actions-runner "$home"/actions-runner-* "$home"/actions-runners/*/*)
  done
fi

# Resolved paths, because they are compared with the link targets in /proc and a home may be listed twice.
declare -A runners=()
for dir in "${DIRS[@]}"; do
  [[ -d $dir/_diag ]] && runners[$(readlink -f -- "$dir")]=1
done
((${#runners[@]})) || die "no runner _diag directories found; pass the runner directory as an argument"

if ((OLDER)); then age=(-mmin "+$((DAYS * 1440))"); else age=(-mmin "-$((DAYS * 1440))"); fi

declare -A open_files=()
while IFS= read -r -d '' file; do
  open_files[$file]=1
done < <(find /proc/[0-9]*/fd -type l -lname '*/_diag/*' -printf '%l\0' 2>/dev/null || true)

count=0 bytes=0 skipped=0 failed=0
while IFS= read -r dir; do
  while IFS= read -r -d '' entry; do
    size=${entry%%$'\t'*}
    file=${entry#*$'\t'}
    if [[ -n ${open_files[$file]:-} ]]; then
      echo "in use, skipped: $file"
      skipped=$((skipped + 1))
    elif ((APPLY == 0)); then
      echo "would delete: $file"
      count=$((count + 1)) bytes=$((bytes + size))
    elif rm -f -- "$file"; then
      echo "deleted: $file"
      count=$((count + 1)) bytes=$((bytes + size))
    else
      failed=$((failed + 1))
    fi
  done < <(find "$dir/_diag" -type f -name '*.log' "${age[@]}" -printf '%s\t%p\0')
done < <(printf '%s\n' "${!runners[@]}" | sort -V)

if ((OLDER)); then window="older than $DAYS day(s)"; else window="from the last $DAYS day(s)"; fi
if ((APPLY)); then verb=Deleted; else verb="Would delete"; fi
echo
echo "$verb $count log(s) $window, $(numfmt --to=iec "$bytes"), across ${#runners[@]} runner(s); $skipped in use, $failed failed."
((APPLY)) || echo "Nothing was deleted. Add --apply to delete."
((failed == 0))
