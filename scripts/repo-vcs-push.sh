#!/usr/bin/env bash
# Version: centralcloud-postgres-repo-vcs-push/v1
# Purpose: Publish a centralcloud-postgres bookmark only after ancestry and repo-owned gates.
# Consumer: just vcs push and repository agents.
# Contract: Serialize publication, refresh origin, reject history loss, run the
# scoped Nix checks, push once, and prove the remote bookmark equals local.
# Evidence: just vcs test plus a successful just vcs push remote readback.
# Falsifier: A failed gate, stale remote, or non-ancestor update reaches origin.

set -euo pipefail

run_remote_vcs() {
	GIT_SSH_COMMAND="${REPO_VCS_GIT_SSH_COMMAND:-ssh -o ControlMaster=no -o ControlPath=none -o ControlPersist=no}" "$@"
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
helper="$script_dir/repo-vcs.sh"
bookmark="${1:-}"

[[ "$bookmark" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ ]] || {
	printf 'repo-vcs-push: invalid bookmark name: %s\n' "$bookmark" >&2
	exit 2
}

backend="$(bash "$helper" backend)"
root="$(bash "$helper" root)"
lock_root="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/centralcloud-postgres"
mkdir -p "$lock_root"

if [ "${REPO_VCS_PUSH_LOCK_HELD:-0}" != "1" ]; then
	set +e
	flock --close --nonblock --conflict-exit-code 75 "$lock_root/push.lock" \
		env REPO_VCS_ROOT="$root" REPO_VCS_PUSH_LOCK_HELD=1 "$0" "$bookmark"
	status=$?
	set -e
	if [ "$status" -eq 75 ]; then
		echo "repo-vcs-push: another repository publication is already running" >&2
	fi
	exit "$status"
fi

run_gate() {
	local recipe="$1"
	if [ ! -e "$root/flake.nix" ] && [ ! -e "$root/shell.nix" ] && [ ! -e "$root/default.nix" ]; then
		env -u REPO_VCS_ROOT -u REPO_VCS_WORKSPACE_ROOT \
			just --justfile "$root/justfile" --working-directory "$root" "$recipe"
	elif [ -n "${IN_NIX_SHELL:-}" ]; then
		env -u REPO_VCS_ROOT -u REPO_VCS_WORKSPACE_ROOT \
			just --justfile "$root/justfile" --working-directory "$root" "$recipe"
	else
		env -u REPO_VCS_ROOT -u REPO_VCS_WORKSPACE_ROOT \
			nix develop "path:$root" --command \
			just --justfile "$root/justfile" --working-directory "$root" "$recipe"
	fi
}

if [ "$backend" = "jj" ]; then
	run_remote_vcs jj --repository "$root" git fetch --remote origin
	local_revset="bookmarks(exact:\"$bookmark\")"
	remote_revset="remote_bookmarks(exact:\"$bookmark\", exact:\"origin\")"
	mapfile -t local_commits < <(
		jj --repository "$root" log -r "$local_revset" --no-graph -T 'commit_id ++ "\n"'
	)
	[ "${#local_commits[@]}" -gt 0 ] || {
		echo "repo-vcs-push: local bookmark is missing: $bookmark" >&2
		exit 1
	}
	[ "${#local_commits[@]}" -eq 1 ] || {
		echo "repo-vcs-push: local bookmark is conflicted: $bookmark" >&2
		exit 1
	}
	local_commit="${local_commits[0]}"
	mapfile -t remote_commits < <(
		jj --repository "$root" log -r "$remote_revset" --no-graph -T 'commit_id ++ "\n"'
	)
	[ "${#remote_commits[@]}" -le 1 ] || {
		echo "repo-vcs-push: remote bookmark is conflicted: $bookmark@origin" >&2
		exit 1
	}
	remote_commit="${remote_commits[0]:-}"
	if [ -n "$remote_commit" ]; then
		ancestry_gap="$(jj --repository "$root" log -r "$remote_commit & ~::$local_commit" --no-graph -T 'commit_id')"
		[ -z "$ancestry_gap" ] || {
			echo "repo-vcs-push: refusing history loss; $bookmark does not contain $bookmark@origin" >&2
			exit 1
		}
	fi
else
	git -C "$root" fetch origin --prune
	local_commit="$(git -C "$root" rev-parse --verify "refs/heads/$bookmark")"
	remote_commit="$(git -C "$root" rev-parse --verify "refs/remotes/origin/$bookmark" 2>/dev/null || true)"
	if [ -n "$remote_commit" ] && ! git -C "$root" merge-base --is-ancestor "$remote_commit" "$local_commit"; then
		echo "repo-vcs-push: refusing history loss; $bookmark does not contain origin/$bookmark" >&2
		exit 1
	fi
fi

run_gate check-vcs
run_gate vcs::test

if [ "$backend" = "jj" ]; then
	# Fresh colocated repositories may expose origin/main as an untracked remote
	# bookmark. Import that exact publication target before pushing; ancestry was
	# already proven above.
	jj --repository "$root" bookmark track "$bookmark" --remote=origin >/dev/null 2>&1 || true
	run_remote_vcs jj --repository "$root" git push --remote origin --bookmark "$bookmark"
	run_remote_vcs jj --repository "$root" git fetch --remote origin
	mapfile -t remote_commits < <(
		jj --repository "$root" log -r "$remote_revset" --no-graph -T 'commit_id ++ "\n"'
	)
	[ "${#remote_commits[@]}" -eq 1 ] || {
		echo "repo-vcs-push: remote readback is missing or conflicted: $bookmark@origin" >&2
		exit 1
	}
	remote_commit="${remote_commits[0]}"
else
	git -C "$root" push origin "refs/heads/$bookmark:refs/heads/$bookmark"
	git -C "$root" fetch origin --prune
	remote_commit="$(git -C "$root" rev-parse --verify "refs/remotes/origin/$bookmark")"
fi

[ "$local_commit" = "$remote_commit" ] || {
	printf 'repo-vcs-push: remote readback mismatch: local=%s remote=%s\n' "$local_commit" "$remote_commit" >&2
	exit 1
}

printf 'repo-vcs-push: published %s %s to origin and verified remote readback\n' "$bookmark" "$local_commit"
