#!/bin/bash
# =============================================================================
# createPackageVersion.sh — Build a new 2GP managed package version for Lumen
#
# Usage:
#   bash scripts/createPackageVersion.sh                        # default: lumenProd
#   bash scripts/createPackageVersion.sh <devHubAlias>          # custom dev hub
#
# Steps performed:
#   1. Create new package version from force-app (auto-increments build number)
#   2. Wait up to 30 min for Salesforce to compile and run Apex tests
#   3. Print version ID + install URL
#   4. Ask for confirmation before promoting to Released
#
# Post-deployment (run manually after package installs in target org):
#   sf project deploy start --source-dir force-app-unpackaged --target-org <alias>
#
# Prerequisites:
#   - Dev hub authenticated: sf org login web --alias lumenProd --set-default-dev-hub
#   - sfdx-project.json: versionNumber set (e.g. 2.0.0.NEXT), ancestorVersion: NONE
# =============================================================================

set -e

DEVHUB=${1:-lumenProd}
PACKAGE=kqexe

echo ""
echo "============================================"
echo " Lumen 2GP Package Version Create"
echo "============================================"
echo " Package : $PACKAGE"
echo " Dev Hub : $DEVHUB"
echo ""

# ── 0. Sort components: move unpackaged metadata out of force-app ─────────────
# Moves flexipages, layouts (custom objects), reports, namedCredentials,
# permissionsets from force-app/ → force-app-unpackaged/ and strips any
# Flexipage actionOverrides from object XML in force-app/.
echo "► Step 0: Sorting components (force-app → force-app-unpackaged)..."
node scripts/sortComponents.js
echo ""

# ── 1. Create package version ──────────────────────────────────────────────────
echo "► Step 1: Creating package version (may take 10-20 min)..."

RAW=$(sf package version create --package "$PACKAGE" --installation-key-bypass --skip-ancestor-check --wait 30 --target-dev-hub "$DEVHUB" --json 2>&1) || true

# Strip warning/info lines before the JSON object
JSON=$(echo "$RAW" | node -e "
  let d=''; process.stdin.on('data',c=>d+=c);
  process.stdin.on('end',()=>{
    const lines = d.split('\n');
    const start = lines.findIndex(l => l.trim().startsWith('{'));
    if (start === -1) { process.stdout.write(d); } else { process.stdout.write(lines.slice(start).join('\n')); }
  });
")

# ── 2. Parse SubscriberPackageVersionId ────────────────────────────────────────
SUBS_ID=$(echo "$JSON" | node -e "
  let d=''; process.stdin.on('data',c=>d+=c);
  process.stdin.on('end',()=>{
    try {
      const j = JSON.parse(d);
      if (j.status !== 0) {
        console.error('Package version create failed:');
        console.error(j.message || JSON.stringify(j.data || j, null, 2));
        process.exit(1);
      }
      const id = j?.result?.SubscriberPackageVersionId;
      if (!id) {
        console.error('No SubscriberPackageVersionId in result.');
        console.error(JSON.stringify(j.result, null, 2));
        process.exit(1);
      }
      console.log(id);
    } catch(e) {
      console.error('Failed to parse sf output:', e.message);
      console.error(d.substring(0, 500));
      process.exit(1);
    }
  });
") || {
  echo ""
  echo "RAW OUTPUT:"
  echo "$RAW"
  exit 1
}

echo "  ✔ Package version created: $SUBS_ID"

# ── 3. Print install URL ───────────────────────────────────────────────────────
INSTALL_URL="https://login.salesforce.com/packaging/installPackage.apexp?p0=${SUBS_ID}"

echo ""
echo "============================================"
echo " VERSION READY (not yet Released)"
echo " $INSTALL_URL"
echo "============================================"
echo ""
echo "Install via CLI (Beta):"
echo "  sf package install --package $SUBS_ID --target-org <alias> --wait 10"
echo ""

# ── 4. Confirm before promoting ────────────────────────────────────────────────
read -p "► Promote to Released? (y/n): " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo ""
  echo "► Step 2: Promoting to Released..."
  sf package version promote --package "$SUBS_ID" --target-dev-hub "$DEVHUB" --no-prompt
  echo "  ✔ Promoted to Released"
  echo ""
  echo "── Post-deployment (after package installs) ─"
  echo "  sf project deploy start --source-dir force-app-unpackaged --target-org <alias>"
  echo ""
else
  echo ""
  echo "  Skipped promotion. To promote later:"
  echo "  sf package version promote --package $SUBS_ID --target-dev-hub $DEVHUB --no-prompt"
  echo ""
fi
