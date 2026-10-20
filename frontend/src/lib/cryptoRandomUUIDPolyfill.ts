/**
 * HTTP 非 localhost 不是 secure context，部分浏览器没有 crypto.randomUUID。
 * 在客户端入口尽早补上，避免业务代码直接调用时报错。
 */
export function ensureCryptoRandomUUID(): void {
  if (typeof globalThis === "undefined") {
    return;
  }

  const cryptoObj = globalThis.crypto;
  if (!cryptoObj || typeof cryptoObj.randomUUID === "function") {
    return;
  }

  const polyfill = function randomUUID(): `${string}-${string}-${string}-${string}-${string}` {
    if (typeof cryptoObj.getRandomValues === "function") {
      const bytes = new Uint8Array(16);
      cryptoObj.getRandomValues(bytes);
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
      return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}` as `${string}-${string}-${string}-${string}-${string}`;
    }

    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (ch) => {
      const r = (Math.random() * 16) | 0;
      const v = ch === "x" ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    }) as `${string}-${string}-${string}-${string}-${string}`;
  };

  try {
    Object.defineProperty(cryptoObj, "randomUUID", {
      value: polyfill,
      configurable: true,
      writable: true,
    });
  } catch {
    (cryptoObj as Crypto).randomUUID = polyfill;
  }
}

ensureCryptoRandomUUID();
