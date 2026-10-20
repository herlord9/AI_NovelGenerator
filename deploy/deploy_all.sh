#!/usr/bin/env bash
# 全量：后端 + 前端（各自按依赖是否变化决定是否 rebuild）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/deploy_backend.sh"
bash "$SCRIPT_DIR/deploy_frontend.sh"
