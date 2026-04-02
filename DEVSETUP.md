# Lumen — Developer Setup Guide

## Overview

Lumen is a Salesforce 2GP Managed Package — a Lightning dashboard for parts inventory analysis. This guide covers how to get a scratch org running with all source and sample data.

---

## Prerequisites

| Tool | Version |
|------|---------|
| Salesforce CLI (`sf`) | ≥ 2.x |
| Node.js | ≥ 18 |
| Python | ≥ 3.9 |
| npm | ≥ 9 |

A **Dev Hub** org must be enabled and connected via `sf org login`.

---

## Quick Start — Scratch Org

### 1. Clone and install

```bash
git clone <repo-url>
cd lumen
npm install
```

### 2. Create scratch org + deploy + load data (one command)

```bash
npm run org:init
# or with a custom alias:
node scripts/orgInit.js myAlias
# or specifying a dev hub:
node scripts/orgInit.js myAlias devhub@yourorg.com
```

This script runs 6 steps automatically:
1. Creates a 30-day scratch org
2. Deploys all packaged source from `force-app/`
3. Assigns the `Lumen_Planning_Permission_Set_1` permission set
4. Deploys unpackaged metadata from `force-app-unpackaged/` (Spares Planning app + Item Record Page, set as org default)
5. Resolves org-specific RecordType IDs and imports all sample data (`data/data-plan.json`)
6. Opens the org in your browser

### 3. Manual steps (if needed)

```bash
# Create scratch org
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias lumenScratch \
  --duration-days 30 \
  --set-default

# Deploy packaged source
sf project deploy start --source-dir force-app --target-org lumenScratch

# Assign permission set
sf org assign permset --name Lumen_Planning_Permission_Set_1 --target-org lumenScratch

# Deploy unpackaged metadata (App + FlexiPage, not part of the package)
sf project deploy start --source-dir force-app-unpackaged --target-org lumenScratch

# Resolve RecordType IDs for this org, then import data
python scripts/fixRecordTypes.py lumenScratch
sf data import tree --plan data/data-plan.json --target-org lumenScratch

# Open org
sf org open --target-org lumenScratch
```

### 4. Delete a scratch org

```bash
sf org delete scratch --no-prompt --target-org <alias>
```

---

## Project Structure

```
lumen/
├── force-app/main/default/     # Packaged Salesforce metadata (goes into 2GP package)
│   ├── classes/                # Apex classes & tests
│   ├── lwc/                    # Lightning Web Components
│   ├── objects/                # Custom objects, fields, layouts
│   ├── customMetadata/         # CMT records (rollup configs, batch SOQL, CSV fields)
│   ├── permissionsets/         # Permission sets
│   └── triggers/               # Apex triggers
│
├── force-app-unpackaged/       # Metadata deployed OUTSIDE the package (both scratch orgs and subscriber orgs)
│   ├── applications/           # Spares_Planning Lightning App (tabs use kqexe__ prefix)
│   ├── flexipages/             # Item_Record_Page (all field/component refs use kqexe__ prefix)
│   ├── namedCredentials/       # Ketteq_API_Dev (dev-only, not in package)
│   └── permissionsets/         # Lumen_Planning_Permission_Set_1
│
├── data/                       # Sample data (1,355+ records)
│   ├── data-plan.json          # Import plan — unprefixed sobject names (for scratch org / fixRecordTypes.py)
│   ├── record-type-ids.json    # Tracks current RecordType IDs in data files (auto-updated by fixRecordTypes.py)
│   ├── record-types.json       # Maps source RecordType IDs → DeveloperNames (used by postInstall.js for subscriber orgs)
│   ├── vendor-Vendor__c.json               (61 records)
│   ├── customer-Customer__c.json           (1 record)
│   ├── site-Site__c.json                   (85 records)
│   ├── item-Item__c.json                   (25 records)
│   ├── interchangeable-Interchangeable_Part__c.json  (5 records)
│   ├── itemsite-Item_Site__c.json          (105 records)
│   ├── vendorpricing-Vendor_Pricing__c.json (33 records)
│   └── order-Order__c.json                 (1005 records)
│
├── config/
│   └── project-scratch-def.json   # Scratch org definition
├── manifest/
│   ├── package.xml                # Metadata manifest for retrieve from source org
│   └── package-unpackaged.xml     # Manifest for the unpackaged components only
├── scripts/
│   ├── orgInit.js                 # Scratch org setup: create org → deploy → assign perms → import data → open
│   ├── orgInit.sh                 # Bash equivalent (for direct shell use)
│   ├── postInstall.js             # Subscriber org setup: deploy unpackaged + namespace-transform + import data
│   ├── fixRecordTypes.py          # Resolves org-specific RecordType IDs in data files before scratch org import
│   └── buildDataPlan.py           # Rebuilds data/ from source org
└── sfdx-project.json              # 2GP package configuration
```

