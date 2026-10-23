const fs = require("node:fs");
const path = require("node:path");
const cheerio = require("cheerio");
const { ROOT, write } = require("./common");
const manifest = JSON.parse(
  fs.readFileSync(path.join(ROOT, "src", "manifest.json"), "utf8"),
);
const issues = [];
for (const p of manifest) {
  const file = path.join(ROOT, "dist", p.path);
  if (!fs.existsSync(file)) {
    issues.push({ page: p.url, type: "missing-page", path: p.path });
    continue;
  }
  const $ = cheerio.load(fs.readFileSync(file, "utf8"));
  for (const [sel, attr] of [
    ["a[href]", "href"],
    ["img[src]", "src"],
    ["script[src]", "src"],
    ['link[rel="stylesheet"][href]', "href"],
  ])
    $(sel).each((_, el) => {
      const v = $(el).attr(attr);
      if (!v || !v.startsWith("/") || v.startsWith("//")) return;
      const raw = v.split(/[?#]/)[0];
      if (!raw) return;

      let decoded;
      try {
        decoded = decodeURIComponent(raw);
      } catch {
        issues.push({
          page: p.url,
          type: "invalid-reference",
          value: v,
        });
        return;
      }

      if (
        decoded.includes("\0") ||
        decoded.includes("\\") ||
        decoded.split("/").includes("..") ||
        /%2f|%5c/i.test(raw)
      ) {
        issues.push({
          page: p.url,
          type: "unsafe-reference",
          value: v,
        });
        return;
      }

      const base = path.resolve(ROOT, "dist");
      const encoded = raw.replace(/%[0-9a-f]{2}/gi, (s) => s.toLowerCase());

      const candidates = [encoded, decoded].map((name) =>
        path.resolve(base, "." + name),
      );

      const exists = candidates.some((candidate) => {
        if (candidate !== base && !candidate.startsWith(base + path.sep)) {
          return false;
        }

        return [candidate, path.join(candidate, "index.html")].some(
          (target) => {
            try {
              const real = fs.realpathSync(target);
              return (
                (real === base || real.startsWith(base + path.sep)) &&
                fs.statSync(real).isFile()
              );
            } catch {
              return false;
            }
          },
        );
      });

      if (!exists) {
        issues.push({
          page: p.url,
          type: "missing-reference",
          value: v,
        });
      }
    });
  if (/\/wp-json\/|admin-ajax\.php|wp-login\.php/i.test($.html()))
    issues.push({ page: p.url, type: "wordpress-dependency-review" });
}
write(
  path.join(ROOT, "logs", "validation.json"),
  JSON.stringify({ pages: manifest.length, issues }, null, 2),
);
console.log(
  `Validated ${manifest.length} pages; ${issues.length} findings. See logs/validation.json`,
);
if (issues.length) process.exitCode = 1;
