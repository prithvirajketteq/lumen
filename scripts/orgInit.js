#!/usr/bin/env node
// =============================================================================
// orgInit.js — Full scratch org setup for Lumen
//
// Usage:
//   node scripts/orgInit.js                         # creates org aliased "lumenScratch-1" (auto-increments)
//   node scripts/orgInit.js myAlias                 # custom alias
//   node scripts/orgInit.js myAlias devhub@acme.com # custom alias + dev hub
// =============================================================================

const { spawnSync } = require("child_process");
const readline = require("readline");

const [, , aliasArg, devhubArg] = process.argv;

// ── Helper: ask a yes/no question ─────────────────────────────────────────────
function ask(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim().toLowerCase());
    });
  });
}

// ── Helper: parse JSON from sf output (ignores leading warning lines) ─────────
function parseSfJson(stdout) {
  const jsonStart = stdout ? stdout.indexOf("{") : -1;
  if (jsonStart < 0) return null;
  try {
    return JSON.parse(stdout.slice(jsonStart));
  } catch {
    return null;
  }
}

// ── Helper: print sf warnings that appear before the JSON ─────────────────────
function printWarnings(stdout) {
  if (!stdout) return;
  const jsonStart = stdout.indexOf("{");
  const pre = jsonStart >= 0 ? stdout.slice(0, jsonStart) : stdout;
  pre.split("\n").map((l) => l.trim()).filter((l) => l).forEach((l) => console.log(`  ⚠  ${l}`));
}

// ── Helper: run a command and return { parsed, status, stderr } ───────────────
function exec(cmd, args) {
  const result = spawnSync(cmd, args, { encoding: "utf8", shell: true });
  printWarnings(result.stdout);
  return {
    parsed: parseSfJson(result.stdout),
    status: result.status,
    stderr: result.stderr?.trim()
  };
}

// ── Helper: exit with a clear error message ───────────────────────────────────
function fail(msg, parsed) {
  const detail = parsed?.message || parsed?.result?.message || "";
  const action = parsed?.action || parsed?.result?.action || "";
  console.error(`  ✖ FAILED: ${detail || msg}`);
  if (action) console.error(`  → Fix: ${action}`);
  process.exit(1);
}

