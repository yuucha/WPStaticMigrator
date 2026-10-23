"use strict";
const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

const types = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".xml": "application/xml; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".pdf": "application/pdf",
  ".mp4": "video/mp4",
};
function createServer(root) {
  const base = fs.realpathSync(root);
  return http.createServer((req, res) => {
    if (!["GET", "HEAD"].includes(req.method)) {
      res.writeHead(405, { Allow: "GET, HEAD" });
      res.end();
      return;
    }
    let pathname;
    let decoded;

    try {
      pathname = new URL(req.url, "http://localhost").pathname;
      decoded = decodeURIComponent(pathname);
    } catch {
      res.writeHead(400);
      res.end("Bad request");
      return;
    }

    // URLをデコードした状態でも安全性を検証
    if (
      decoded.includes("\0") ||
      decoded.includes("\\") ||
      decoded.split("/").includes("..") ||
      /%2f|%5c/i.test(pathname)
    ) {
      res.writeHead(403);
      res.end("Forbidden");
      return;
    }

    // Buildの出力形式に合わせる
    const encoded = pathname.replace(/%[0-9a-f]{2}/gi, (s) => s.toLowerCase());

    // エンコード形式を優先し、デコード形式も許容する
    const candidates = [
      path.resolve(base, "." + encoded),
      path.resolve(base, "." + decoded),
    ];

    let file;

    for (const candidate of candidates) {
      if (candidate !== base && !candidate.startsWith(base + path.sep)) {
        continue;
      }

      try {
        const stat = fs.statSync(candidate);
        const target = stat.isDirectory()
          ? path.join(candidate, "index.html")
          : candidate;

        const real = fs.realpathSync(target);

        if (real !== base && !real.startsWith(base + path.sep)) {
          continue;
        }

        if (fs.statSync(real).isFile()) {
          file = real;
          break;
        }
      } catch {
        // 次の候補を確認
      }
    }

    if (!file) {
      res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("404 Not Found");
      return;
    }
    try {
      if (fs.statSync(file).isDirectory()) file = path.join(file, "index.html");
      const real = fs.realpathSync(file);
      if (real !== base && !real.startsWith(base + path.sep)) {
        res.writeHead(403);
        res.end("Forbidden");
        return;
      }
      if (!fs.statSync(real).isFile()) throw Error("Not a file");
      res.writeHead(200, {
        "Content-Type":
          types[path.extname(real).toLowerCase()] || "application/octet-stream",
        "X-Content-Type-Options": "nosniff",
      });
      if (req.method === "HEAD") {
        res.end();
        return;
      }
      fs.createReadStream(real).pipe(res);
    } catch {
      res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      res.end("404 Not Found");
    }
  });
}
if (require.main === module) {
  const dir = process.env.WPSM_WORKDIR;
  const port = Number(process.env.WPSM_PORT || 8080);
  const root = path.join(dir, "dist");
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
    console.error("Missing dist/. Run build first.");
    process.exit(2);
  }
  const server = createServer(root);
  server.on("error", (e) => {
    console.error("Preview server error:", e.message);
    process.exitCode = 1;
  });
  server.listen(port, "127.0.0.1", () =>
    console.log(`Preview: http://127.0.0.1:${port}/ (Ctrl+C to stop)`),
  );
}
module.exports = { createServer };
