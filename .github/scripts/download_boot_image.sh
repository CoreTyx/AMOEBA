#!/usr/bin/env bash
#=============================================================================
# Fetch the Linux boot image artifact for the current ref.
#
# ONE COPY, CALLED FROM TWO WORKFLOWS.  linux-boot.yml and ci.yml's
# ci-linux-boot-ecc-inject job both need this, and they used to each carry their
# own inline copy.  They drifted the moment one was fixed: the branch-scoping
# relaxation landed in linux-boot.yml and ci.yml kept failing with the old
# message, which read as a code regression rather than as a stale duplicate.
#
# THE BRANCH SCOPING IS CONDITIONAL, AND THAT IS THE POINT.  An unscoped lookup
# takes the newest success on any branch, so a PR that edits the kernel could
# silently boot main's kernel and prove nothing about the change under review.
# But the image is built from testcode/linux/** and bin/linux_image_to_lst.py
# and NOTHING ELSE, so a ref that touches neither cannot affect it, and for
# those the default branch's image IS the same image.  Scoping unconditionally
# made these jobs permanently red on every hardware-only PR -- which is most of
# them.  A job that always fails for a reason unrelated to the change is a job
# people learn to ignore, which is worse than one that is occasionally too
# permissive.
#
# Needs: GH_TOKEN, GITHUB_REPOSITORY, and GITHUB_HEAD_REF or GITHUB_REF_NAME.
# Optional: PR_NUMBER (set it for pull_request events, or there is no base to
# compare against and no fallback is allowed), DEFAULT_BRANCH, DEST.
#=============================================================================
set -euo pipefail

DEST="${DEST:-testcode/linux/build}"
mkdir -p "$DEST"

BRANCH="${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}"

find_image () {   # $1 = branch name, prints a run id or nothing
  gh run list --repo "$GITHUB_REPOSITORY" --branch "$1" \
    --workflow linux-image.yml --status success \
    --limit 1 --json databaseId --jq '.[0].databaseId'
}

echo "Looking for a boot image built from branch: $BRANCH"
RUN_ID=$(find_image "$BRANCH")
IMAGE_FROM="$BRANCH"

if [ -z "$RUN_ID" ]; then
  if [ -n "${PR_NUMBER:-}" ]; then
    # Fetched then filtered in two steps on purpose: piping gh into grep under
    # `set -o pipefail` with a `|| true` would swallow an API failure and read it
    # as "nothing changed", and that is the one direction this must not fail
    # open in.
    FILES=$(gh api --paginate \
              "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/files" \
              --jq '.[].filename')
    CHANGED=$(printf '%s\n' "$FILES" \
              | grep -E '^(testcode/linux/|bin/linux_image_to_lst\.py$)' || true)
  else
    CHANGED="(not a pull request, so there is no base to fall back from)"
  fi

  if [ -n "$CHANGED" ]; then
    echo "No successful linux-image.yml run on branch '$BRANCH', and this ref"
    echo "changes the image sources, so another branch's image would not"
    echo "represent it.  Changed:"
    printf '  %s\n' "$CHANGED"
    echo "Run Actions -> Linux Boot Image -> Run workflow against '$BRANCH',"
    echo "then re-run this job."
    exit 1
  fi

  FALLBACK="${DEFAULT_BRANCH:-main}"
  echo "::notice::No boot image for '$BRANCH', and it does not touch the image sources, so falling back to '$FALLBACK'."
  RUN_ID=$(find_image "$FALLBACK")
  IMAGE_FROM="$FALLBACK"
  if [ -z "$RUN_ID" ]; then
    echo "No successful linux-image.yml run on '$FALLBACK' either, so there is"
    echo "no image anywhere to boot.  Run Actions -> Linux Boot Image -> Run"
    echo "workflow."
    exit 1
  fi
fi

echo "Using boot image from branch '$IMAGE_FROM' (run $RUN_ID)"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "LINUX_IMAGE_FROM=$IMAGE_FROM" >> "$GITHUB_ENV"
fi
gh run download "$RUN_ID" --repo "$GITHUB_REPOSITORY" \
  --name amoeba-linux-boot-image --dir "$DEST"
ls -la "$DEST"
