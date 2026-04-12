#!/usr/bin/env bash
# Deploy NanoClaw agent(s) to target machines
# Usage:
#   ./deploy.sh <agent-name>             Deploy one agent (sync + build + restart)
#   ./deploy.sh <agent-name> --dry-run   Show files that would change + diffs
#   ./deploy.sh <agent-name> --init      First-time: sync code + overlay, skip postDeploy
#                                        Then SSH in and run /setup on the target
#   ./deploy.sh --all                    Deploy all agents
#   ./deploy.sh --all --code             Core code only (skip .env/personality)
set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed. Install with: brew install jq" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/agents"

# Core code excludes — these are never rsynced
# groups/: sync groups/global/ (shared personality/memory, part of core),
# but exclude all other groups/* which hold per-instance runtime data.
CORE_EXCLUDES=(
  --exclude='agents/'
  --exclude='store/'
  --exclude='data/'
  --exclude='logs/'
  --include='groups/'
  --include='groups/global/***'
  --exclude='groups/*'
  --exclude='node_modules/'
  --exclude='dist/'
  --exclude='.env'
  --exclude='.git/'
  --exclude='deploy.sh'
  --exclude='FORK_CHANGELOG.md'
  --exclude='.claude/settings.local.json'
  --exclude='.DS_Store'
  --exclude='.nanoclaw/'
)

# Show files that would change + actual diffs, without making changes.
# Processes rsync --itemize-changes output:
#   >f......... path    (file identical but metadata diff — no content diff)
#   >f..t...... path    (timestamp only)
#   >f.st...... path    (size + timestamp — real content diff)
#   >f+++++++++ path    (new file)
#   *deleting   path    (file being removed on remote)
show_diff() {
  local src_root="$1"  # local dir (with trailing /)
  local dst_spec="$2"  # host:path/ spec
  local host="$3"
  local dst_path="$4"
  shift 4
  local excludes=("$@")

  local changes
  if [[ ${#excludes[@]} -gt 0 ]]; then
    changes=$(rsync -azn --delete --itemize-changes "${excludes[@]}" "$src_root" "$dst_spec" 2>&1 || true)
  else
    changes=$(rsync -azn --itemize-changes "$src_root" "$dst_spec" 2>&1 || true)
  fi

  if [[ -z "$changes" ]]; then
    echo "  (no changes)"
    return
  fi

  local has_content_changes=false
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Skip rsync's directory-only updates
    if [[ "$line" =~ ^cd ]] || [[ "$line" =~ ^\.d ]]; then continue; fi

    if [[ "$line" =~ ^\*deleting[[:space:]]+(.+)$ ]]; then
      local file="${BASH_REMATCH[1]}"
      echo "  DELETE  $file"
      has_content_changes=true
    elif [[ "$line" =~ ^([\>\<][f])([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
      local flags="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
      local file="${BASH_REMATCH[3]}"
      # New file
      if [[ "${flags:2:1}" == "+" ]]; then
        echo "  ADD     $file"
        has_content_changes=true
        continue
      fi
      # Has content change? 's' (size) or 'c' (checksum) means real diff
      if [[ "${flags:3:1}" == "s" ]] || [[ "${flags:2:1}" == "c" ]]; then
        echo "  MODIFY  $file"
        has_content_changes=true
      fi
    fi
  done <<< "$changes"

  if [[ "$has_content_changes" != "true" ]]; then
    return
  fi

  # Second pass: show actual diffs for modified files
  echo ""
  echo "  --- diffs ---"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ ! "$line" =~ ^([\>\<][f])([^[:space:]]+)[[:space:]]+(.+)$ ]]; then continue; fi
    local flags="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    local file="${BASH_REMATCH[3]}"
    # Skip unchanged content (timestamp/permission only)
    if [[ "${flags:2:1}" != "+" && "${flags:3:1}" != "s" && "${flags:2:1}" != "c" ]]; then continue; fi

    echo ""
    echo "  ==> $file"
    local local_file="${src_root}${file}"
    if [[ "${flags:2:1}" == "+" ]]; then
      echo "  (new file — $(wc -l < "$local_file" 2>/dev/null || echo 0) lines)"
      continue
    fi
    # Fetch remote version and diff against local
    # </dev/null is CRITICAL: otherwise ssh consumes the while-loop's stdin
    ssh "$host" "cat $(printf '%q' "$dst_path/$file")" </dev/null 2>/dev/null \
      | diff -u --label "remote:$file" --label "local:$file" - "$local_file" \
      | sed 's/^/  /' || true
  done <<< "$changes"
}

deploy_agent() {
  local agent_name="$1"
  local code_only="${2:-false}"
  local init_mode="${3:-false}"
  local dry_run="${4:-false}"
  local agent_dir="$AGENTS_DIR/$agent_name"

  if [[ ! -d "$agent_dir" ]]; then
    echo "Error: Agent '$agent_name' not found in $AGENTS_DIR" >&2
    exit 1
  fi

  local config="$agent_dir/agent.json"
  if [[ ! -f "$config" ]]; then
    echo "Error: No agent.json found for '$agent_name'" >&2
    exit 1
  fi

  local host name path post_deploy
  name=$(jq -r '.name' "$config")
  host=$(jq -r '.host' "$config")
  path=$(jq -r '.path' "$config")
  post_deploy=$(jq -r '.postDeploy // empty' "$config")

  if [[ "$dry_run" == "true" ]]; then
    echo "==> Dry run for $name ($host:$path)"
    if [[ "$host" == "localhost" ]]; then
      echo "  (localhost — no rsync would run)"
      return
    fi
    echo ""
    echo "  Core code changes:"
    show_diff "$SCRIPT_DIR/" "$host:$path/" "$host" "$path" "${CORE_EXCLUDES[@]}"
    if [[ "$code_only" != "true" && -d "$agent_dir/groups" ]]; then
      echo ""
      echo "  Overlay (groups/) changes:"
      show_diff "$agent_dir/groups/" "$host:$path/groups/" "$host" "$path/groups"
    fi
    return
  fi

  echo "==> Deploying $name to $host:$path"

  if [[ "$host" == "localhost" ]]; then
    echo "  Skipping rsync for localhost agent"
    if [[ -n "$post_deploy" && "$init_mode" != "true" ]]; then
      echo "  Running post-deploy locally: $post_deploy"
      (cd "$path" && eval "$post_deploy")
    fi
  else
    # Step 1: rsync core code
    echo "  Syncing core code..."
    rsync -az --delete "${CORE_EXCLUDES[@]}" "$SCRIPT_DIR/" "$host:$path/"

    # Step 2: rsync agent overlay (personality files, groups)
    if [[ "$code_only" != "true" ]]; then
      echo "  Syncing agent overlay..."
      # Sync groups/ from the overlay
      if [[ -d "$agent_dir/groups" ]]; then
        rsync -az "$agent_dir/groups/" "$host:$path/groups/"
      fi
      # Sync .env if it exists
      if [[ -f "$agent_dir/.env" ]]; then
        rsync -az "$agent_dir/.env" "$host:$path/.env"
      fi
    fi

    # Step 3: Run post-deploy command (skipped in init mode — run /setup on target)
    if [[ "$init_mode" == "true" ]]; then
      echo "  Init mode: skipping post-deploy"
      echo ""
      echo "  Next steps on the target machine:"
      echo "    ssh $host"
      echo "    cd $path"
      echo "    claude  # then run /setup"
    elif [[ -n "$post_deploy" ]]; then
      echo "  Running post-deploy: $post_deploy"
      ssh "$host" "cd $(printf '%q' "$path") && $post_deploy"
    fi
  fi

  echo "  Done: $name"
}

# Parse arguments
CODE_ONLY=false
INIT_MODE=false
DRY_RUN=false
DEPLOY_ALL=false
AGENT_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)     DEPLOY_ALL=true; shift ;;
    --code)    CODE_ONLY=true; shift ;;
    --init)    INIT_MODE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -*)        echo "Unknown option: $1" >&2; exit 1 ;;
    *)         AGENT_NAME="$1"; shift ;;
  esac