---

## Custom Objects & Data

| Object | Records | Description |
|--------|---------|-------------|
| `Vendor__c` | 61 | Parts vendors/suppliers |
| `Customer__c` | 1 | Customer accounts |
| `Site__c` | 85 | Depot/warehouse sites |
| `Item__c` | 25 | Parts/items inventory |
| `Interchangeable_Part__c` | 5 | Interchangeable part relationships |
| `Item_Site__c` | 105 | Item inventory levels per site |
| `Vendor_Pricing__c` | 33 | Vendor pricing per item (leaf items only — lookup filter blocks primary items) |
| `Order__c` | 1005 | Parts orders history |

Data is imported in dependency order (parents before children). Cross-object references use `@referenceId` format resolved at import time.

### RecordType ID handling

RecordType IDs are org-specific and change with every new scratch org. `scripts/fixRecordTypes.py` handles this automatically:
- Reads `data/record-type-ids.json` to find which IDs are currently in the data files
- Queries the target org for the correct IDs by `DeveloperName`
- Patches the data files in-place before import
- Updates `record-type-ids.json` for the next run

Objects with RecordTypes: `Vendor__c` (Repair_Vendor, Supplier), `Site__c` (Depot, Warehouse), `Order__c` (Demand_Order, Supply_Order).

---

## What's in the Package vs. Unpackaged

| Metadata | Package (`force-app`) | Unpackaged (`force-app-unpackaged`) |
|---|---|---|
| Apex classes, triggers | ✅ | — |
| Custom objects, fields | ✅ | — |
| LWC (`dynamicFieldCounter`) | ✅ | — |
| Layouts, list views, tabs | ✅ | — |
| Custom metadata | ✅ | — |
| Named credential (`Amazon_API_Endpoint`) | ✅ | — |
| `Spares_Planning` App | — | ✅ |
| `Item_Record_Page` FlexiPage | — | ✅ |
| Permission set (`Lumen_Planning_Permission_Set_1`) | — | ✅ |
| Named credential (`Ketteq_API_Dev`, dev only) | — | ✅ (manual — requires ExternalCredential setup) |

---

## 2GP Package Setup

The project is configured as a **2GP Managed package** (`kqexe`, namespace `kqexe`) in `sfdx-project.json`. Dev Hub is `lumenProd`. See [PACKAGING.md](./PACKAGING.md) for the full packaging guide.

### Create a new package version and deploy to a subscriber org

```bash
# 1. Create a new package version (max ~6/day per Dev Hub)
bash scripts/createPackageVersion.sh

# 2. Install in target org  ← MUST happen before postInstall.js
sf package install --package <04t-id> --target-org <targetOrg> --wait 10

# 3. Deploy unpackaged components + assign perms + import sample data
node scripts/postInstall.js <targetOrg>
```

> See [PACKAGING.md](./PACKAGING.md) for full details, common errors, and the troubleshooting table.

---

## Refreshing Sample Data

To re-export all records from the `kqexpkg` org into `data/`:

```bash
npm run data:rebuild
# or directly:
python scripts/buildDataPlan.py
```

This queries all custom objects from `mydevhub` (kqexpkg) and rebuilds the JSON files with correct cross-object `@referenceId` links.

> **Note:** After rebuilding, run `python scripts/fixRecordTypes.py <alias>` before the next data import to remap RecordType IDs for the target org.

---

## Development Commands

```bash
npm run lint               # ESLint on LWC/Aura JS
npm test                   # Run all LWC Jest unit tests
npm run test:unit:watch    # Jest watch mode
npm run test:unit:coverage # Jest coverage report
npm run prettier           # Format all files
npm run prettier:verify    # Verify formatting

sf apex run test -o lumenScratch   # Run Apex tests in scratch org
```

---

## Architecture

See [CLAUDE.md](./CLAUDE.md) for full architecture details including:
- Apex trigger pattern and `TriggerHandler` base class
- `ItemTriggerHandler` CMT-driven rollup aggregation
- Configuration-driven patterns via `Application_Config__mdt`
- `BatchCalculateRepairAction` repair status logic
