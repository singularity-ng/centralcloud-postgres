# Canonical agent-facing version-control interface.

set no-cd
set positional-arguments

repo := source_directory() + "/.."
runner := repo + "/scripts/repo-vcs.sh"

# Show the current repository working-copy state.
status:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} status

# Show working-copy or revision differences; --check validates added lines.
diff *ARGS:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} diff "$@"

# Show revision history.
log *ARGS:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} log "$@"

# Show one revision.
show REVISION:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} show "$1"

# List jj bookmarks or Git branches, including remote state.
bookmarks:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} bookmarks

# List registered jj workspaces or Git worktrees.
workspace-list:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} workspace-list

# List files owned by the current revision or Git index.
tracked-files:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} tracked-files

# Fetch configured remotes through the selected repository backend.
fetch *ARGS:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} fetch "$@"

# Publish a bookmark only after the repository verification and ancestry gates.
push BOOKMARK="main":
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} push "$1"

# Create a new jj revision. Git-only checkouts fail closed for this jj primitive.
new *REVISIONS:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} new "$@"

# Rebase the current revision or Git branch onto a destination.
rebase DESTINATION:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} rebase "$1"

# Describe the current jj revision or create the current Git commit.
describe MESSAGE REVISION="@":
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} describe "$1" "$2"

# Move a jj bookmark or Git branch to a revision.
bookmark-set NAME REVISION="@":
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} bookmark-set "$1" "$2"

# Delete a merged local lifecycle bookmark or branch.
bookmark-drop NAME:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} bookmark-drop "$1"

# Restore paths from a revision without bypassing the repository facade.
restore REVISION *PATHS:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} restore "$@"

# Create an isolated workspace under the CentralCloud workspace root.
workspace-create NAME REVISION="@":
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} workspace-create "$1" "$2"

# Refresh stale workspace metadata.
workspace-update-stale NAME:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} workspace-update-stale "$1"

# Remove a clean, registered, non-current workspace.
workspace-close NAME:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} workspace-close "$1"

# Remove an unregistered jj workspace directory only when it has no working copy.
workspace-prune-orphan NAME:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} workspace-prune-orphan "$1"

# Run the public VCS facade contract.
test:
    @REPO_VCS_ROOT="{{ repo }}" {{ runner }} contract-test

