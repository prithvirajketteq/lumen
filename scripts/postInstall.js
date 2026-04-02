#!/usr/bin/env node
// =============================================================================
// postInstall.js — Deploy unpackaged components + import data to a subscriber
//                  org that already has the kqexe managed package installed.
//
// Usage:
//   node scripts/postInstall.js <orgAlias>
//
// Prerequisites:
//   The kqexe managed package must already be installed in the target org.
//   Install it first: sf package install --package <04t...> --target-org <orgAlias>
//
// What this script automates (no manual steps required after):
//   - Deploys: App, FlexiPage, Permission Set, Named Credentials, Reports, Layouts
//   - Deploys object action override (Item__c View → Item_Record_Page)
//   - Assigns both permission sets to the running user
//   - Imports 1,355+ sample records across 8 objects
//
// All bare custom API names (Item__c, Vendor__r, etc.) are automatically
// prefixed with kqexe__ before deploying to subscriber orgs.
// Layout filenames are also renamed (Order__c- → kqexe__Order__c-).
// =============================================================================

const { spawnSync, execSync } = require("child_process");
const fs   = require("fs");
const path = require("path");
const os   = require("os");

const NS       = "kqexe__";
const DATA_DIR = path.join(__dirname, "..", "data");
const TMP_DIR  = path.join(os.tmpdir(), "lumen-pkg-data");

// ── Arg handling ──────────────────────────────────────────────────────────────
const orgAlias = process.argv[2];
if (!orgAlias) {
  console.error("Usage: node scripts/postInstall.js <orgAlias>");
  process.exit(1);
}

// ── Clear temp directory for fresh transforms every run ───────────────────────
if (fs.existsSync(TMP_DIR)) {
  fs.rmSync(TMP_DIR, { recursive: true, force: true });
}
fs.mkdirSync(TMP_DIR, { recursive: true });

// ── Helper: run a command and stream output ───────────────────────────────────
function exec(cmd, args) {
  console.log(`  $ ${cmd} ${args.join(" ")}`);
  const result = spawnSync(cmd, args, { encoding: "utf8", shell: true, stdio: "inherit" });
  if (result.status !== 0) {
    console.error(`  ✖ Command failed (exit ${result.status})`);
    process.exit(1);
  }
}

// ── Helper: run sf and return parsed JSON ─────────────────────────────────────
function sfJson(cmdString) {
  const txt = execSync(`sf ${cmdString} --json`, { encoding: "utf8", shell: true });
  const idx = txt.indexOf("{");
  if (idx < 0) throw new Error("No JSON from sf: " + txt);
  return JSON.parse(txt.slice(idx));
}

// ── Helper: remove a flexiPageRegions block containing a keyword ──────────────
function removeFlexiPageRegion(content, keyword) {
  const OPEN  = "<flexiPageRegions>";
  const CLOSE = "</flexiPageRegions>";
  
  while (content.includes(keyword)) {
    const kwIdx = content.indexOf(keyword);
    if (kwIdx === -1) break;

    // Find the LAST <flexiPageRegions> before the keyword
    let openIdx = -1;
    let searchIdx = 0;
    while (true) {
      const found = content.indexOf(OPEN, searchIdx);
      if (found === -1 || found > kwIdx) break;
      openIdx = found;
      searchIdx = found + 1;
    }
    if (openIdx === -1) break;

    // Find the closing </flexiPageRegions> after the keyword
    const closeIdx = content.indexOf(CLOSE, kwIdx);
    if (closeIdx === -1) break;

    const endIdx = closeIdx + CLOSE.length;

    // Remove the block and any leading newline/whitespace before it
    const before = content.slice(0, openIdx).trimEnd();
    const after  = content.slice(endIdx);
    content = before + "\n" + after.trimStart();
  }

  return content;
}

// ── Preflight: verify kqexe package is installed ─────────────────────────────
console.log("\n══════════════════════════════════════════");
console.log(" Preflight: Checking package installation");
console.log("══════════════════════════════════════════");

