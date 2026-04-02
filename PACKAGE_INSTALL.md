# Lumen — Package Installation Guide

This guide covers how to install the `kqexe` managed package into a subscriber org (sandbox or production) and run all post-installation setup steps to get the app fully functional.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Salesforce CLI (`sf`) | ≥ 2.x | `sf --version` to verify |
| Node.js | ≥ 18 | `node --version` to verify |
| Python | ≥ 3.9 | `python --version` to verify |

The **target org** must be authenticated before running any commands:

```bash
sf org login web --alias <targetOrgAlias>
```

---

## Current Released Version

| Version | Subscriber Package Version ID |
|---------|-------------------------------|
| 5.0.0.1 | `04ta500000D9GKbAAN` |

---

## Step 1 — Install the Package

Install the managed package into the target org. The package must be installed **before** running any post-install steps.

### Option A — CLI

```bash
sf package install \
  --package 04ta500000D9GKbAAN \
  --target-org <orgAlias> \
  --wait 15
```

### Option B — Browser

```
https://login.salesforce.com/packaging/installPackage.apexp?p0=04ta500000D9GKbAAN
```

Log in to the target org and follow the installer wizard.

### Check installation status (if `--wait` timed out)

```bash
sf package install report --request-id <0Hf...> --target-org <orgAlias>
```

### Verify the package is installed

```bash
sf package installed list --target-org <orgAlias>
```

Confirm that `kqexe` appears in the list with namespace `kqexe`.

---

## Step 2 — Run Post-Install Setup

After the package is installed, run the post-install script. This is a **single command** that handles everything — no manual steps are needed afterward.

```bash
node scripts/postInstall.js <orgAlias>
```

> **Prerequisites for this step:**
> - The `kqexe` managed package must already be installed (Step 1 must be complete).
> - `npm install` must have been run in the project root to install Node.js dependencies.
> - The org alias must be authenticated.

---

## What `postInstall.js` Does (7 Automated Steps)

### Preflight — Verify Package Installation

The script checks that the `kqexe` package is installed in the target org. If not found, it exits with instructions to install it first.

---

### Step 0 — Namespace-Transform Unpackaged Components

Reads all files from `force-app-unpackaged/` and writes namespace-transformed copies to a temporary directory. This is necessary because source files use bare names (no `kqexe__` prefix), while subscriber orgs require fully prefixed names.

Transformations applied:

