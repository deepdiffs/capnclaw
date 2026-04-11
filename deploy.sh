#!/usr/bin/env bash
# Deploy NanoClaw agent(s) to target machines
# Usage:
#   ./deploy.sh <agent-name>       Deploy one agent
#   ./deploy.sh --all              Deploy all agents
#   ./deploy.sh --all --code       Core code only (skip .env/personality)
set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed. Install with: brew install jq" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/agents"

# Core code excludes — these are never rsynced
CORE_EXCLUDES=(
  --exclude='agents/'
  --exclude='store/'
  --exclude='data/'
  --exclude='logs/'
  --exclude='node_modules/'
  --exclude='dist/'
  --exclude='.env'
  --exclude='.git/'
  --exclude='.DS_Store'
  --exclude='.nanoclaw/'
)

deploy_agent() {
  local agent_name="$1"
  local code_only="${2:-false}"
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

  echo "==> Deploying $name to $host:$path"

  if [[ "$host" == "localhost" ]]; then
    echo "  Skipping rsync for localhost agent"
    if [[ -n "$post_deploy" ]]; then
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

    # Step 3: Run post-deploy command
    if [[ -n "$post_deploy" ]]; then
      echo "  Running post-deploy: $post_deploy"
      ssh "$host" "cd $(printf '%q' "$path") && $post_deploy"
    fi
  fi

  echo "  Done: $name"
}

# Parse arguments
CODE_ONLY=false
DEPLOY_ALL=false
AGENT_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)  DEPLOY_ALL=true; shift ;;
    --code) CODE_ONLY=true; shift ;;
    -*)     echo "Unknown option: $1" >&2; exit 1 ;;
    *)      AGENT_NAME="$1"; shift ;;
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
    deploy_agent "$agent" "$CODE_ONLY"
  done
elif [[ -n "$AGENT_NAME" ]]; then
  deploy_agent "$AGENT_NAME" "$CODE_ONLY"
else
  echo "Usage:"
  echo "  ./deploy.sh <agent-name>       Deploy one agent"
  echo "  ./deploy.sh --all              Deploy all agents"
  echo "  ./deploy.sh --all --code       Core code only (skip .env/personality)"
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