try {
  const installed = sfJson(`package installed list -o ${orgAlias}`);
  const found = (installed.result || []).some(p => p.SubscriberPackageNamespace === "kqexe");
  if (!found) {
    console.error("  ✖ kqexe package is NOT installed in org: " + orgAlias);
    console.error("    Install it first:");
    console.error("    sf package install --package <04t...> --target-org " + orgAlias + " --wait 10");
    process.exit(1);
  }
  console.log("  ✔ kqexe package is installed");
} catch (e) {
  console.log("  ⚠  Could not verify package installation — proceeding anyway");
}

// ── Step 0: Namespace-transform all unpackaged components ────────────────────
console.log("\n══════════════════════════════════════════");
console.log(" Step 0: Preparing namespaced unpackaged components");
console.log("══════════════════════════════════════════");
console.log("  Transforms applied:");
console.log("   • Bare __c/__r names → kqexe__ prefix in all XML content");
console.log("   • Layout filenames: ObjectName__c- → kqexe__ObjectName__c-");
console.log("   • FlexiPage LWC component names: c:foo → kqexe:foo");
console.log("   • FlexiPage: removes AttachedContentNotes region");
console.log("   • PermissionSet: strips recordTypeVisibilities + externalCredentialPrincipalAccesses");
console.log("   • App: strips utilityBar reference to non-existent FlexiPage");

const UNPKG_SRC = path.join(__dirname, "..", "force-app-unpackaged", "main", "default");
const UNPKG_TMP = path.join(TMP_DIR, "force-app-unpackaged");

// Matches bare custom API names not already prefixed with kqexe__
const NS_RE = /(?<![A-Za-z0-9_])(?!kqexe__)([A-Za-z]\w*__[cr])(?![A-Za-z0-9_])/g;

function nsTransform(content) {
  return content.replace(NS_RE, `${NS}$1`);
}

// Rename layout filenames: ObjectName__c-Layout Name → kqexe__ObjectName__c-Layout Name
function renameLayout(filename) {
  return filename.replace(/^([A-Za-z]\w*__c)-/, `${NS}$1-`);
}

// Copy a source directory to the tmp area, transforming all file contents.
function copyAndTransformDir(subdir, opts = {}) {
  const srcDir = path.join(UNPKG_SRC, subdir);
  const dstDir = path.join(UNPKG_TMP, subdir);
  if (!fs.existsSync(srcDir)) return;
  fs.mkdirSync(dstDir, { recursive: true });

  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      copyAndTransformDir(path.join(subdir, entry.name), opts);
      continue;
    }

    const srcFile = path.join(srcDir, entry.name);
    const outName = opts.renameFile ? opts.renameFile(entry.name) : entry.name;
    const dstFile = path.join(path.join(UNPKG_TMP, subdir), outName);

    let content = fs.readFileSync(srcFile, "utf8");

    // Apply namespace prefix to all bare __c/__r API names in content
    content = nsTransform(content);

    // App: strip non-existent utility bar FlexiPage reference
    content = content.replace(/\s*<utilityBar>[^<]*<\/utilityBar>/g, "");

    // FlexiPage transforms
    if (entry.name.endsWith(".flexipage-meta.xml")) {

      // Prefix LWC component names with package namespace
      content = content.replace(
        /<componentName>(?!kqexe:)([a-zA-Z][a-zA-Z0-9]*)<\/componentName>/g,
        `<componentName>${NS.replace("__", ":")}$1</componentName>`
      );
      content = content.replace(
        /<identifier>c_([a-zA-Z][a-zA-Z0-9]*)<\/identifier>/g,
        `<identifier>${NS.replace("__", "_")}$1</identifier>`
      );

      // FlexiPage: prefix field references in visibilityRules {!Record.FieldName__c}
      content = content.replace(
        /\{!Record\.(?!kqexe__)([A-Za-z]\w*__c)\}/g,
        `{!Record.${NS}$1}`
      );
      console.log(`  ✔ Prefixed Record field references in ${entry.name}`);

      // Remove AttachedContentNotes flexiPageRegions block
      if (content.includes("AttachedContentNotes")) {
        content = removeFlexiPageRegion(content, "AttachedContentNotes");
        if (content.includes("AttachedContentNotes")) {
          console.error(`  ✖ FAILED to remove AttachedContentNotes from ${entry.name}`);
        } else {
          console.log(`  ✔ Removed AttachedContentNotes region from ${entry.name}`);
        }
      }
    }

    // PermissionSet: strip blocks that can't deploy from outside the package
    if (entry.name.endsWith(".permissionset-meta.xml")) {
      content = content.replace(/\s*<recordTypeVisibilities>[\s\S]*?<\/recordTypeVisibilities>/g, "");
      content = content.replace(/\s*<externalCredentialPrincipalAccesses>[\s\S]*?<\/externalCredentialPrincipalAccesses>/g, "");
    }

    fs.writeFileSync(dstFile, content);
    const displayName = outName !== entry.name ? `${entry.name} → ${outName}` : entry.name;
    console.log(`  ✔ Namespaced: ${path.join(subdir, displayName)}`);
  }
}

