#!/bin/bash
# =============================================================================
# orgInit.sh — Full scratch org setup for Lumen
#
# Usage:
#   ./scripts/orgInit.sh                          # creates org aliased "lumenScratch-1" (auto-increments)
#   ./scripts/orgInit.sh myAlias                  # custom alias
#   ./scripts/orgInit.sh myAlias devhub@acme.com  # custom alias + dev hub
#
# What it does:
#   1. Creates a scratch org
#   2. Deploys all source (force-app)
#   3. Assigns the Lumen permission set
#   4. Imports sample data (all custom objects)
#   5. Opens the org
# =============================================================================

set -e

DEVHUB=${2:-}

# Auto-increment alias if none provided
if [ -z "$1" ]; then
  NUM=1
  while sf org list 2>/dev/null | grep -q "lumenScratch-${NUM}"; do
    NUM=$((NUM + 1))
  done
  ALIAS="lumenScratch-${NUM}"
else
  ALIAS=$1
fi

echo ""
echo "============================================"
echo " Lumen Scratch Org Setup"
echo "============================================"
echo " Alias  : $ALIAS"
echo ""

# ── 1. Create scratch org ───────────────────────────────────────────────────
echo "► Creating scratch org..."
if [ -n "$DEVHUB" ]; then
  sf org create scratch \
    --definition-file config/project-scratch-def.json \
    --alias "$ALIAS" \
    --target-dev-hub "$DEVHUB" \
    --duration-days 30 \
    --set-default
else
  sf org create scratch \
    --definition-file config/project-scratch-def.json \
    --alias "$ALIAS" \
    --duration-days 30 \
    --set-default
fi
echo "  ✔ Scratch org created: $ALIAS"

# ── 2. Deploy source ─────────────────────────────────────────────────────────
echo ""
echo "► Deploying source to scratch org..."
sf project deploy start \
  --source-dir force-app \
  --target-org "$ALIAS"
echo "  ✔ Source deployed"

# ── 3. Assign permission set ─────────────────────────────────────────────────
echo ""
echo "► Assigning permission set..."
sf org assign permset \
  --name Lumen_Planning_Permission_Set_1 \
  --target-org "$ALIAS" || echo "  ⚠ Permission set assignment skipped (may not exist)"

# ── 4. Import sample data ─────────────────────────────────────────────────────
echo ""
echo "► Resolving RecordType IDs for target org..."
python scripts/fixRecordTypes.py "$ALIAS"
echo "  ✔ RecordType IDs resolved"

echo ""
echo "► Importing sample data..."
sf data import tree \
  --plan data/data-plan.json \
  --target-org "$ALIAS"
echo "  ✔ Data imported"

# ── 5. Open org ───────────────────────────────────────────────────────────────
echo ""
echo "► Opening org..."
sf org open --target-org "$ALIAS"

echo ""
echo "============================================"
echo " Setup complete! Org alias: $ALIAS"
echo "============================================"