done

shopt -s nullglob

if [[ "$DEPLOY_ALL" == "true" ]]; then
  agents=("$AGENTS_DIR"/*/)
  if [[ ${#agents[@]} -eq 0 ]]; then
    echo "Error: No agents found in $AGENTS_DIR" >&2
    exit 1
  fi
  for agent_dir in "${agents[@]}"; do
    agent=$(basename "$agent_dir")
    deploy_agent "$agent" "$CODE_ONLY" "$INIT_MODE" "$DRY_RUN"
  done
elif [[ -n "$AGENT_NAME" ]]; then
  deploy_agent "$AGENT_NAME" "$CODE_ONLY" "$INIT_MODE" "$DRY_RUN"
else
  echo "Usage:"
  echo "  ./deploy.sh <agent-name>             Deploy one agent (sync + build + restart)"
  echo "  ./deploy.sh <agent-name> --dry-run   Preview: show files + diffs, don't deploy"
  echo "  ./deploy.sh <agent-name> --init      First-time: sync only, skip postDeploy"
  echo "  ./deploy.sh --all                    Deploy all agents"
  echo "  ./deploy.sh --all --code             Core code only (skip .env/personality)"
  echo ""
  echo "Available agents:"
  agents=("$AGENTS_DIR"/*/)
  if [[ ${#agents[@]} -eq 0 ]]; then
    echo "  (none)"
  else
    for agent_dir in "${agents[@]}"; do
      agent=$(basename "$agent_dir")
      host=$(jq -r '.host' "$agent_dir/agent.json" 2>/dev/null || echo "unknown")
      echo "  $agent → $host"
    done
  fi
  exit 1
fi
