#!/usr/bin/env bash
# Version: centralcloud-postgres-repo-vcs/v1
# Purpose: Provide centralcloud-postgres's one agent-facing Just-backed VCS interface while
# keeping validators portable across canonical jj workspaces and Git-only CI clones.
# Consumer: just vcs recipes, repository validators, and repository agents.
# Contract: Detect a validated backend, scope every operation to its real root,
# fail closed on unsupported or unsafe lifecycle actions, and propagate errors.
# Evidence: just vcs test exercises discovery, revision, and workspace behavior.
# Falsifier: An agent needs a native jj/Git command for a declared operation, or
# an invalid ancestor marker or dirty/live workspace passes a safety gate.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

die() {
	printf 'repo-vcs: %s\n' "$*" >&2
	exit 1
}

usage() {
	die "usage: $0 {backend|root|changed-files|tracked-files|diff-check|status|diff|log|show|bookmarks|workspace-list|fetch|push|new|rebase|describe|bookmark-set|bookmark-drop|restore|workspace-create|workspace-update-stale|workspace-drop|workspace-prune-orphan|contract-test} [args...]"
}

candidate_root() {
	if [ -n "${REPO_VCS_ROOT:-}" ]; then
		[ -d "$REPO_VCS_ROOT" ] || die "REPO_VCS_ROOT is not a directory: $REPO_VCS_ROOT"
		(cd "$REPO_VCS_ROOT" && pwd -P)
	else
		pwd -P
	fi
}

detect_backend_at() {
	local candidate="$1"
	if command -v jj >/dev/null 2>&1 && jj --repository "$candidate" root >/dev/null 2>&1; then
		printf 'jj\n'
		return
	fi
	if command -v git >/dev/null 2>&1 &&
		[ "$(git -C "$candidate" rev-parse --is-inside-work-tree 2>/dev/null || true)" = "true" ]; then
		printf 'git\n'
		return
	fi
	die "path is not inside a validated jj workspace or Git worktree: $candidate"
}

resolve_root() {
	local candidate="$1"
	local selected_backend="$2"
	case "$selected_backend" in
	jj) jj --repository "$candidate" root ;;
	git) git -C "$candidate" rev-parse --show-toplevel ;;
	*) die "unsupported backend: $selected_backend" ;;
	esac
}

candidate="$(candidate_root)"
backend="$(detect_backend_at "$candidate")"
root="$(resolve_root "$candidate" "$backend")"

run_remote_vcs() {
	GIT_SSH_COMMAND="${REPO_VCS_GIT_SSH_COMMAND:-ssh -o ControlMaster=no -o ControlPath=none -o ControlPersist=no}" "$@"
}

require_jj() {
	[ "$backend" = "jj" ] || die "$1 requires the canonical jj workspace backend; Git-only clones are CI/breakglass surfaces"
}

