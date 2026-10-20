# 部署（对齐 disco-elysium 线上脚本）

参考：

- 后端：`disco-elysium-python-flask/scripts/build_prod.sh`  
  依赖打进镜像（清华 PyPI）+ **代码挂载**；只有 `Dockerfile` / `requirements` 变了才 `--build`，日常同步后 `restart`。
- 前端：`disco-elysium-blog-front/scripts/deploy_prod.sh`  
  **本机构建**，再上传产物；容器用现成运行时。

## 用法

```powershell
cd E:\gs-workspace\AI_NovelGenerator

# 全量
.\deploy\deploy.ps1

# 只后端 / 只前端
.\deploy\deploy-backend.ps1
.\deploy\deploy-frontend.ps1
```

或 Git Bash：

```bash
bash deploy/deploy_backend.sh
bash deploy/deploy_frontend.sh
```

远程目录：`/data/ai-novel-generator`（与 blog 的 `/data/...` 一致）

| 地址 | URL |
|------|-----|
| 前端 | http://117.72.100.59:9002 |
| 后端 | http://117.72.100.59:9001/docs |

## 为什么本地不慢

本机已有 `.venv` / `node_modules`。服务器上 **首次** 或改依赖才会 `docker build`（且 Dockerfile 里用清华 / npmmirror）。日常改业务代码只传文件 + restart，不会再下一堆包。
