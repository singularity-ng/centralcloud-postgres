#!/usr/bin/env bash
# Purpose: Prove centralcloud-postgres exposes one guarded Just-backed VCS interface.
# Consumer: just vcs test, repository maintainers, and agent publication flows.
# Contract: Exercise discovery, revision, workspace, and publication refusal behavior.
# Evidence: Disposable jj/Git fixtures plus static checks of the public Just surface.
# Falsifier: A declared VCS operation needs a native command or an unsafe action passes.

set -euo pipefail

# The contract owns its fixture roots; a caller's facade override must not leak
# into backend-discovery assertions.
unset REPO_VCS_ROOT REPO_VCS_WORKSPACE_ROOT

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
helper="$root/scripts/repo-vcs.sh"
push_helper="$root/scripts/repo-vcs-push.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
	printf 'repo-vcs contract: %s\n' "$*" >&2
	exit 1
}

required_recipes=(
	status diff log show bookmarks workspace-list tracked-files fetch push new rebase describe
	bookmark-set bookmark-drop restore workspace-create workspace-update-stale
	workspace-close workspace-prune-orphan test
)
recipe_summary="$(just --justfile "$root/justfile" --summary)"
for recipe in "${required_recipes[@]}"; do
	if ! tr ' ' '\n' <<<"$recipe_summary" | grep -qx "vcs::$recipe"; then
		fail "missing canonical just vcs recipe: $recipe"
	fi
done

if [ "$(grep -c "^mod vcs 'just/vcs.just'$" "$root/justfile" || true)" -ne 1 ]; then
	fail "root justfile must expose exactly one vcs module"
fi

[ -x "$helper" ] || fail "repo-vcs.sh must be executable"
[ -x "$push_helper" ] || fail "repo-vcs-push.sh must be executable"
grep -q 'run_gate check-vcs' "$push_helper" || fail "push omits the repository VCS quality gate"
grep -q 'run_gate vcs::test' "$push_helper" || fail "push omits the facade contract gate"
grep -q 'remote readback' "$push_helper" || fail "push omits remote readback evidence"
grep -q 'ControlMaster=no.*ControlPath=none.*ControlPersist=no' "$helper" || fail "fetch permits persistent SSH masters"
grep -q 'ControlMaster=no.*ControlPath=none.*ControlPersist=no' "$push_helper" || fail "push permits persistent SSH masters"
if rg -q 'SKIP(_GATE)?|NO_VERIFY|force-with-lease|--force' "$push_helper"; then
	fail "push helper exposes a verification or ancestry bypass"
fi
grep -q 'just vcs push' "$root/AGENTS.md" || fail "root instructions omit the VCS facade"
if rg -q '^[[:space:]]*(jj git push|git push)([[:space:]]|$)' \
	"$root/AGENTS.md"; then
	fail "agent-facing instructions still expose native publication"
fi
just --justfile "$root/justfile" --working-directory "$root" vcs status >/dev/null

mkdir -p "$tmp/invalid/.git/info" "$tmp/invalid/plain"
printf '# invalid marker\n' >"$tmp/invalid/.git/info/exclude"
if (cd "$tmp/invalid/plain" && bash "$helper" backend >/dev/null 2>&1); then
	fail "accepted an incomplete ancestor .git marker as a repository"
fi

repo="$tmp/invalid/pure-jj"
jj git init --no-colocate "$repo" >/dev/null
printf 'clean\n' >"$repo/example.txt"

actual_backend="$(cd "$repo" && bash "$helper" backend)"
[ "$actual_backend" = "jj" ] || fail "expected jj backend, got $actual_backend"

actual_root="$(cd "$repo" && bash "$helper" root)"
[ "$actual_root" = "$repo" ] || fail "expected root $repo, got $actual_root"

if ! REPO_VCS_ROOT="$repo" bash "$helper" tracked-files | grep -qx 'example.txt'; then
	fail "jj tracked-files omitted a working-copy file"
fi

if ! (cd "$repo" && bash "$helper" changed-files working) | grep -qx 'example.txt'; then
	fail "pure-jj changed-files omitted an added file"
fi

(cd "$repo" && bash "$helper" diff-check working)
printf 'trailing whitespace \n' >"$repo/example.txt"
if (cd "$repo" && bash "$helper" diff-check working >/dev/null 2>&1); then
	fail "jj diff-check accepted trailing whitespace"
fi

printf 'clean again\n' >"$repo/example.txt"
(cd "$repo" && bash "$helper" diff-check working)

REPO_VCS_ROOT="$repo" bash "$helper" status >/dev/null
REPO_VCS_ROOT="$repo" bash "$helper" describe 'test: seed facade fixture' >/dev/null
REPO_VCS_ROOT="$repo" bash "$helper" bookmark-set fixture-main >/dev/null
REPO_VCS_ROOT="$repo" bash "$helper" bookmark-set main >/dev/null
if ! REPO_VCS_ROOT="$repo" bash "$helper" bookmarks | grep -q '^fixture-main:'; then
	fail "bookmark-set was not visible through bookmarks"
fi