validate_workspace_name() {
	local name="$1"
	[[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "invalid workspace name: $name"
}

workspace_root() {
	if [ -n "${REPO_VCS_WORKSPACE_ROOT:-}" ]; then
		printf '%s\n' "$REPO_VCS_WORKSPACE_ROOT"
	else
		printf '%s/code/worktrees/%s/centralcloud-postgres\n' "$HOME" "$backend"
	fi
}

workspace_has_live_cwd() {
	local workspace_path="$1"
	local cwd target
	for cwd in /proc/[0-9]*/cwd; do
		target="$(readlink "$cwd" 2>/dev/null || true)"
		case "$target" in
		"$workspace_path" | "$workspace_path"/*)
			printf 'repo-vcs: workspace is the cwd of a live process: %s -> %s\n' "$cwd" "$target" >&2
			return 0
			;;
		esac
	done
	return 1
}

git_workspace_registered() {
	local workspace_path="$1"
	git -C "$root" worktree list --porcelain |
		awk '/^worktree / { print substr($0, 10) }' |
		grep -Fxq "$(realpath "$workspace_path")"
}

registered_workspace_path() {
	local name="$1"
	case "$backend" in
	jj)
		jj --repository "$root" workspace list --ignore-working-copy \
			-T 'if(name == "'"$name"'", root ++ "\n", "")' |
			awk 'NF { if (found++) exit 2; path=$0 } END { if (!found) exit 1; print path }' ||
			die "workspace is not registered exactly once: $name"
		;;
	git)
		git -C "$root" worktree list --porcelain |
			awk -v wanted="$name" '
          /^worktree / { path=substr($0, 10); branch="" }
          /^branch / { branch=$0; sub(/^branch refs\/heads\//, "", branch) }
          /^$/ { if (branch == wanted) { if (found++) exit 2; match=path } }
          END { if (!found) exit 1; print match }
        ' || die "worktree is not registered exactly once: $name"
		;;
	esac
}

git_changed_files() {
	local mode="$1"
	case "$mode" in
	staged)
		git -C "$root" diff --cached --name-only --diff-filter=ACMR
		;;
	changed | working)
		{
			git -C "$root" diff --name-only --diff-filter=ACMR HEAD
			git -C "$root" ls-files --others --exclude-standard
		} | awk 'NF && !seen[$0]++'
		;;
	*) die "unsupported Git changed-files mode: $mode" ;;
	esac
}

jj_changed_files() {
	local mode="$1"
	case "$mode" in
	staged | changed | working)
		jj --repository "$root" diff --name-only | while IFS= read -r path; do
			if [ -e "$root/$path" ] || [ -L "$root/$path" ]; then
				printf '%s\n' "$path"
			fi
		done
		;;
	*) die "unsupported jj changed-files mode: $mode" ;;
	esac
}

changed_files() {
	local mode="${1:-working}"
	case "$backend" in
	jj) jj_changed_files "$mode" ;;
	git) git_changed_files "$mode" ;;
	esac
}

check_patch_whitespace() {
	awk '
		/^\+\+\+ / { next }
		/^\+/ {
			line = substr($0, 2)
			if (line ~ /[ \t\r]+$/) {
				print "repo-vcs: added line has trailing whitespace: " line > "/dev/stderr"
				invalid = 1
			}
			if (line ~ /^(<<<<<<< |=======|>>>>>>> )/) {
				print "repo-vcs: added line contains a conflict marker: " line > "/dev/stderr"
				invalid = 1
			}
		}
		END { exit invalid }
	'
}

diff_check() {
	local mode="${1:-working}"
	if [ "$backend" = "jj" ]; then
		case "$mode" in
		staged | changed | working | all)
			jj --repository "$root" diff --git --color=never | check_patch_whitespace
			;;
		*) die "unsupported jj diff-check mode: $mode" ;;
		esac
		return
	fi

	case "$mode" in
	staged) git -C "$root" diff --check --cached ;;
	changed | working | all) git -C "$root" diff --check ;;
	*) die "unsupported Git diff-check mode: $mode" ;;
	esac
}

command_name="${1:-}"
[ -n "$command_name" ] || usage
shift

case "$command_name" in
backend)
	[ "$#" -eq 0 ] || usage
	printf '%s\n' "$backend"
	;;
root)
	[ "$#" -eq 0 ] || usage
	printf '%s\n' "$root"
	;;
changed-files)
	[ "$#" -le 1 ] || usage
	changed_files "${1:-working}"
	;;
tracked-files)
	[ "$#" -eq 0 ] || usage
	case "$backend" in
	jj) (cd "$root" && jj file list -r @) ;;
	git) git -C "$root" ls-files ;;
	esac
	;;
diff-check)
	[ "$#" -le 1 ] || usage
	diff_check "${1:-working}"
	;;
status)
	case "$backend" in
	jj) jj --repository "$root" status "$@" ;;
	git) git -C "$root" status "$@" ;;
	esac
	;;
diff)
	if [ "${1:-}" = "--check" ]; then
		shift
		[ "$#" -eq 0 ] || die "diff --check does not accept additional arguments"
		diff_check working
	elif [ "$backend" = "jj" ]; then
		jj --repository "$root" diff "$@"
	else
		git -C "$root" diff "$@"
	fi
	;;
log)
	case "$backend" in
	jj) jj --repository "$root" log "$@" ;;
	git) git -C "$root" log "$@" ;;
	esac
	;;
show)
	[ "$#" -eq 1 ] || usage
	case "$backend" in
	jj) jj --repository "$root" show "$1" ;;
	git) git -C "$root" show "$1" ;;
	esac
	;;
bookmarks)
	[ "$#" -eq 0 ] || usage
	case "$backend" in
	jj) jj --repository "$root" bookmark list --all-remotes ;;
	git) git -C "$root" branch --all --verbose --verbose ;;
	esac
	;;
workspace-list)
	[ "$#" -eq 0 ] || usage
	case "$backend" in
	jj) jj --repository "$root" workspace list ;;
	git) git -C "$root" worktree list ;;
	esac
	;;
fetch)
	if [ "$backend" = "jj" ]; then
		run_remote_vcs jj --repository "$root" git fetch "$@"
	elif [ "$#" -gt 0 ]; then
		git -C "$root" fetch "$@"
	else
		git -C "$root" fetch --all --prune
	fi
	;;
push)
	[ "$#" -eq 1 ] || usage
	exec env REPO_VCS_ROOT="$root" "$script_dir/repo-vcs-push.sh" "$1"
	;;
new)
	require_jj new
	jj --repository "$root" new "$@"
	;;
rebase)
	[ "$#" -eq 1 ] || usage
	case "$backend" in
	jj) jj --repository "$root" rebase -r @ -d "$1" ;;
	git) git -C "$root" rebase "$1" ;;
	esac
	;;
describe)
	[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
	if [ "$backend" = "jj" ]; then
		jj --repository "$root" describe -m "$1" -r "${2:-@}"
	else
		case "${2:-@}" in
		@ | HEAD) ;;
		*) die "Git describe can only commit the current working copy" ;;
		esac
		git -C "$root" add --all
		git -C "$root" diff --cached --quiet && die "nothing to commit"
		git -C "$root" commit -m "$1"
	fi
	;;
bookmark-set)
	[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
	if [ "$backend" = "jj" ]; then
		jj --repository "$root" bookmark set "$1" -r "${2:-@}"
	else
		revision="${2:-HEAD}"
		[ "$revision" != "@" ] || revision=HEAD
		git -C "$root" branch --force "$1" "$revision"
	fi
	;;
bookmark-drop)
	[ "$#" -eq 1 ] || usage
	case "$backend" in
	jj) jj --repository "$root" bookmark delete "$1" ;;
	git) git -C "$root" branch --delete "$1" ;;
	esac
	;;
restore)
	[ "$#" -ge 2 ] || usage
	revision="$1"
	shift
	case "$backend" in
	jj) jj --repository "$root" restore --from "$revision" -- "$@" ;;
	git) git -C "$root" restore --source "$revision" -- "$@" ;;
	esac
	;;
workspace-create)
	[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
	name="$1"
	revision="${2:-@}"
	validate_workspace_name "$name"
	workspace_base="$(workspace_root)"
	workspace_path="$workspace_base/$name"
	[ ! -e "$workspace_path" ] || die "workspace path already exists: $workspace_path"
	mkdir -p "$workspace_base"
	if [ "$backend" = "jj" ]; then
		jj --repository "$root" workspace add -r "$revision" --name "$name" "$workspace_path"
	else
		[ "$revision" != "@" ] || revision=HEAD
		if git -C "$root" show-ref --verify --quiet "refs/heads/$name"; then
			git -C "$root" worktree add "$workspace_path" "$name"
		else
			git -C "$root" worktree add -b "$name" "$workspace_path" "$revision"
		fi
	fi
	;;
workspace-update-stale)
	[ "$#" -eq 1 ] || usage
	name="$1"
	validate_workspace_name "$name"
	workspace_path="$(registered_workspace_path "$name")"
	if [ "$backend" = "jj" ]; then
		[ -e "$workspace_path/.jj" ] || die "workspace path is missing or is not jj: $workspace_path"
		jj --repository "$workspace_path" workspace update-stale
	else
		[ -e "$workspace_path/.git" ] || die "workspace path is missing or is not Git: $workspace_path"
		git_workspace_registered "$workspace_path" || die "refusing to update unregistered worktree: $name"
		git -C "$root" worktree repair "$workspace_path"
	fi
	;;
workspace-drop)
	[ "$#" -eq 1 ] || usage
	name="$1"
	validate_workspace_name "$name"
	workspace_path="$(registered_workspace_path "$name")"
	[ -e "$workspace_path" ] || die "workspace path is missing: $workspace_path"
	[ "$(realpath "$root")" != "$(realpath "$workspace_path")" ] ||
		die "refusing to drop the current workspace; use another registered workspace"
	workspace_has_live_cwd "$workspace_path" && die "refusing to drop a workspace owned by a live process"
	if [ "$backend" = "jj" ]; then
		[ -e "$workspace_path/.jj" ] || die "workspace path is not jj: $workspace_path"
		jj --repository "$root" workspace list | cut -d: -f1 | grep -Fxq "$name" ||
			die "refusing to drop unregistered workspace: $name"
		[ -z "$(jj --repository "$workspace_path" diff --summary)" ] ||
			die "refusing to drop dirty workspace: $name"
		jj --repository "$root" workspace forget "$name"
		rm -rf -- "$workspace_path"
	else
		[ -e "$workspace_path/.git" ] || die "workspace path is not Git: $workspace_path"
		git_workspace_registered "$workspace_path" || die "refusing to drop unregistered worktree: $name"
		[ -z "$(git -C "$workspace_path" status --porcelain)" ] ||
			die "refusing to drop dirty worktree: $name"
		git -C "$root" worktree remove "$workspace_path"
	fi
	;;
workspace-prune-orphan)
	[ "$#" -eq 1 ] || usage
	require_jj workspace-prune-orphan
	name="$1"
	validate_workspace_name "$name"
	workspace_path="$(workspace_root)/$name"
	[ -e "$workspace_path/.jj" ] || die "workspace path is missing or is not jj: $workspace_path"
	if jj --repository "$root" workspace list | cut -d: -f1 | grep -Fxq "$name"; then
		die "refusing to prune registered workspace: $name"
	fi
	workspace_has_live_cwd "$workspace_path" && die "refusing to prune a workspace owned by a live process"
	orphan_status="$(jj --repository "$workspace_path" status 2>&1)" ||
		die "refusing to prune workspace with unreadable state: $name"
	[ "$orphan_status" = "No working copy" ] ||
		die "refusing to prune workspace with recoverable working-copy state: $name"
	rm -rf -- "$workspace_path"
	;;
contract-test)
	[ "$#" -eq 0 ] || usage
	exec env -u REPO_VCS_ROOT -u REPO_VCS_WORKSPACE_ROOT \
		bash "$script_dir/test-repo-vcs.sh"
	;;
*) usage ;;
esac
