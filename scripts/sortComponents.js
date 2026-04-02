#!/usr/bin/env node
// =============================================================================
// sortComponents.js — Pre-package component sorter
//
// Moves unpackaged metadata types from force-app/ → force-app-unpackaged/ and
// cleans up force-app/ object XML (strips Flexipage actionOverrides).
//
// Run automatically by createPackageVersion.sh before sf package version create.
// Safe to run repeatedly — overwrites force-app-unpackaged with whatever was
// just retrieved from the org (force-app is always the freshly-retrieved source).
// =============================================================================

const fs   = require("fs");
const path = require("path");

const ROOT      = path.join(__dirname, "..");
const PKG_SRC   = path.join(ROOT, "force-app", "main", "default");
const UNPKG_SRC = path.join(ROOT, "force-app-unpackaged");

let moved = 0, cleaned = 0;

// Entire directories that must never be inside the managed package
const UNPACKAGED_DIRS = ["flexipages", "reports", "namedCredentials", "permissionsets"];

// Custom-object layouts only — CMDT layouts (e.g. *__mdt-*) stay in the package
function isCustomObjectLayout(filename) {
  return filename.endsWith(".layout-meta.xml") && /^[A-Za-z]\w*__c-/.test(filename);
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function moveFile(src, dst) {
  ensureDir(path.dirname(dst));
  const existed = fs.existsSync(dst);
  fs.copyFileSync(src, dst);
  fs.unlinkSync(src);
  const tag = existed ? "↺ Updated" : "✔ Moved";
  console.log(`  ${tag}: ${path.relative(ROOT, src)} → ${path.relative(ROOT, dst)}`);
  moved++;
}

function moveDirContents(srcDir, dstDir) {
  if (!fs.existsSync(srcDir)) return;
  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const srcPath = path.join(srcDir, entry.name);
    const dstPath = path.join(dstDir, entry.name);
    if (entry.isDirectory()) {
      moveDirContents(srcPath, dstPath);
    } else {
      moveFile(srcPath, dstPath);
    }
  }
  // Remove empty source dir
  try { fs.rmdirSync(srcDir); } catch {}
}

console.log("\n══════════════════════════════════════════");
console.log(" Sort Components: force-app → force-app-unpackaged");
console.log("══════════════════════════════════════════");

// ── Move whole unpackaged directories ────────────────────────────────────────
for (const dir of UNPACKAGED_DIRS) {
  const srcDir = path.join(PKG_SRC, dir);
  if (fs.existsSync(srcDir) && fs.readdirSync(srcDir).length > 0) {
    console.log(`\n  Moving ${dir}/...`);
    moveDirContents(srcDir, path.join(UNPKG_SRC, dir));
  }
}

// ── Move custom-object layouts ────────────────────────────────────────────────
const pkgLayouts   = path.join(PKG_SRC, "layouts");
const unpkgLayouts = path.join(UNPKG_SRC, "layouts");
if (fs.existsSync(pkgLayouts)) {
  let anyLayout = false;
  for (const filename of fs.readdirSync(pkgLayouts)) {
    if (isCustomObjectLayout(filename)) {
      if (!anyLayout) { console.log("\n  Moving custom-object layouts..."); anyLayout = true; }
      moveFile(path.join(pkgLayouts, filename), path.join(unpkgLayouts, filename));
    } else {
      console.log(`  — Kept in package: layouts/${filename}`);
    }
  }
}

// ── Clean FlexiPages: strip visibilityRules referencing non-package fields ────
// Fields that exist only in the developer org but not in the managed package
// cause deploy failures when the FlexiPage is deployed to subscriber orgs.
const NON_PACKAGE_FIELDS = ["Count_of_Child_Items__c"];

const unpkgFlexipagesDir = path.join(UNPKG_SRC, "flexipages");
if (fs.existsSync(unpkgFlexipagesDir)) {
  for (const filename of fs.readdirSync(unpkgFlexipagesDir)) {
    if (!filename.endsWith(".flexipage-meta.xml")) continue;
    const fpFile = path.join(unpkgFlexipagesDir, filename);
    let content  = fs.readFileSync(fpFile, "utf8");
    const before = content;
    for (const field of NON_PACKAGE_FIELDS) {
      content = content.replace(
        /\s*<visibilityRule>[\s\S]*?<\/visibilityRule>/g,
        (match) => match.includes(field) ? "" : match
      );
    }
    if (content !== before) {
      fs.writeFileSync(fpFile, content);
      const removed = NON_PACKAGE_FIELDS.filter(f => before.includes(f) && !content.includes(f));
      console.log(`  ✔ Cleaned FlexiPage ${filename}: removed visibilityRules for [${removed.join(", ")}]`);
      cleaned++;
    }
  }
}

// ── Clean object XML: strip <type>Flexipage</type> actionOverrides ────────────
const objectsDir = path.join(PKG_SRC, "objects");
if (fs.existsSync(objectsDir)) {
  console.log("\n  Cleaning object XML (removing Flexipage actionOverrides)...");
  for (const objName of fs.readdirSync(objectsDir)) {
    const objFile = path.join(objectsDir, objName, `${objName}.object-meta.xml`);
    if (!fs.existsSync(objFile)) continue;
    let content  = fs.readFileSync(objFile, "utf8");
    const before = content;
    // Remove any <actionOverrides> block that contains <type>Flexipage</type>
    content = content.replace(
      /[ \t]*<actionOverrides>(?:(?!<actionOverrides>)[\s\S])*?<type>Flexipage<\/type>[\s\S]*?<\/actionOverrides>\r?\n?/g,
      ""
    );
    if (content !== before) {
      fs.writeFileSync(objFile, content);
      console.log(`  ✔ Cleaned: objects/${objName}/${objName}.object-meta.xml`);
      cleaned++;
    }
  }
}

console.log("\n══════════════════════════════════════════");
console.log(` ✅  Done: ${moved} file(s) moved, ${cleaned} object file(s) cleaned`);
console.log("══════════════════════════════════════════\n");
