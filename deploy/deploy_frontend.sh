#!/usr/bin/env bash
# 本机 standalone 构建 -> 上传 -> 官方 node 镜像直接 node server.js（服务器不再 npm install）
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519_root_117_72_100_59}"
SSH_HOST="${SSH_HOST:-root@117.72.100.59}"
REMOTE_PROJECT_DIR="${REMOTE_PROJECT_DIR:-/data/ai-novel-generator}"
COMPOSE_FILE="deploy/docker-compose.prod.yml"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FRONTEND_DIR="$PROJECT_DIR/frontend"
cd "$FRONTEND_DIR"

ssh_cmd() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=25 -o ServerAliveInterval=10 "$SSH_HOST" "$@"
}

echo -e "${CYAN}AI NovelGenerator - Frontend Deploy (standalone)${NC}"

if [ ! -f "$SSH_KEY" ]; then
  echo -e "${RED}[ERROR]${NC} SSH key missing: $SSH_KEY"; exit 1
fi
ssh_cmd "echo SSH_OK" >/dev/null

if [ "${SKIP_LOCAL_BUILD:-0}" = "1" ] && [ -f .next/standalone/server.js ]; then
  echo "[Step] reuse existing standalone"
else
  echo "[Step] local standalone build..."
  if [ ! -d node_modules ]; then
    npm install --registry https://registry.npmmirror.com
  fi
  export NEXT_PUBLIC_API_BASE=http://117.72.100.59:9001
  export NODE_ENV=production
  export DOCKER_BUILD=1
  npm run build
fi

if [ ! -f .next/standalone/server.js ]; then
  echo -e "${RED}[ERROR]${NC} .next/standalone/server.js missing"; exit 1
fi

# standalone 需要 static / public 一并挂载
mkdir -p .next/standalone/.next
rm -rf .next/standalone/.next/static
cp -a .next/static .next/standalone/.next/static
if [ -d public ]; then
  rm -rf .next/standalone/public
  cp -a public .next/standalone/public
fi

echo "[INFO] upload standalone + compose..."
TEMP_TAR=$(mktemp /tmp/novel-fe-standalone.XXXXXX.tar.gz 2>/dev/null || echo /tmp/novel-fe-standalone.$$.tar.gz)
tar -czf "$TEMP_TAR" -C .next/standalone .
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$TEMP_TAR" "$SSH_HOST:/tmp/novel-fe-standalone.tar.gz"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
  "$PROJECT_DIR/deploy/docker-compose.prod.yml" \
  "$SSH_HOST:/tmp/docker-compose.prod.yml"

ssh_cmd "set -e
  mkdir -p ${REMOTE_PROJECT_DIR}/frontend/.next/standalone ${REMOTE_PROJECT_DIR}/deploy
  # 停掉可能把机器打满的旧前端（在容器内 npm install 的那种）
  docker rm -f novel-generator-frontend 2>/dev/null || true
  docker volume rm novel-generator-frontend-node-modules 2>/dev/null || true
  rm -rf ${REMOTE_PROJECT_DIR}/frontend/.next/standalone/*
  tar -xzf /tmp/novel-fe-standalone.tar.gz -C ${REMOTE_PROJECT_DIR}/frontend/.next/standalone
  # compose 挂载路径：standalone + static + public
  mkdir -p ${REMOTE_PROJECT_DIR}/frontend/.next/static ${REMOTE_PROJECT_DIR}/frontend/public
  rm -rf ${REMOTE_PROJECT_DIR}/frontend/.next/static/*
  cp -a ${REMOTE_PROJECT_DIR}/frontend/.next/standalone/.next/static/. ${REMOTE_PROJECT_DIR}/frontend/.next/static/ 2>/dev/null || true
  if [ -d ${REMOTE_PROJECT_DIR}/frontend/.next/standalone/public ]; then
    rm -rf ${REMOTE_PROJECT_DIR}/frontend/public/*
    cp -a ${REMOTE_PROJECT_DIR}/frontend/.next/standalone/public/. ${REMOTE_PROJECT_DIR}/frontend/public/ 2>/dev/null || true
  fi
  mv /tmp/docker-compose.prod.yml ${REMOTE_PROJECT_DIR}/deploy/
  rm -f /tmp/novel-fe-standalone.tar.gz
"

rm -f "$TEMP_TAR"

if ! ssh_cmd "docker images node:20-bookworm-slim --format '{{.Repository}}:{{.Tag}}'" | grep -q 'node:20-bookworm-slim'; then
  echo "[INFO] pulling node:20-bookworm-slim..."
  ssh_cmd "docker pull node:20-bookworm-slim"
fi

echo "[INFO] start frontend..."
ssh_cmd "cd ${REMOTE_PROJECT_DIR} && docker compose -f ${COMPOSE_FILE} up -d frontend"
sleep 5
code=$(ssh_cmd "curl -sS -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:9002/zh 2>/dev/null" || echo 000)
ssh_cmd "docker ps --filter name=novel-generator-frontend --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
ssh_cmd "docker logs novel-generator-frontend --tail 20 2>&1" || true
echo -e "${GREEN}[DONE]${NC} frontend HTTP=$code  http://117.72.100.59:9002"