| Source (as authored) | Deployed to subscriber org as |
|----------------------|-------------------------------|
| `Item__c`, `Vendor__r` (bare `__c`/`__r` names) | `kqexe__Item__c`, `kqexe__Vendor__r` |
| `<componentName>dynamicFieldCounter</componentName>` in FlexiPage | `kqexe:dynamicFieldCounter` |
| Layout filename `Order__c-Demand Order Layout.layout-meta.xml` | `kqexe__Order__c-Demand Order Layout.layout-meta.xml` |
| `<utilityBar>Spares_Planning_UtilityBar</utilityBar>` in App | Removed (referenced FlexiPage does not exist) |
| `<recordTypeVisibilities>` blocks in PermissionSet | Removed (can't deploy package RecordType references from outside the package) |
| `<externalCredentialPrincipalAccesses>` in PermissionSet | Removed (External Credential access is granted by the package's own permission set) |

---

### Step 1 — Deploy Unpackaged Components

Deploys the namespace-transformed metadata from the temp directory:

- `Spares_Planning` Lightning App
- `Item_Record_Page` FlexiPage
- `Lumen_Planning_Permission_Set_1` permission set
- Named Credentials (`Ketteq_API_Dev`, `Amazon_API_Endpoint` dev)
- Reports
- Layouts (all custom object layouts)

---

### Step 1b — Deploy Object Action Override

Deploys a namespace-transformed copy of `kqexe__Item__c` object metadata to set the **View** action on Item records to open the `Item_Record_Page` FlexiPage instead of the standard layout.

---

### Step 2 — Assign Permission Sets

Assigns **both** permission sets to the running user:

| Permission Set | Source |
|----------------|--------|
| `kqexe__Lumen_Planning_Permission_Set_1` | From the package — grants RecordType visibility required for data import |
| `Lumen_Planning_Permission_Set_1` | Unpackaged — grants tab access, additional field permissions, report access |

> If a permission set is already assigned, this step skips silently.

---

### Step 3 — Resolve RecordType IDs

Queries the target org for RecordType IDs (which are org-specific) and builds a remap table that translates source org IDs → target org IDs for use during data import.

RecordTypes resolved:

| Object | RecordType Developer Names |
|--------|---------------------------|
| `kqexe__Vendor__c` | `Repair_Vendor`, `Supplier` |
| `kqexe__Site__c` | `Depot`, `Warehouse` |
| `kqexe__Order__c` | `Demand_Order`, `Supply_Order` |

---

### Step 4 — Transform Data Files

Reads the source data files in `data/` and writes namespace-transformed copies to a temp directory:

- Adds `kqexe__` prefix to all custom sobject types and custom field names
- Remaps RecordType IDs from source values → target org values (using the remap built in Step 3)

---

### Step 5 — Import Sample Data

Imports 1,355+ records across 8 objects in dependency order:

| Object | Records |
|--------|---------|
| `kqexe__Vendor__c` | 61 |
| `kqexe__Customer__c` | 1 |
| `kqexe__Site__c` | 85 |
| `kqexe__Item__c` | 25 |
| `kqexe__Interchangeable_Part__c` | 5 |
| `kqexe__Item_Site__c` | 105 |
| `kqexe__Vendor_Pricing__c` | 33 |
| `kqexe__Order__c` | 1,005 |

Cross-object references are resolved automatically via `@referenceId` format during import.

---

### Step 6 — Open Org in Browser

Opens the target org in your default browser. If this fails, run manually:

```bash
sf org open --target-org <orgAlias>
```

---

## Post-Deployment Verification Steps

After `postInstall.js` completes, verify the following:

### 1. Confirm Installed Components

```bash
sf package installed list --target-org <orgAlias>
```

The `kqexe` package should appear with namespace `kqexe`.

### 2. Verify Permission Set Assignments

```bash
sf data query \
  -q "SELECT Assignee.Name, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE '%Lumen%'" \
  -o <orgAlias>
```

Both `kqexe__Lumen_Planning_Permission_Set_1` and `Lumen_Planning_Permission_Set_1` should appear for your user.

### 3. Verify Data Import

```bash
sf data query -q "SELECT COUNT() FROM kqexe__Item__c" -o <orgAlias>
sf data query -q "SELECT COUNT() FROM kqexe__Order__c" -o <orgAlias>
sf data query -q "SELECT COUNT() FROM kqexe__Vendor__c" -o <orgAlias>
```

Expected counts: 25 Items, 1,005 Orders, 61 Vendors.

### 4. Verify the App is Accessible

Navigate to the **Spares Planning** app in the org. All 8 tabs should be visible:
- Item, Vendor, Customer, Site, Item Site, Interchangeable Part, Vendor Pricing, Order

### 5. Verify Item Record Page

Open any Item record. The page should display the `Item_Record_Page` FlexiPage (containing the `dynamicFieldCounter` component), not the standard layout.

### 6. Verify RecordType Visibility

Open a Vendor, Site, or Order record. RecordTypes (`Repair_Vendor`/`Supplier`, `Depot`/`Warehouse`, `Demand_Order`/`Supply_Order`) should be visible and selectable.

---

## Upgrading to a Newer Version

Installing a newer version on an org that already has the package is an upgrade. Run the same commands:

```bash
# Install the newer version
sf package install --package <new-04t-id> --target-org <orgAlias> --wait 15

# Re-run post-install setup
node scripts/postInstall.js <orgAlias>
```

> Re-running `postInstall.js` on an existing install is safe — it re-deploys unpackaged components and re-assigns permission sets (idempotent). Data import may create duplicate records if run again on a populated org.

---

## Uninstalling the Package

```bash
sf package uninstall --package 04ta500000D9GKbAAN --target-org <orgAlias> --wait 10
```

> Uninstalling will remove all package objects and data. Unpackaged components (App, FlexiPage, Permission Set, Layouts) deployed by `postInstall.js` must be deleted manually if needed.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `The object type kqexe__Item__c is invalid` | Package not installed | Complete Step 1 (package install) before running `postInstall.js` |
| `no CustomObject named kqexe__Customer__c found` | Package not installed | Install the package first |
| `kqexe package is NOT installed in org` | `postInstall.js` preflight failed | Run `sf package install --package 04ta500000D9GKbAAN --target-org <alias> --wait 15` first |
| `Record Type ID: this ID value isn't valid for the user` | Running user missing `kqexe__Lumen_Planning_Permission_Set_1` before data import | `postInstall.js` Step 2 assigns both permission sets — ensure it ran successfully |
| `Unable to create/update fields: kqexe__Days_At_Vendor__c` | `Days_At_Vendor__c` is a formula field — cannot be inserted | Remove this field from `data/order-Order__c.json` |
| `We couldn't process your request because you don't have access to kqexe__<Field>__c` | FlexiPage or data file references a field removed from the package version | Remove the field from the FlexiPage XML in `force-app-unpackaged/flexipages/` and/or from the relevant `data/*.json` |
| `We couldn't retrieve the design time component information for component c:dynamicFieldCounter` | LWC namespace prefix not transformed | `postInstall.js` transforms this automatically — ensure you are running the latest version of the script |
| `no FlexiPage named Spares_Planning_UtilityBar found` | App XML references a non-existent utility bar | `postInstall.js` strips this reference automatically |
| `invalid cross reference id` on PermissionSet deploy | PermissionSet references External Credential principal from outside the package | `postInstall.js` strips `externalCredentialPrincipalAccesses` automatically |
| `Duplicate PermissionSetAssignment` | Permission set already assigned to the user | Safe to ignore — `postInstall.js` handles this gracefully |
| Layout deploy fails with `no CustomObject` error | Layout filename not renamed with `kqexe__` prefix | `postInstall.js` renames layouts automatically (`Order__c-` → `kqexe__Order__c-`) |
| `sf org login` required | Org not authenticated | Run `sf org login web --alias <alias>` before proceeding |
| `node: command not found` | Node.js not installed | Install Node.js ≥ 18 and re-run |
| `python: command not found` | Python not installed or not in PATH | Install Python ≥ 3.9 and ensure it's in PATH; try `python3` on macOS/Linux |

---

## Quick Reference

| Task | Command |
|------|---------|
| Install package | `sf package install --package 04ta500000D9GKbAAN --target-org <org> --wait 15` |
| Run post-install setup | `node scripts/postInstall.js <org>` |
| Verify installation | `sf package installed list --target-org <org>` |
| Open org | `sf org open --target-org <org>` |
| Check data counts | `sf data query -q "SELECT COUNT() FROM kqexe__Item__c" -o <org>` |
| Uninstall | `sf package uninstall --package 04ta500000D9GKbAAN --target-org <org> --wait 10` |