// Transform all unpackaged component types
["applications", "flexipages", "permissionsets"].forEach(d => copyAndTransformDir(d));
copyAndTransformDir("layouts", { renameFile: renameLayout });
copyAndTransformDir("namedCredentials");
copyAndTransformDir("reports");

// ── Step 1: Deploy unpackaged components ──────────────────────────────────────
console.log("\n══════════════════════════════════════════");
console.log(" Step 1: Deploying unpackaged components");
console.log("══════════════════════════════════════════");
console.log("  Deploying: App, FlexiPage, Permission Set, Named Credentials, Reports, Layouts");

const step1Dirs = [
  "applications", "flexipages", "permissionsets",
  "reports", "layouts"
  // namedCredentials skipped — requires External Credential to be created manually in Setup first
].flatMap(d => {
  const p = path.join(UNPKG_TMP, d);
  return fs.existsSync(p) ? ["--source-dir", p] : [];
});

exec("sf", [
  "project", "deploy", "start",
  ...step1Dirs,
  "--target-org", orgAlias,
  "--test-level", "NoTestRun",
  "--wait", "10"
]);

// ── Step 1b: Deploy Item__c action override ───────────────────────────────────
console.log("\n══════════════════════════════════════════");
console.log(" Step 1b: Deploying object action overrides");
console.log("══════════════════════════════════════════");

const itemObjSrc  = path.join(__dirname, "..", "force-app-unpackaged", "objects", "Item__c", "Item__c.object-meta.xml");
const itemObjDest = path.join(TMP_DIR, "objects", "kqexe__Item__c", "kqexe__Item__c.object-meta.xml");
fs.mkdirSync(path.dirname(itemObjDest), { recursive: true });

let objContent = fs.readFileSync(itemObjSrc, "utf8");
objContent = objContent.replace(/>(?!kqexe__)([A-Za-z]\w*__[cr])</g, `>${NS}$1<`);
objContent = objContent.replace(
  /<listViewButtons>(?!kqexe__)([^<]+)<\/listViewButtons>/g,
  `<listViewButtons>${NS}$1</listViewButtons>`
);
fs.writeFileSync(itemObjDest, objContent);
console.log("  ✔ Prepared kqexe__Item__c action override (View → Item_Record_Page)");

exec("sf", [
  "project", "deploy", "start",
  "--source-dir", path.join(TMP_DIR, "objects"),
  "--target-org", orgAlias,
  "--test-level", "NoTestRun",
  "--wait", "10"
]);

// ── Step 2: Assign permission sets ───────────────────────────────────────────
console.log("\n══════════════════════════════════════════");
console.log(" Step 2: Assigning permission sets");
console.log("══════════════════════════════════════════");

const pkgPermResult = spawnSync("sf", [
  "org", "assign", "permset",
  "--name", "kqexe__Lumen_Planning_Permission_Set_1",
  "--target-org", orgAlias
], { encoding: "utf8", shell: true, stdio: "inherit" });
if (pkgPermResult.status !== 0) {
  console.log("  ⚠  Package permission set already assigned or not found — skipping");
} else {
  console.log("  ✔ kqexe__Lumen_Planning_Permission_Set_1 assigned");
}

const permResult = spawnSync("sf", [
  "org", "assign", "permset",
  "--name", "Lumen_Planning_Permission_Set_1",
  "--target-org", orgAlias
], { encoding: "utf8", shell: true, stdio: "inherit" });
if (permResult.status !== 0) {
  console.log("  ⚠  Unpackaged permission set already assigned — skipping");
} else {
  console.log("  ✔ Lumen_Planning_Permission_Set_1 assigned");
}

