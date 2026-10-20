import type { NextConfig } from "next";
import path from "node:path";
import { fileURLToPath } from "node:url";
import createNextIntlPlugin from "next-intl/plugin";

const withNextIntl = createNextIntlPlugin("./src/i18n/request.ts");
const isProduction = process.env.NODE_ENV === "production";
const frontendRoot = path.dirname(fileURLToPath(import.meta.url));

const nextConfig: NextConfig = {
  // Docker 生产镜像使用 standalone 输出，减小运行体积。
  ...(process.env.DOCKER_BUILD === "1" ? { output: "standalone" as const } : {}),
  // 避免上层 workspace 的 package-lock 把根目录误判到 E:\gs-workspace
  outputFileTracingRoot: frontendRoot,
  turbopack: {
    root: frontendRoot,
  },
  // 独立验收可使用其他构建目录，不改写正在运行的本机服务产物。
  distDir: process.env.NEXT_DIST_DIR || ".next",
  reactCompiler: true,
  typescript: {
    // 生产构建不应读取可能由上次 dev 强制中断而残留的开发路由声明。
    tsconfigPath: isProduction ? "tsconfig.build.json" : "tsconfig.json",
  },
  env: {
    NEXT_PUBLIC_API_BASE:
      process.env.NEXT_PUBLIC_API_BASE || "http://127.0.0.1:9001",
  },
};

export default withNextIntl(nextConfig);
