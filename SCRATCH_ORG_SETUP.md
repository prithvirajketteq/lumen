# Lumen — Scratch Org Setup & Deployment Guide

This guide covers how to set up a local development environment, retrieve metadata from the source org, create a scratch org, deploy all source, and import sample data.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Salesforce CLI (`sf`) | ≥ 2.x | `sf --version` to verify |
| Node.js | ≥ 18 | `node --version` to verify |
| Python | ≥ 3.9 | `python --version` to verify |
| npm | ≥ 9 | `npm --version` to verify |
| PowerShell | Any | Required for `retrieve-all.ps1` (Windows) |

A **Dev Hub** org must be enabled and authenticated:

```bash
sf org login web --alias lumenProd --set-default-dev-hub
```

---

## Step 0 — Clone & Install Dependencies

```bash
git clone <repo-url>
cd lumen
npm install
```

---

## Step 1 — Retrieve Latest Metadata from Source Org

Before creating a scratch org, pull the latest metadata from the source/packaging org (`kqexpkg`) to ensure your local files are up to date.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/retrieve-all.ps1 -OrgAlias kqexpkg
```

**What this script does (9 steps):**

| Step | Action |
|------|--------|
| 1 | Verifies org connection to `kqexpkg` |
| 2 | Prompts for safety confirmation before deleting local files |
| 3 | Clears `force-app/main/default/` and `force-app-unpackaged/main/default/` |
| 4 | Sets `force-app` as the default directory in `sfdx-project.json` |
| 5 | Retrieves managed package components via `manifest/package.xml` into `force-app/` |
| 6 | Switches to `force-app-unpackaged` as default and retrieves unpackaged components via `manifest/unpackaged.xml` |
| 7 | Restores `sfdx-project.json` defaults (`force-app` as default) |
| 8 | Removes `<type>Flexipage</type>` action overrides from `Item__c` object XML (prevents deploy errors) |
| 9 | Strips `externalCredentialPrincipalAccesses` from the Permission Set (can't deploy outside package) and removes `AttachedContentNotes` region from the FlexiPage |

> **Note:** You will be prompted with a warning before deletion. Type `y` to continue or `n` to abort.

---

## Step 2 — Create Scratch Org, Deploy & Import Data

### Option A — One-Command Setup (Recommended)

```bash
npm run org:init
# With a custom alias:
node scripts/orgInit.js myAlias
# With a custom alias + specific Dev Hub:
node scripts/orgInit.js myAlias devhub@yourorg.com
```

The script first runs `retrieve-all.ps1` automatically, then asks if you want to proceed with scratch org creation. It auto-increments the alias (`lumenScratch-1`, `lumenScratch-2`, etc.) if no alias is provided.

**What `orgInit.js` automates (6 steps after retrieval):**

| Step | Action |
|------|--------|
| 1 | Retrieves latest metadata from `kqexpkg` via `retrieve-all.ps1` |
| 2 | Creates a 30-day scratch org using `config/project-scratch-def.json` |
| 3 | Deploys all packaged source from `force-app/` (Apex, LWC, objects, triggers, CMT, etc.) |
| 4 | Deploys unpackaged metadata from `force-app-unpackaged/` (App, FlexiPage, Permission Set, Named Credentials, Reports, Layouts) |
| 5 | Assigns `Lumen_Planning_Permission_Set_1` permission set to the running user |
| 6 | Resolves org-specific RecordType IDs via `fixRecordTypes.py`, imports 1,355+ sample records, opens org in browser |

---

### Option B — Manual Step-by-Step

Use these commands if you need more control or if `orgInit.js` fails at a specific step.

#### 1. Create scratch org

```bash
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias lumenScratch \
  --duration-days 30 \
  --set-default
```

#### 2. Deploy packaged source

```bash
sf project deploy start --source-dir force-app --target-org lumenScratch
```

Deploys: Apex classes, LWC, custom objects, triggers, custom metadata, permission sets, layouts, tabs, and list views.

#### 3. Deploy unpackaged metadata

```bash
sf project deploy start --source-dir force-app-unpackaged --target-org lumenScratch
```

Deploys: `Spares_Planning` Lightning App, `Item_Record_Page` FlexiPage, `Lumen_Planning_Permission_Set_1` permission set, Named Credentials, Reports, Layouts.

#### 4. Assign permission set

```bash
sf org assign permset --name Lumen_Planning_Permission_Set_1 --target-org lumenScratch
```

#### 5. Resolve RecordType IDs and import sample data

```bash
# Resolve org-specific RecordType IDs in data files
python scripts/fixRecordTypes.py lumenScratch

