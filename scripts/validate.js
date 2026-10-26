const fs = require("node:fs");
const path = require("node:path");
const cheerio = require("cheerio");
const { ROOT, write } = require("./common");
const manifest = JSON.parse(
  fs.readFileSync(path.join(ROOT, "src", "manifest.json"), "utf8"),
);
const issues = [];
const categoryLabels = {
  link: "リンク切れ",
  image: "画像",
  stylesheet: "スタイルシート",
  script: "スクリプト",
  page: "HTMLページ",
  layout: "レイアウト",
  wordpress: "WordPress依存",
  reference: "不正な参照",
};
function addIssue(issue) {
  issues.push({ ...issue, categoryLabel: categoryLabels[issue.category] });
}
for (const p of manifest) {
  const file = path.join(ROOT, "dist", p.path);
  if (!fs.existsSync(file)) {
    addIssue({ page: p.url, file: p.path, category: "page", type: "missing-page", path: p.path });
    continue;
  }
  const $ = cheerio.load(fs.readFileSync(file, "utf8"));
  for (const [sel, attr, category] of [
    ["a[href]", "href", "link"],
    ["img[src]", "src", "image"],
    ["script[src]", "src", "script"],
    ['link[rel="stylesheet"][href]', "href", "stylesheet"],
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
        addIssue({
          page: p.url,
          file: p.path,
          category: "reference",
          type: "invalid-reference",
          value: v,
          element: sel,
        });
        return;
      }

      if (
        decoded.includes("\0") ||
        decoded.includes("\\") ||
        decoded.split("/").includes("..") ||
        /%2f|%5c/i.test(raw)
      ) {
        addIssue({
          page: p.url,
          file: p.path,
          category: "reference",
          type: "unsafe-reference",
          value: v,
          element: sel,
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
        addIssue({
          page: p.url,
          file: p.path,
          category,
          type: "missing-reference",
          value: v,
          element: sel,
        });
      }
    });
  if (/\/wp-json\/|admin-ajax\.php|wp-login\.php/i.test($.html()))
    addIssue({ page: p.url, file: p.path, category: "wordpress", type: "wordpress-dependency-review" });
}
const manifestPaths = new Map(manifest.map((page) => [page.url, page.path]));
const variantsPath = path.join(ROOT, "logs", "shared-variants.json");
if (fs.existsSync(variantsPath)) {
  const variants = JSON.parse(fs.readFileSync(variantsPath, "utf8"));
  for (const variant of variants) {
    addIssue({
      page: variant.url,
      file: manifestPaths.get(variant.url) || "",
      category: "layout",
      type: "shared-component-variant",
      value: variant.component,
    });
  }
}
const summary = Object.entries(
  issues.reduce((counts, issue) => {
    counts[issue.category] = (counts[issue.category] || 0) + 1;
    return counts;
  }, {}),
)
  .map(([category, count]) => ({ category, label: categoryLabels[category], count }))
  .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label, "ja"));
write(
  path.join(ROOT, "logs", "validation.json"),
  JSON.stringify({ pages: manifest.length, issueCount: issues.length, summary, issues }, null, 2),
);
console.log(
  `Validated ${manifest.length} pages; ${issues.length} findings. See logs/validation.json`,
);
if (issues.length) process.exitCode = 1;