// ── Main ──────────────────────────────────────────────────────────────────────
(async () => {

  console.log("");
  console.log("============================================");
  console.log(" Lumen Org Init");
  console.log("============================================");

  // ── STEP 1 — Retrieve latest metadata ──────────────────────────────────────
  console.log("");
  console.log("► [1] Retrieving latest metadata from org...");
  const retrieveResult = spawnSync(
    "powershell",
    ["-ExecutionPolicy", "Bypass", "-File", "scripts/retrieve-all.ps1", "-OrgAlias", "kqexpkg"],
    { encoding: "utf8", shell: true, stdio: "inherit" }
  );
  if (retrieveResult.status !== 0) {
    console.error("  ✖ Retrieve failed. Aborting.");
    process.exit(1);
  }
  console.log("  ✔ Metadata retrieved successfully.");

  // ── STEP 2 — Ask whether to create scratch org ─────────────────────────────
  console.log("");
  const proceedAnswer = await ask("► Do you want to create a scratch org and run post-deployment? (y/n): ");
  if (proceedAnswer !== "y") {
    console.log("");
    console.log("  Skipping scratch org creation. Retrieve complete!");
    console.log("============================================");
    process.exit(0);
  }

  // ── STEP 3 — Resolve alias ─────────────────────────────────────────────────
  let alias;
  if (aliasArg) {
    alias = aliasArg;
  } else {
    const { parsed } = exec("sf", ["org", "list", "--json"]);
    const existingAliases = parsed?.result?.scratchOrgs?.map((o) => o.alias) ?? [];
    let num = 1;
    while (existingAliases.includes(`lumenScratch-${num}`)) num++;
    alias = `lumenScratch-${num}`;
  }

  console.log("");
  console.log("============================================");
  console.log(" Lumen Scratch Org Setup");
  console.log("============================================");
  console.log(` Alias  : ${alias}`);
  console.log("");

  // ── STEP 4 — Create scratch org ────────────────────────────────────────────
  console.log("► [2/6] Creating scratch org...");
  const createArgs = [
    "org", "create", "scratch",
    "--definition-file", "config/project-scratch-def.json",
    "--alias", alias,
    "--duration-days", "30",
    "--set-default",
    "--json"
  ];
  if (devhubArg) createArgs.push("--target-dev-hub", devhubArg);

  const createResult = exec("sf", createArgs);
  if (createResult.status !== 0) fail("Scratch org creation failed", createResult.parsed);
  const username = createResult.parsed?.result?.username || alias;
  console.log(`  ✔ Scratch org created`);
  console.log(`     Username : ${username}`);
  console.log(`     Alias    : ${alias}`);

  // ── STEP 5 — Deploy force-app ──────────────────────────────────────────────
  console.log("");
  console.log("► [3/6] Deploying force-app to scratch org...");
  console.log("     Deploying: objects, classes, LWC, triggers, permissions...");
  const deployResult = exec("sf", [
    "project", "deploy", "start",
    "--source-dir", "force-app",
    "--target-org", alias,
    "--json"
  ]);
  if (deployResult.status !== 0) {
    const errors = deployResult.parsed?.result?.details?.componentFailures || [];
    if (errors.length > 0) {
      console.error(`  ✖ Deploy failed with ${errors.length} component error(s):`);
      errors.slice(0, 10).forEach((e) => console.error(`     • [${e.componentType}] ${e.fullName}: ${e.problem}`));
    }
    fail("Deployment failed", deployResult.parsed);
  }
  const deployed = deployResult.parsed?.result?.numberComponentsDeployed ?? 0;
  const deployErrors = deployResult.parsed?.result?.numberComponentErrors ?? 0;
  const byType = {};
  (deployResult.parsed?.result?.deployedSource || []).forEach(({ type }) => {
    byType[type] = (byType[type] || 0) + 1;
  });
  console.log(`  ✔ Deployment complete — ${deployed} components deployed, ${deployErrors} errors`);
  Object.entries(byType).sort().forEach(([type, count]) => console.log(`     • ${type}: ${count}`));

  // ── STEP 6 — Deploy force-app-unpackaged ───────────────────────────────────
  console.log("");
  console.log("► [4/6] Deploying unpackaged metadata...");
  console.log("     Includes: app, flexipages, named credentials, reports, permissionset");
  const unpackagedResult = exec("sf", [
    "project", "deploy", "start",
    "--source-dir", "force-app-unpackaged",
    "--target-org", alias,
    "--json"
  ]);
  if (unpackagedResult.status !== 0) {
    const errors = unpackagedResult.parsed?.result?.details?.componentFailures || [];
    if (errors.length > 0) {
      console.error(`  ✖ Unpackaged deploy failed with ${errors.length} error(s):`);
      errors.slice(0, 5).forEach((e) => console.error(`     • [${e.componentType}] ${e.fullName}: ${e.problem}`));
    }
    fail("Unpackaged deploy failed", unpackagedResult.parsed);
  }
  console.log("  ✔ Unpackaged metadata deployed");

  // ── STEP 7 — Assign permission set ─────────────────────────────────────────
  console.log("");
  console.log("► [5/6] Assigning permission set...");
  const permResult = exec("sf", [
    "org", "assign", "permset",
    "--name", "Lumen_Planning_Permission_Set_1",
    "--target-org", alias,
    "--json"
  ]);
  if (permResult.status !== 0) {
    console.log("  ⚠  Permission set not found — skipping (assign manually if needed)");
  } else {
    console.log("  ✔ Permission set assigned: Lumen_Planning_Permission_Set_1");
  }

  // ── STEP 8 — Import sample data ────────────────────────────────────────────
  console.log("");
  console.log("► [6/6] Importing sample data...");
  console.log("     Resolving RecordType IDs for target org...");
  const fixResult = exec("python", ["scripts/fixRecordTypes.py", alias]);
  if (fixResult.status !== 0) {
    console.log("  ⚠  RecordType ID resolution failed — import may partially fail");
  }
  console.log("     Objects: Vendor__c, Customer__c, Site__c, Item__c, Interchangeable_Part__c, Item_Site__c, Vendor_Pricing__c, Order__c");

  const importResult = exec("sf", [
    "data", "import", "tree",
    "--plan", "data/data-plan.json",
    "--target-org", alias,
    "--json"
  ]);
  if (importResult.status !== 0) fail("Data import failed", importResult.parsed);

  const importedResults = importResult.parsed?.result?.results || [];
  const countByObject = {};
  importedResults.forEach(({ refId, type }) => {
    const obj = type || (refId ? refId.replace(/Ref\d+$/, "__c") : "Unknown");
    countByObject[obj] = (countByObject[obj] || 0) + 1;
  });
  const totalRecords = importedResults.length;
  console.log(`  ✔ Data import complete — ${totalRecords} records created`);
  Object.entries(countByObject).forEach(([obj, count]) => console.log(`     • ${obj}: ${count} record(s)`));

  // ── STEP 9 — Open org ──────────────────────────────────────────────────────
  console.log("");
  console.log("► Opening org in browser...");
  const openResult = spawnSync("sf", ["org", "open", "--target-org", alias], {
    encoding: "utf8",
    shell: true,
    stdio: "inherit"
  });
  if (openResult.status !== 0) {
    console.error("  ⚠  Could not open org automatically. Run manually:");
    console.error(`     sf org open --target-org ${alias}`);
  } else {
    console.log("  ✔ Org opened in browser");
  }

  console.log("");
  console.log("============================================");
  console.log(` Setup complete! Org alias: ${alias}`);
  console.log("============================================");

})();