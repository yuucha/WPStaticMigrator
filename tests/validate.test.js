const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

test("validate reports categorized HTML findings and source files", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "wpsm-validate-"));
  fs.mkdirSync(path.join(root, "src"), { recursive: true });
  fs.mkdirSync(path.join(root, "dist"), { recursive: true });
  fs.mkdirSync(path.join(root, "logs"), { recursive: true });
  fs.writeFileSync(path.join(root, "config.json"), JSON.stringify({
    origin: "https://example.test", includeHosts: ["example.test"], startPaths: ["/"],
  }));
  fs.writeFileSync(path.join(root, "src", "manifest.json"), JSON.stringify([
    { url: "https://example.test/", path: "index.html" },
  ]));
  fs.writeFileSync(path.join(root, "dist", "index.html"), '<a href="/missing/">x</a><img src="/missing.png"><script src="/missing.js"></script>');
  fs.writeFileSync(path.join(root, "logs", "shared-variants.json"), JSON.stringify([
    { url: "https://example.test/", component: "header" },
  ]));

  const result = spawnSync(process.execPath, [path.join(__dirname, "../bin/wp-static-migrator.js"), "validate", "--output", root]);
  assert.equal(result.status, 1);
  const report = JSON.parse(fs.readFileSync(path.join(root, "logs", "validation.json"), "utf8"));
  assert.equal(report.issueCount, 4);
  assert.deepEqual(Object.fromEntries(report.summary.map(({ category, count }) => [category, count])), {
    image: 1, layout: 1, link: 1, script: 1,
  });
  assert.ok(report.issues.every((issue) => issue.file === "index.html"));
  fs.rmSync(root, { recursive: true, force: true });
});