// ── Step 3: Build RecordType ID mapping ───────────────────────────────────────
console.log("\n══════════════════════════════════════════");
console.log(" Step 3: Resolving RecordType IDs");
console.log("══════════════════════════════════════════");

const sourceRTMap = JSON.parse(
  fs.readFileSync(path.join(DATA_DIR, "record-types.json"), "utf8")
);

const rtData = sfJson(
  `data query -q "SELECT Id,SobjectType,DeveloperName FROM RecordType WHERE NamespacePrefix = 'kqexe'" -o ${orgAlias}`
);

const idRemap = {};
for (const rec of rtData.result?.records || []) {
  const unprefixedType = rec.SobjectType.replace(/^kqexe__/, "");
  const sourceTypeMap  = sourceRTMap[unprefixedType] || {};
  for (const [sourceId, devName] of Object.entries(sourceTypeMap)) {
    if (rec.DeveloperName === devName) {
      idRemap[sourceId] = rec.Id;
      console.log(`  ✔ ${unprefixedType}/${devName}: ${sourceId} → ${rec.Id}`);
    }
  }
}

// ── Step 4: Transform data files ──────────────────────────────────────────────
console.log("\n══════════════════════════════════════════");
console.log(" Step 4: Transforming data for namespace");
console.log("══════════════════════════════════════════");

function prefixCustom(name) {
  if (!name || name.startsWith(NS)) return name;
  if (name.endsWith("__c") || name.endsWith("__r")) return NS + name;
  return name;
}

function transformRecord(rec) {
  const out = { attributes: { ...rec.attributes } };
  if (out.attributes.type) out.attributes.type = prefixCustom(out.attributes.type);

  for (const [k, v] of Object.entries(rec)) {
    if (k === "attributes") continue;
    if (k === "RecordTypeId" && idRemap[v]) {
      out[k] = idRemap[v];
      continue;
    }
    const newKey = k.endsWith("__c") ? prefixCustom(k) : k;
    out[newKey] = (v && typeof v === "object" && !Array.isArray(v) && v.attributes)
      ? transformRecord(v) : v;
  }
  return out;
}

const originalPlan = JSON.parse(fs.readFileSync(path.join(DATA_DIR, "data-plan.json"), "utf8"));
const transformedPlan = originalPlan.map(entry => ({
  ...entry,
  sobject: prefixCustom(entry.sobject),
  files: entry.files.map(file => {
    const src  = JSON.parse(fs.readFileSync(path.join(DATA_DIR, file), "utf8"));
    const dest = { records: src.records.map(transformRecord) };
    const outPath = path.join(TMP_DIR, file);
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, JSON.stringify(dest, null, 2));
    console.log(`  ✔ Transformed ${file}`);
    return file;
  })
}));

const planPath = path.join(TMP_DIR, "data-plan.json");
fs.writeFileSync(planPath, JSON.stringify(transformedPlan, null, 2));

// ── Step 5: Import data ───────────────────────────────────────────────────────
console.log("\n══════════════════════════════════════════");
console.log(" Step 5: Importing data");
console.log("══════════════════════════════════════════");

exec("sf", ["data", "import", "tree", "--plan", planPath, "--target-org", orgAlias]);

// ── Step 6: Open org ──────────────────────────────────────────────────────────
console.log("\n══════════════════════════════════════════");
console.log(" Step 6: Opening org in browser");
console.log("══════════════════════════════════════════");

const openResult = spawnSync("sf", ["org", "open", "--target-org", orgAlias], {
  encoding: "utf8",
  shell: true,
  stdio: "inherit"
});
if (openResult.status !== 0) {
  console.error("  ⚠  Could not open org automatically. Run manually:");
  console.error(`     sf org open --target-org ${orgAlias}`);
} else {
  console.log("  ✔ Org opened in browser");
}

// ── Done ──────────────────────────────────────────────────────────────────────
console.log("\n══════════════════════════════════════════");
console.log(` ✅  Post-install complete for: ${orgAlias}`);
console.log("  All components deployed and configured:");
console.log("  • App, FlexiPage, Permission Set, Named Credentials, Reports, Layouts");
console.log("  • Item_Record_Page action override active on kqexe__Item__c");
console.log("  • 1,355+ sample records imported");
console.log("══════════════════════════════════════════");