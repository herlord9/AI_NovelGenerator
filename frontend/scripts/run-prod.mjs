import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const envFile = join(root, "env.prod");

function loadEnvFile(path) {
  const text = readFileSync(path, "utf8");
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx <= 0) continue;
    const key = trimmed.slice(0, idx).trim();
    const value = trimmed.slice(idx + 1).trim();
    process.env[key] = value;
  }
}

loadEnvFile(envFile);

const apiBase = process.env.NEXT_PUBLIC_API_BASE || "http://117.72.100.59:9001";
process.env.NEXT_PUBLIC_API_BASE = apiBase;
process.env.NODE_ENV = "production";

console.log(`[prod] NEXT_PUBLIC_API_BASE=${apiBase}`);
console.log("[prod] building…");

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: root,
      env: process.env,
      stdio: "inherit",
      shell: process.platform === "win32",
    });
    child.on("exit", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} ${args.join(" ")} exited with ${code}`));
    });
  });
}

await run("npx", ["next", "build"]);
console.log("[prod] starting on 0.0.0.0:9002 …");
await run("npx", ["next", "start", "--hostname", "0.0.0.0", "--port", "9002"]);
