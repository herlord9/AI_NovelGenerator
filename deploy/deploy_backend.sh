#!/usr/bin/env bash
# 对齐 disco-elysium-python-flask/scripts/build_prod.sh
# 日常：同步代码 + restart；仅 Dockerfile / requirements-prod.txt 变化才 --build
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519_root_117_72_100_59}"
SSH_HOST="${SSH_HOST:-root@117.72.100.59}"
REMOTE_PROJECT_DIR="${REMOTE_PROJECT_DIR:-/data/ai-novel-generator}"
IMAGE_NAME="novel-generator-backend"
IMAGE_TAG="prod"
COMPOSE_FILE="deploy/docker-compose.prod.yml"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

ssh_cmd() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_HOST" "$@"
}

echo -e "${CYAN}AI NovelGenerator - Backend Deploy${NC}"
echo "Server: $SSH_HOST  Dir: $REMOTE_PROJECT_DIR"
echo ""

if [ ! -f "$SSH_KEY" ]; then
  echo -e "${RED}[ERROR]${NC} SSH key missing: $SSH_KEY"; exit 1
fi
ssh_cmd "echo SSH_OK" >/dev/null
ssh_cmd "docker info >/dev/null"

FIRST_DEPLOY=false
if ! ssh_cmd "[ -d ${REMOTE_PROJECT_DIR} ]"; then
  ssh_cmd "mkdir -p ${REMOTE_PROJECT_DIR}"
  FIRST_DEPLOY=true
fi

NEED_REBUILD=false
FLASK_IMAGE_EXISTS=$(ssh_cmd "docker images ${IMAGE_NAME}:${IMAGE_TAG} --format '{{.Repository}}:{{.Tag}}' 2>/dev/null" | grep -qx "${IMAGE_NAME}:${IMAGE_TAG}" && echo yes || echo no)

if [ "$FIRST_DEPLOY" = true ] || [ "$FLASK_IMAGE_EXISTS" = "no" ]; then
  echo "[INFO] first deploy or image missing -> rebuild"
  NEED_REBUILD=true
else
  LOCAL_DF=$(md5sum deploy/Dockerfile.backend 2>/dev/null | awk '{print $1}')
  LOCAL_RQ=$(md5sum requirements-prod.txt 2>/dev/null | awk '{print $1}')
  REMOTE_DF=$(ssh_cmd "md5sum ${REMOTE_PROJECT_DIR}/deploy/Dockerfile.backend 2>/dev/null | cut -d' ' -f1" || true)
  REMOTE_RQ=$(ssh_cmd "md5sum ${REMOTE_PROJECT_DIR}/requirements-prod.txt 2>/dev/null | cut -d' ' -f1" || true)
  if [ "$LOCAL_DF" != "$REMOTE_DF" ] || [ "$LOCAL_RQ" != "$REMOTE_RQ" ]; then
    echo -e "${YELLOW}[INFO]${NC} Dockerfile/requirements changed -> rebuild"
    NEED_REBUILD=true
  else
    echo -e "${GREEN}[INFO]${NC} deps unchanged -> code sync + restart only"
  fi
fi

echo "[INFO] syncing source..."
TEMP_TAR=$(mktemp /tmp/novel-be.XXXXXX.tar.gz 2>/dev/null || echo /tmp/novel-be.$$.tar.gz)
tar -czf "$TEMP_TAR" \
  --exclude='.git' --exclude='.venv' --exclude='**/__pycache__' \
  --exclude='frontend/node_modules' --exclude='frontend/.next' \
  --exclude='user_data' --exclude='.cursor' \
  -C "$PROJECT_DIR" .
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$TEMP_TAR" "$SSH_HOST:/tmp/novel-be.tar.gz"
ssh_cmd "mkdir -p ${REMOTE_PROJECT_DIR} && tar -xzf /tmp/novel-be.tar.gz -C ${REMOTE_PROJECT_DIR} && sed -i 's/\r$//' ${REMOTE_PROJECT_DIR}/deploy/*.sh 2>/dev/null; chmod +x ${REMOTE_PROJECT_DIR}/deploy/*.sh; rm -f /tmp/novel-be.tar.gz"
rm -f "$TEMP_TAR"

# stop old mongo occupying 27017
ssh_cmd "if docker ps -a --format '{{.Names}}' | grep -qx short-drama-mongo; then docker stop short-drama-mongo; docker update --restart=no short-drama-mongo; fi"

# ensure mongodb + replica set
ssh_cmd "cd ${REMOTE_PROJECT_DIR} && docker compose -f ${COMPOSE_FILE} up -d mongodb"
ssh_cmd "bash -s" <<'REMOTE_MONGO'
for i in $(seq 1 30); do
  docker exec novel-generator-mongodb mongosh --quiet --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q 1 && break
  sleep 2
done
docker exec novel-generator-mongodb mongosh --quiet --eval '
try { print("rs_ok="+rs.status().ok); }
catch(e){ printjson(rs.initiate({_id:"rs0",members:[{_id:0,host:"mongodb:27017"}]})); }
' || true
for i in $(seq 1 30); do
  docker exec novel-generator-mongodb mongosh --quiet --eval 'quit(db.hello().isWritablePrimary?0:1)' 2>/dev/null && break
  sleep 2
done
REMOTE_MONGO

if [ "$NEED_REBUILD" = true ]; then
  echo "[INFO] building backend image (tuna mirror inside Dockerfile)..."
  ssh_cmd "cd ${REMOTE_PROJECT_DIR} && docker compose -f ${COMPOSE_FILE} build backend && docker compose -f ${COMPOSE_FILE} up -d backend"
else
  status=$(ssh_cmd "docker inspect novel-generator-backend --format '{{.State.Status}}' 2>/dev/null" || echo missing)
  if [ "$status" = "missing" ]; then
    ssh_cmd "cd ${REMOTE_PROJECT_DIR} && docker compose -f ${COMPOSE_FILE} up -d backend"
  else
    echo "[INFO] restart backend to load mounted code..."
    ssh_cmd "docker restart novel-generator-backend"
  fi
fi

sleep 3
ssh_cmd "cd ${REMOTE_PROJECT_DIR} && docker compose -f ${COMPOSE_FILE} ps"
echo -e "${GREEN}[DONE]${NC} http://117.72.100.59:9001/docs"
