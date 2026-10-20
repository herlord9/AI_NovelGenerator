@echo off
chcp 65001 >nul
setlocal EnableExtensions

rem 进入项目绝对路径
cd /d "%~dp0"
set "PROJECT_ROOT=%CD%"
echo [INFO] 项目目录: %PROJECT_ROOT%

set "NOVEL_GENERATOR_PROFILE=prod"
set "NOVEL_GENERATOR_BACKEND_PORT=9001"
set "NOVEL_GENERATOR_FRONTEND_PORT=9002"
set "NOVEL_GENERATOR_MONGODB_URL=mongodb://127.0.0.1:27017/?replicaSet=rs0&directConnection=true"
set "NOVEL_GENERATOR_MONGO_DATABASE_NAME=novel_generator"
set "NEXT_PUBLIC_API_BASE=http://127.0.0.1:9001"
set "VENV_DIR=%PROJECT_ROOT%\.venv"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"
set "NPM_CMD=npm.cmd"

where python >nul 2>&1
if errorlevel 1 (
    where py >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] 未找到 Python，请先安装 Python 3 并加入 PATH。
        pause
        exit /b 1
    )
    set "SYS_PY=py -3"
) else (
    set "SYS_PY=python"
)

where %NPM_CMD% >nul 2>&1
if errorlevel 1 (
    echo [ERROR] 未找到 npm，请先安装 Node.js 并确保 npm 在 PATH 中。
    pause
    exit /b 1
)

if not exist "%VENV_PY%" (
    echo [INFO] 未检测到虚拟环境，正在创建: %VENV_DIR%
    %SYS_PY% -m venv "%VENV_DIR%"
    if errorlevel 1 (
        echo [ERROR] 创建虚拟环境失败。
        pause
        exit /b 1
    )
) else (
    echo [INFO] 已找到虚拟环境: %VENV_DIR%
)

echo [INFO] 使用虚拟环境安装 Python 依赖...
"%VENV_PY%" -m pip install --upgrade pip
if errorlevel 1 (
    echo [ERROR] 升级 pip 失败。
    pause
    exit /b 1
)
"%VENV_PY%" -m pip install -r "%PROJECT_ROOT%\requirements.txt"
if errorlevel 1 (
    echo [ERROR] Python 依赖安装失败。
    pause
    exit /b 1
)

echo [INFO] 进入前端目录并安装/构建...
cd /d "%PROJECT_ROOT%\frontend"
if not exist "node_modules\" (
    echo [INFO] 未检测到 node_modules，开始安装前端依赖...
    if exist "package-lock.json" (
        call %NPM_CMD% ci
    ) else (
        call %NPM_CMD% install
    )
) else (
    echo [INFO] 已找到 node_modules，检查并同步依赖...
    if exist "package-lock.json" (
        call %NPM_CMD% ci
    ) else (
        call %NPM_CMD% install
    )
)
if errorlevel 1 (
    echo [ERROR] npm 依赖安装失败。
    pause
    exit /b 1
)

echo [INFO] 生产构建前端 NEXT_PUBLIC_API_BASE=%NEXT_PUBLIC_API_BASE%
call %NPM_CMD% run build
if errorlevel 1 (
    echo [ERROR] npm run build 失败。
    pause
    exit /b 1
)

cd /d "%PROJECT_ROOT%"
echo [INFO] 启动后端: http://127.0.0.1:%NOVEL_GENERATOR_BACKEND_PORT%
start "AI_NovelGenerator Backend" cmd /k "cd /d "%PROJECT_ROOT%" && set NOVEL_GENERATOR_BACKEND_PORT=%NOVEL_GENERATOR_BACKEND_PORT%&& set NOVEL_GENERATOR_FRONTEND_PORT=%NOVEL_GENERATOR_FRONTEND_PORT%&& set NOVEL_GENERATOR_MONGODB_URL=%NOVEL_GENERATOR_MONGODB_URL%&& set NOVEL_GENERATOR_MONGO_DATABASE_NAME=%NOVEL_GENERATOR_MONGO_DATABASE_NAME%&& "%VENV_PY%" main.py"

echo [INFO] 启动前端(本地 API): http://127.0.0.1:%NOVEL_GENERATOR_FRONTEND_PORT%
start "AI_NovelGenerator Frontend" cmd /k "cd /d "%PROJECT_ROOT%\frontend" && set NEXT_PUBLIC_API_BASE=%NEXT_PUBLIC_API_BASE%&& %NPM_CMD% run start"

echo [INFO] 前后端已在新窗口启动，关闭对应窗口即可停止服务。
echo        前端: http://127.0.0.1:%NOVEL_GENERATOR_FRONTEND_PORT%
echo        后端: http://127.0.0.1:%NOVEL_GENERATOR_BACKEND_PORT%/docs
echo        公网生产前端请另开: cd frontend ^&^& npm run prod
endlocal
exit /b 0