# Import all sample data (1,355+ records across 8 objects)
sf data import tree --plan data/data-plan.json --target-org lumenScratch
```

#### 6. Open org in browser

```bash
sf org open --target-org lumenScratch
```

---

## Post-Deployment Steps

After the org is created and data is loaded, verify the following:

### 1. Confirm Deployment

```bash
sf project deploy report --target-org lumenScratch
```

### 2. Run Apex Tests

```bash
sf apex run test -o lumenScratch --wait 10
```

All tests should pass. Apex tests use `TestDataFactory` for fixtures and `MockAmazonCallout` for HTTP mocks.

### 3. Run LWC Jest Tests

```bash
npm test
```

### 4. Verify Data Import

Check record counts in the org:

```bash
sf data query -q "SELECT COUNT() FROM Item__c" -o lumenScratch
sf data query -q "SELECT COUNT() FROM Order__c" -o lumenScratch
```

Expected: 25 Item records, 1,005 Order records.

### 5. Verify the App is Accessible

Navigate to the **Spares Planning** Lightning App in the org. If it doesn't appear, check that the permission set was assigned and the FlexiPage deployed correctly.

### 6. Verify RecordType Visibility

If Vendor, Site, or Order record types are missing, re-run:

```bash
python scripts/fixRecordTypes.py lumenScratch
sf data import tree --plan data/data-plan.json --target-org lumenScratch
```

---

## What Lives Where

| Metadata | Directory | Notes |
|----------|-----------|-------|
| Apex classes & triggers | `force-app/` | Part of the 2GP package |
| Custom objects & fields | `force-app/` | Part of the 2GP package |
| LWC (`dynamicFieldCounter`) | `force-app/` | Part of the 2GP package |
| Custom metadata (CMT) | `force-app/` | Rollup configs, batch SOQL, CSV fields |
| Named credential (`Amazon_API_Endpoint`) | `force-app/` | Part of the package |
| `Spares_Planning` App | `force-app-unpackaged/` | Deployed separately — not in package |
| `Item_Record_Page` FlexiPage | `force-app-unpackaged/` | Deployed separately — not in package |
| `Lumen_Planning_Permission_Set_1` | `force-app-unpackaged/` | Deployed separately — not in package |
| Named credential (`Ketteq_API_Dev`) | `force-app-unpackaged/` | Dev-only, requires manual ExternalCredential setup |
| Sample data (1,355+ records) | `data/` | Imported via `sf data import tree` |

---

## Sample Data Objects

| Object | Records | Description |
|--------|---------|-------------|
| `Vendor__c` | 61 | Parts vendors/suppliers |
| `Customer__c` | 1 | Customer accounts |
| `Site__c` | 85 | Depot/warehouse sites |
| `Item__c` | 25 | Parts/items with parent-child hierarchy |
| `Interchangeable_Part__c` | 5 | Interchangeable part relationships |
| `Item_Site__c` | 105 | Item inventory levels per site |
| `Vendor_Pricing__c` | 33 | Vendor pricing per item |
| `Order__c` | 1,005 | Parts orders history |

RecordTypes (org-specific IDs auto-resolved by `fixRecordTypes.py`):
- `Vendor__c`: `Repair_Vendor`, `Supplier`
- `Site__c`: `Depot`, `Warehouse`
- `Order__c`: `Demand_Order`, `Supply_Order`

---

## Refreshing Sample Data from Source Org

To re-export all records from the `kqexpkg` org into `data/`:

```bash
npm run data:rebuild
# or directly:
python scripts/buildDataPlan.py
```

After rebuilding, always re-run RecordType resolution before the next import:

```bash
python scripts/fixRecordTypes.py <scratchOrgAlias>
```

---

## Development Commands

```bash
npm run lint                  # ESLint on LWC/Aura JS
npm test                      # Run all LWC Jest unit tests
npm run test:unit:watch       # Jest watch mode
npm run test:unit:coverage    # Jest coverage report
npm run prettier              # Format all files
npm run prettier:verify       # Verify formatting (no changes)

sf apex run test -o lumenScratch --wait 10   # Run Apex tests in org
```

Pre-commit hooks run lint + Prettier + related Jest tests automatically via Husky/lint-staged.

---

## Deleting a Scratch Org

```bash
sf org delete scratch --no-prompt --target-org lumenScratch
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `retrieve-all.ps1` fails with execution policy error | Run `powershell -ExecutionPolicy Bypass -File scripts/retrieve-all.ps1 -OrgAlias kqexpkg` |
| Deploy fails with component errors | Check `force-app/` is up to date — re-run retrieve first |
| `fixRecordTypes.py` fails | Ensure Python ≥ 3.9 and that the org alias is authenticated: `sf org display -o <alias>` |
| Data import fails on RecordTypeId | Re-run `python scripts/fixRecordTypes.py <alias>` then retry import |
| Permission set not found warning | Assign manually: `sf org assign permset --name Lumen_Planning_Permission_Set_1 --target-org <alias>` |
| Scratch org creation fails (daily limit) | Dev Hub has a daily scratch org creation limit — wait until the next day or use a different Dev Hub |
