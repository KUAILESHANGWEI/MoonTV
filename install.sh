#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${MOONTV_REPO_URL:-https://github.com/KUAILESHANGWEI/MoonTV.git}"
IMAGE="${MOONTV_IMAGE:-ghcr.io/kuileshangwei/moontv:latest}"
CONTAINER_NAME="${MOONTV_CONTAINER_NAME:-moontv}"
HOST_PORT="${MOONTV_PORT:-3000}"
PASSWORD="${PASSWORD:-}"
USERNAME="${USERNAME:-}"
STORAGE_TYPE="${NEXT_PUBLIC_STORAGE_TYPE:-localstorage}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required before installing MoonTV." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but not running." >&2
  exit 1
fi

if [[ -z "$PASSWORD" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    PASSWORD="$(openssl rand -hex 12)"
  else
    PASSWORD="moontv-$(date +%s)-$RANDOM"
  fi
  echo "Generated PASSWORD=$PASSWORD"
fi

if ! docker pull "$IMAGE"; then
  if ! command -v git >/dev/null 2>&1; then
    echo "Pulling $IMAGE failed and git is unavailable for source build fallback." >&2
    exit 1
  fi

  build_dir="$(mktemp -d)"
  cleanup() {
    rm -rf "$build_dir"
  }
  trap cleanup EXIT

  git clone --depth=1 "$REPO_URL" "$build_dir"
  docker build -t "$IMAGE" "$build_dir"
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  docker rm -f "$CONTAINER_NAME" >/dev/null
fi

docker_args=(
  -d
  --name "$CONTAINER_NAME"
  --restart unless-stopped
  -p "$HOST_PORT:3000"
  -e PASSWORD="$PASSWORD"
  -e NEXT_PUBLIC_STORAGE_TYPE="$STORAGE_TYPE"
)

if [[ -n "$USERNAME" ]]; then
  docker_args+=(-e USERNAME="$USERNAME")
fi

docker run "${docker_args[@]}" "$IMAGE" >/dev/null

echo "MoonTV is running at http://127.0.0.1:$HOST_PORT"
echo "Container: $CONTAINER_NAME"
echo "Image: $IMAGE"
