#!/usr/bin/env bash
# orchy-scope-check.sh: mechanically verify that a worker's changes stayed inside its scope.
#
# Changed paths = `git diff --name-only -M <base>` (tracked, staged or not; renames report
# the new path) plus `git ls-files --others --exclude-standard` (untracked).
#
# Allow globs are matched against repo-relative paths with `[[ $path == $glob ]]` after
# `shopt -s globstar extglob nullglob`. `**` is supported (inside `[[ ]]` a plain `*` also
# crosses `/`). A trailing `/` means "directory subtree": `dir/` is normalized to `dir/**`
# and also matches `dir/*`.
#
# `.agents/TICKETS.md` and `.agents/orchy-metrics.jsonl` are violations regardless of allowlist.
#
# Exit: 0 in scope, 2 violation, 1 usage or git error.
set -euo pipefail
shopt -s globstar extglob nullglob

PROTECTED=(.agents/TICKETS.md .agents/orchy-metrics.jsonl)

usage() {
  cat <<'EOF'
Usage: orchy-scope-check.sh --base <git-ref-or-sha> [--repo <path>] [--allow <glob>]... [--allow-file <file>] [--json]

  --base <ref>         checkpoint recorded before the wave (required)
  --repo <path>        repository or worktree path (default: .)
  --allow <glob>       allowed path glob; repeatable
  --allow-file <file>  one glob per line; '#' comments and blank lines ignored
  --json               print a single JSON object instead of human output
  -h, --help           show this help

Exit codes: 0 in scope, 2 violation, 1 usage/git error.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

json_str() { local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }

json_arr() {
  local sep='' p
  printf '['
  for p in "$@"; do printf '%s"%s"' "$sep" "$(json_str "$p")"; sep=','; done
  printf ']'
}

base='' repo='.' json=0
allow=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --base) [[ $# -ge 2 ]] || die "--base needs a value"; base=$2; shift 2 ;;
    --repo) [[ $# -ge 2 ]] || die "--repo needs a value"; repo=$2; shift 2 ;;
    --allow) [[ $# -ge 2 ]] || die "--allow needs a value"; allow+=("$2"); shift 2 ;;
    --allow-file)
      [[ $# -ge 2 ]] || die "--allow-file needs a value"
      [[ -r $2 ]] || die "cannot read allow file: $2"
      while IFS= read -r line || [[ -n $line ]]; do
        line=${line%%#*}
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        if [[ -n $line ]]; then allow+=("$line"); fi
      done <"$2"
      shift 2 ;;
    --json) json=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

[[ -n $base ]] || { usage >&2; die "--base is required"; }
top=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || die "not a git repository: $repo"
git -C "$top" rev-parse --verify --quiet "${base}^{commit}" >/dev/null || die "base ref not found: $base"

if ((${#allow[@]})); then
  for i in "${!allow[@]}"; do
    g=${allow[$i]#./}
    if [[ $g == */ ]]; then
      allow[$i]="${g}**"
      allow+=("${g}*")
    else
      allow[$i]=$g
    fi
  done
fi

changed=()
while IFS= read -r -d '' p; do changed+=("$p"); done < <(
  {
    git -C "$top" diff --name-only -M -z "$base" --
    git -C "$top" ls-files --others --exclude-standard -z
  } | sort -zu
)

in_scope=() out_scope=() protected=()
for p in ${changed[@]+"${changed[@]}"}; do
  hit=0
  for g in "${PROTECTED[@]}"; do
    if [[ $p == "$g" ]]; then hit=2; break; fi
  done
  if ((hit == 2)); then protected+=("$p"); continue; fi
  for g in ${allow[@]+"${allow[@]}"}; do
    if [[ $p == $g ]]; then hit=1; break; fi
  done
  if ((hit)); then in_scope+=("$p"); else out_scope+=("$p"); fi
done

ok=1
if ((${#out_scope[@]} + ${#protected[@]} > 0)); then ok=0; fi

if ((json)); then
  okj=false
  if ((ok)); then okj=true; fi
  printf '{"ok":%s,"base":"%s","in_scope":%s,"out_of_scope":%s,"protected":%s}\n' \
    "$okj" "$(json_str "$base")" \
    "$(json_arr ${in_scope[@]+"${in_scope[@]}"})" \
    "$(json_arr ${out_scope[@]+"${out_scope[@]}"})" \
    "$(json_arr ${protected[@]+"${protected[@]}"})"
elif ((ok)); then
  printf 'SCOPE OK (%d files)\n' "${#in_scope[@]}"
  for p in ${in_scope[@]+"${in_scope[@]}"}; do printf '  %s\n' "$p"; done
else
  printf 'SCOPE VIOLATION\n'
  for p in ${out_scope[@]+"${out_scope[@]}"}; do printf '  out-of-scope: %s\n' "$p"; done
  for p in ${protected[@]+"${protected[@]}"}; do printf '  protected: %s\n' "$p"; done
  quoted=''
  for p in ${out_scope[@]+"${out_scope[@]}"} ${protected[@]+"${protected[@]}"}; do
    quoted+=" $(printf '%q' "$p")"
  done
  printf 'revert with: git -C %q checkout %q --%s ; and delete untracked ones\n' "$top" "$base" "$quoted"
fi

if ((ok)); then exit 0; fi
exit 2