workspace_root="$tmp/workspaces"
REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-update-stale default >/dev/null
REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-create cleanup-check @ >/dev/null
[ -d "$workspace_root/cleanup-check" ] || fail "workspace-create omitted its directory"
REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-close cleanup-check >/dev/null
[ ! -e "$workspace_root/cleanup-check" ] || fail "workspace-close left its directory behind"

REPO_VCS_ROOT="$repo" bash "$helper" bookmark-drop main >/dev/null
REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-create missing-main-check fixture-main >/dev/null
if REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-close missing-main-check >/dev/null 2>&1; then
	fail "workspace-close treated a revset error as safe"
fi
REPO_VCS_ROOT="$repo" bash "$helper" bookmark-set main fixture-main >/dev/null
REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-close missing-main-check >/dev/null

REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-create unintegrated-check @ >/dev/null
printf 'unique\n' >"$workspace_root/unintegrated-check/unique.txt"
jj --repository "$workspace_root/unintegrated-check" describe -m 'test: unique workspace work' >/dev/null
jj --repository "$workspace_root/unintegrated-check" new >/dev/null
if REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-close unintegrated-check >/dev/null 2>&1; then
	fail "workspace-close discarded clean but unintegrated jj history"
fi
jj --repository "$repo" new main "unintegrated-check@-" >/dev/null
jj --repository "$repo" bookmark set main -r @ >/dev/null
REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-close unintegrated-check >/dev/null

REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-create dirty-check @ >/dev/null
printf 'uncommitted\n' >"$workspace_root/dirty-check/dirty.txt"
if REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-close dirty-check >/dev/null 2>&1; then
	fail "workspace-close accepted a dirty workspace"
fi

REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-create live-check @ >/dev/null
(
	cd "$workspace_root/live-check"
	sleep 30
) &
live_pid=$!
if REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-close live-check >/dev/null 2>&1; then
	kill "$live_pid" 2>/dev/null || true
	fail "workspace-close accepted a workspace owned by a live process"
fi
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-close live-check >/dev/null

if REPO_VCS_ROOT="$repo" REPO_VCS_WORKSPACE_ROOT="$workspace_root" \
	bash "$helper" workspace-create '../escape' @ >/dev/null 2>&1; then
	fail "workspace-create accepted an unsafe name"
fi

push_repo="$tmp/push-repo"
push_origin="$tmp/push-origin.git"
push_peer="$tmp/push-peer"
git init --bare "$push_origin" >/dev/null
jj git init --no-colocate "$push_repo" >/dev/null
printf 'base\n' >"$push_repo/base.txt"
REPO_VCS_ROOT="$push_repo" bash "$helper" describe 'test: push base' >/dev/null
REPO_VCS_ROOT="$push_repo" bash "$helper" bookmark-set main >/dev/null
jj --repository "$push_repo" git remote add origin "$push_origin"
jj --repository "$push_repo" git push --remote origin --bookmark main >/dev/null
git --git-dir="$push_origin" symbolic-ref HEAD refs/heads/main

printf 'local\n' >"$push_repo/local.txt"
REPO_VCS_ROOT="$push_repo" bash "$helper" describe 'test: local divergence' >/dev/null
REPO_VCS_ROOT="$push_repo" bash "$helper" bookmark-set main >/dev/null

jj git clone "$push_origin" "$push_peer" >/dev/null
printf 'remote\n' >"$push_peer/remote.txt"
jj --repository "$push_peer" describe -m 'test: remote divergence' >/dev/null
jj --repository "$push_peer" bookmark set main -r @ >/dev/null
jj --repository "$push_peer" git push --remote origin --bookmark main >/dev/null

set +e
conflict_output="$({
	REPO_VCS_ROOT="$push_repo" \
		XDG_RUNTIME_DIR="$tmp/runtime" \
		REPO_VCS_PUSH_LOCK_HELD=1 \
		bash "$push_helper" main
} 2>&1)"
conflict_status=$?
set -e
[ "$conflict_status" -ne 0 ] || fail "push accepted a conflicted jj bookmark"
grep -q 'local bookmark is conflicted: main' <<<"$conflict_output" ||
	fail "push did not diagnose a conflicted jj bookmark"

git_repo="$tmp/pure-git"
git init "$git_repo" >/dev/null
git -C "$git_repo" config user.name 'VCS Contract'
git -C "$git_repo" config user.email 'vcs-contract@example.invalid'
printf 'tracked\n' >"$git_repo/tracked.txt"
git -C "$git_repo" add tracked.txt
git -C "$git_repo" commit -m 'test: seed Git fixture' >/dev/null
[ "$(REPO_VCS_ROOT="$git_repo" bash "$helper" backend)" = "git" ] ||
	fail "Git-only checkout did not select the Git backend"
REPO_VCS_ROOT="$git_repo" bash "$helper" tracked-files | grep -qx 'tracked.txt' ||
	fail "Git tracked-files omitted an indexed file"
printf 'untracked\n' >"$git_repo/untracked.txt"
REPO_VCS_ROOT="$git_repo" bash "$helper" changed-files working | grep -qx 'untracked.txt' ||
	fail "Git changed-files omitted an untracked file"

grep -q '/centralcloud-postgres' "$helper" || fail "default workspace root is not repository-scoped"

printf 'repo-vcs contract: OK\n'
