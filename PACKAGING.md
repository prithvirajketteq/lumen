# Lumen — 2GP Managed Package Guide

This guide covers the full lifecycle of the Lumen managed 2GP package: building versions, promoting them to release, installing, and running the post-install setup.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Salesforce CLI (`sf`) ≥ 2.x | `sf --version` |
| Node.js | ≥ 18 |
| Python | ≥ 3.9 |
| Dev Hub org | `lumenProd` — already configured with **Second-Generation Managed Packages** enabled |
| Namespace linked | `kqexe` namespace is registered and linked to `lumenProd` Dev Hub |
| `sfdx-project.json` | Already configured — `packageDirectories` points to `force-app`, package ID `0Hoa50000002vBtCAI` |

> `"namespace"` is intentionally **omitted** from `sfdx-project.json` for scratch org development. SF CLI's `NamespaceRegistryValidator` would otherwise fail if the Dev Hub cannot resolve the namespace. The namespace is only needed when running `sf package version create` — add it back then if required.

> The package (`kqexe`, ID `0Hoa50000002vBtCAI`) is registered and versions exist. **Skip Step 1** unless setting up in a brand-new Dev Hub.

---

## Scratch Org Setup (Developer Workflow)

Use this when you need a fresh developer scratch org for building or testing — not for subscriber installs.

### One-command setup

```bash
npm run retrieve -- kqexpkg
npm run org:init                                 # auto-alias: lumenScratch-1, lumenScratch-2, ...
node scripts/orgInit.js myAlias                  # custom alias
node scripts/orgInit.js myAlias devhub@acme.com  # custom alias + dev hub
```

No manual steps required after the script completes. The sections below document what each step does and the equivalent manual commands.

---

### Step 1 — Create the scratch org

`orgInit.js` creates a 30-day scratch org from `config/project-scratch-def.json` and sets it as the default org.

```bash
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias lumenScratch \
  --duration-days 30 \
  --set-default
```

> **Dev Hub:** Defaults to whichever Dev Hub is currently set as default. Pass `--target-dev-hub lumenProd` to target a specific one, or supply it as the third argument to `orgInit.js`.

> **Namespace error:** If you see `NamespaceRegistryValidator threw an unhandled exception`, ensure `"namespace"` is **not** present in `sfdx-project.json`. See the Prerequisites note above.

---

### Step 2 — Deploy packaged source (`force-app/`)

Deploys all metadata in the 2GP package directory: custom objects, fields, Apex classes, Apex triggers, LWC components, custom metadata records, permission sets, and named credentials.

```bash
sf project deploy start \
  --source-dir force-app \
  --target-org lumenScratch
```

In a scratch org, names are bare (no `kqexe__` prefix) — `Item__c`, `dynamicFieldCounter`, etc.

---

### Step 3 — Deploy unpackaged metadata (`force-app-unpackaged/`)

Deploys metadata that lives outside the package: the Spares Planning Lightning App, Item Record Page FlexiPage, layouts, named credentials, reports, and the Admin profile (which sets layout assignments, record type visibilities, and app visibility).

```bash
sf project deploy start \
  --source-dir force-app-unpackaged \
  --target-org lumenScratch
```

No namespace transformation is applied in a scratch org — files are deployed as-is with bare names.

---

### Step 4 — Assign permission set

Assigns `Lumen_Planning_Permission_Set_1` to the running user so they can access all tabs, fields, and record types.

```bash
sf org assign permset \
  --name Lumen_Planning_Permission_Set_1 \
  --target-org lumenScratch
```

> If the permission set is not found `orgInit.js` logs a warning and continues — assign manually if needed.

---

### Step 5 — Resolve RecordType IDs and import sample data

RecordType IDs are org-specific and change with every new scratch org. `fixRecordTypes.py` queries the target org's RecordType IDs by `DeveloperName` and patches the data files in-place before import.

```bash
# Resolve org-specific RecordType IDs into data files
python scripts/fixRecordTypes.py lumenScratch

# Import 1,355+ records across 8 objects in dependency order
sf data import tree \
  --plan data/data-plan.json \
  --target-org lumenScratch
```

Objects imported (in order): `Vendor__c` (61), `Customer__c` (1), `Site__c` (85), `Item__c` (25), `Interchangeable_Part__c` (5), `Item_Site__c` (105), `Vendor_Pricing__c` (33), `Order__c` (1005).

Objects with RecordTypes: `Vendor__c` (Repair_Vendor, Supplier), `Site__c` (Depot, Warehouse), `Order__c` (Demand_Order, Supply_Order).

---

### Step 6 — Open the org

```bash
sf org open --target-org lumenScratch
```

---

### What lives where in a scratch org

| Component | Source | Notes |
|---|---|---|
| Custom objects, Apex, LWC, triggers | `force-app/` | Bare names — no `kqexe__` prefix in developer org |
| FlexiPage, App, Layouts, Reports, Named Credentials | `force-app-unpackaged/` | Deployed as-is (no namespace transform needed in developer org) |
| Profiles | `force-app-unpackaged/profiles/Admin.profile-meta.xml` | Sets layout assignments + record type visibilities + app visibility |
| Sample data | `data/` | 1,355+ records; RecordType IDs resolved per org at import time |

### Delete a scratch org

```bash
sf org delete scratch --no-prompt --target-org lumenScratch
```

---

## Step 1 — Create the Package (one-time setup, already done)

This registers the package in the Dev Hub and writes its `0Ho` ID into `sfdx-project.json`. **Skip if `packageAliases` already contains `"kqexe"`.**

```bash
sf package create --name "kqexe" --package-type Managed --path force-app --target-dev-hub lumenProd
```

> **Namespace constraint:** The `kqexe` namespace is permanently tied to package `0Hoa50000002vBtCAI`. You cannot create a second managed package with the same namespace in the same Dev Hub. To start a fresh version lineage with no upgrade constraints from prior released versions, set `ancestorVersion: NONE` in `sfdx-project.json` and use `--skip-ancestor-check` when creating versions.

---

## Step 2 — Pre-Flight Checklist (do this before every version create)

Run through these checks before running `sf package version create`.

> **Most pre-flight cleanup is now automated.** Running `bash scripts/createPackageVersion.sh` executes `node scripts/sortComponents.js` as Step 0, which automatically:
> - Moves FlexiPages, layouts (custom objects), reports, Named Credentials, and Permission Sets from `force-app/` → `force-app-unpackaged/`
> - Strips any `<type>Flexipage</type>` actionOverrides from all object XML in `force-app/`
>
> You only need to perform the manual checks below.

### 2a — Bump the version number

If the previous version is already released, the `versionNumber` in `sfdx-project.json` must be higher than the latest released version. Use `.NEXT` to let Salesforce auto-increment the patch build:

```json
"versionNumber": "5.0.0.NEXT"
```

If `5.0.0.x` is already released, move to `6.0.0.NEXT`, and so on.

Also update `versionName` to reflect the release (e.g. `"ver 5.0 Mar 2026"`).

### 2b — Set ancestor

- `ancestorVersion: NONE` — fresh lineage, no upgrade path from prior released versions. Use `--skip-ancestor-check` on the create command.
- `ancestorVersion: HIGHEST` — maintains an upgrade chain from the latest released version.

### 2c — Verify Apex tests locally (optional but saves daily quota)

Before creating a version, confirm all Apex tests pass in a connected scratch org. Each version create attempt consumes one of the ~6 daily quota slots per Dev Hub.

---

## Step 3 — Create a Package Version

Use the script — it runs `sortComponents.js` first (auto-sorts force-app), then creates the version:

```bash
bash scripts/createPackageVersion.sh [devHubAlias]
# default dev hub: lumenProd
```

Or run manually (after running `node scripts/sortComponents.js`):

```bash
sf package version create \
  --package kqexe \
  --installation-key-bypass \
  --skip-ancestor-check \
  --code-coverage \
  --wait 30 \
  --target-dev-hub lumenProd
```

| Flag | Purpose |
|---|---|
| `--installation-key-bypass` | Skips password protection |
| `--skip-ancestor-check` | Required when `ancestorVersion: NONE` and released versions already exist |
| `--code-coverage` | Enforces ≥ 75% Apex test coverage — **required for promotion** |
| `--wait 30` | Waits up to 30 min for the build; increase if it times out |

On success the CLI prints the new `04t...` subscriber package version ID and updates `packageAliases` in `sfdx-project.json`. **Commit `sfdx-project.json` after each version.**

> **Do NOT use `--skip-validation`** — versions created that way cannot be promoted to Released.

> **Daily limit:** Salesforce allows only ~6 package version creates per 24 hours per Dev Hub.

### Check version creation status (if you did not use `--wait`)

```bash
sf package version create report --package-create-request-id <08c...> --target-dev-hub lumenProd
```

---

## Step 4 — List All Versions

```bash
sf package version list --target-dev-hub lumenProd
```

Add `--verbose` to see subscriber version IDs (`04t...`), code coverage, and ancestor info.

---

## Step 5 — Promote a Version to Released

Versions start as **Beta** — installable in scratch orgs and sandboxes without promotion. Promote to **Released** only when stable and ready for production.

> **Promotion is permanent.** A released version cannot be deleted or modified. Upgrade constraints apply from this point forward.

```bash
sf package version promote --package <04t-id> --target-dev-hub lumenProd --no-prompt
```

---

## Step 6 — Install a Package Version

### Into a scratch org or sandbox (Beta or Released)

```bash
sf package install --package <04t-id> --target-org <orgAlias> --wait 15
```

### Into a production org (Released only)

```bash
sf package install --package <04t-id> --target-org <orgAlias> --wait 15
```

### Check installation status (if you did not use `--wait`)

```bash
sf package install report --request-id <0Hf...> --target-org <orgAlias>
```

---

## Step 7 — Run Post-Install Setup

After the package is installed, run the post-install script:

```bash
node scripts/postInstall.js <orgAlias>
```

The script performs these steps in order:

### Step 0 — Prepare namespaced unpackaged components

Reads `force-app-unpackaged/` (applications, flexipages, permissionsets) and writes namespace-transformed copies to a temp directory. Transformations applied:

- All bare custom API names (`Item__c`, `Vendor__r`, etc.) are prefixed with `kqexe__`
- LWC component names in FlexiPages are prefixed with the package namespace (`dynamicFieldCounter` → `kqexe:dynamicFieldCounter`)
- `<utilityBar>` reference to the non-existent `Spares_Planning_UtilityBar` is stripped from the App
- `<recordTypeVisibilities>` blocks are stripped from the PermissionSet (package RecordTypes can't be referenced from outside the package in deployment)
- `<externalCredentialPrincipalAccesses>` is stripped from the PermissionSet (External Credential principal access must be granted via the package's own permission set)

### Step 1 — Deploy unpackaged components

Deploys the namespace-transformed unpackaged metadata: `Spares_Planning` app, `Item_Record_Page` FlexiPage, `Lumen_Planning_Permission_Set_1`.

### Step 1b — Deploy object action overrides

Builds a namespaced copy of `force-app-unpackaged/objects/Item__c/Item__c.object-meta.xml` (adds `kqexe__` prefixes to all references) and deploys it so the View action on `kqexe__Item__c` records opens `Item_Record_Page`.

### Step 2 — Assign permission sets

Assigns **both** permission sets to the running user:
1. `kqexe__Lumen_Planning_Permission_Set_1` — the package's own PS; grants RecordType visibility needed for data import
2. `Lumen_Planning_Permission_Set_1` — the unpackaged PS; grants additional tab/field access

### Step 3 — Resolve RecordType IDs

Queries `kqexe` namespace RecordTypes in the target org and builds a source-ID → target-ID remap table used during data transformation.

### Step 4 — Transform data files

Reads `data/*.json`, adds `kqexe__` prefix to all custom sobject types and field names, remaps RecordType IDs to the target org values. Writes transformed files to a temp directory.

### Step 5 — Import data

Runs `sf data import tree` with the transformed plan. Imports 1,355+ records across 8 objects (Vendor, Customer, Site, Item, Interchangeable_Part, Item_Site, Vendor_Pricing, Order).

### Pre-flight checks before running postInstall.js

Before running, verify:
- The `kqexe` package is installed in the org (`sf package installed list --target-org <orgAlias>`)
- `force-app-unpackaged/flexipages/` FlexiPages do not reference fields removed from the package
- `data/order-Order__c.json` does not contain formula fields or fields that no longer exist in the package (e.g. `Days_At_Vendor__c` is a formula field — do not include it)

### What postInstall.js automates (no manual steps required)

`postInstall.js` handles the entire post-install setup end-to-end:

| Step | What happens |
|---|---|
| Step 0 | Namespace-transforms all `force-app-unpackaged/` components: prefixes `__c`/`__r` names with `kqexe__`, renames layout files (`Order__c-` → `kqexe__Order__c-`), prefixes LWC names in FlexiPage (`c:foo` → `kqexe:foo`) |
| Step 1 | Deploys: App, FlexiPage, Permission Set, Named Credentials, Reports, Layouts |
| Step 1b | Deploys `kqexe__Item__c` action override (View → Item_Record_Page) |
| Step 2 | Assigns `kqexe__Lumen_Planning_Permission_Set_1` + `Lumen_Planning_Permission_Set_1` to running user |
| Step 3 | Deploys `Admin` profile: layout assignments (all objects), record type visibilities (Order/Site/Vendor), Spares Planning app visibility |
| Step 4–6 | Resolves RecordType IDs → transforms data → imports 1,355+ records |

There are no remaining manual steps after `node scripts/postInstall.js <orgAlias>`.

---

## Step 8 — Upgrade to a Newer Version

Installing a newer version on an org that already has the package is an upgrade — run the same install command with the new version ID:

```bash
sf package install --package <new-04t-id> --target-org <orgAlias> --wait 15
node scripts/postInstall.js <orgAlias>
```

---

## Step 9 — Verify Installation

```bash
sf package installed list --target-org <orgAlias>
```

---

## Current Released Version

Latest release: **5.0.0.1** (`04ta500000D9GKbAAN`) — installed on `kqlumenuat` ✓

**Option A — Browser:**
```
https://login.salesforce.com/packaging/installPackage.apexp?p0=04ta500000D9GKbAAN
```

**Option B — CLI:**
```bash
sf package install --package 04ta500000D9GKbAAN --target-org <orgAlias> --wait 15
node scripts/postInstall.js <orgAlias>
# That's it — no manual steps required.
```

---

## Typical Release Workflow (next time)

```
1. [ code changes ] → git commit → git push

2. Pre-flight checks:
   a. Bump versionNumber in sfdx-project.json if previous version is already released
      (e.g. 5.0.0.NEXT → 6.0.0.NEXT)
   b. Verify all Apex tests pass — test assertions must match current constant values
   c. Verify data files don't include formula fields or renamed/removed fields

   Note: Flexipage actionOverride cleanup and moving unpackaged components
   (layouts, reports, namedCredentials, flexipages, permissionsets) out of
   force-app/ is handled automatically by scripts/sortComponents.js, which
   runs as Step 0 of createPackageVersion.sh.

3. Create version (runs sortComponents.js automatically as Step 0):
   bash scripts/createPackageVersion.sh [devHubAlias]

4. Commit sfdx-project.json (CLI updates packageAliases automatically):
   git add sfdx-project.json && git commit -m "chore: add package version alias <version>"

5. Test the beta version:
   sf package install --package <04t-id> --target-org <scratchOrgAlias> --wait 15
   node scripts/postInstall.js <scratchOrgAlias>
   # No manual steps required — postInstall.js handles everything.

6. Promote when ready:
   sf package version promote --package <04t-id> --target-dev-hub lumenProd --no-prompt

7. Install in subscriber orgs:
   sf package install --package <04t-id> --target-org <targetOrgAlias> --wait 15
   node scripts/postInstall.js <targetOrgAlias>
   # No manual steps required — postInstall.js handles everything.

8. Update "Current Released Version" section in this file.
```

---

## sfdx-project.json Reference

Current configuration (fresh-start versioning, no upgrade path from prior versions):

```json
{
  "packageDirectories": [
    {
      "path": "force-app",
      "package": "kqexe",
      "versionName": "ver 5.0 Mar 2026",
      "versionNumber": "5.0.0.NEXT",
      "ancestorVersion": "NONE"
    }
  ],
  "packageAliases": {
    "kqexe": "0Hoa50000002vBtCAI",
    "kqexe@4.0.0-1": "04ta500000D2PPRAA3",
    "kqexe@4.0.0-2": "04ta500000D2PR3AAN",
    "kqexe@5.0.0-1": "04ta500000D9GKbAAN"
  }
}
```

| Field | Purpose |
|---|---|
| `versionNumber` | Use `.NEXT` to let Salesforce auto-increment the patch build number |
| `ancestorVersion` | `NONE` = fresh start, no upgrade constraints. Use `HIGHEST` to maintain an upgrade chain from the latest released version |
| `--skip-ancestor-check` | CLI flag required when `ancestorVersion: NONE` and released versions already exist |
| `"namespace"` | **Omitted** from `sfdx-project.json` — add `"namespace": "kqexe"` only when running `sf package version create`. Leaving it in causes `NamespaceRegistryValidator` failures during scratch org creation if the Dev Hub cannot resolve the namespace. |

---

## What Lives Where

| Location | Contents | Notes |
|---|---|---|
| `force-app/` | Package source | Deployed as part of the managed package. Never add FlexiPages, Layouts (custom objects), Named Credentials, Reports, or Permission Sets here — `sortComponents.js` will move them to `force-app-unpackaged/` automatically. |
| `force-app-unpackaged/` | Post-install additions | App, FlexiPages, Layouts, Named Credentials, Reports, Permission Set (full, with external credential access), Profiles (layout assignments, record type visibilities, app visibility). Deployed by `postInstall.js` after package install with automatic `kqexe__` namespace transformation. |
| `manifest/package-unpackaged.xml` | Manifest for unpackaged components | Used to retrieve unpackaged metadata from an org. |
| `data/` | Sample data for import | Referenced by `postInstall.js` Step 5. Must not contain formula fields or fields removed from the current package version. |

---

## How postInstall.js Handles Subscriber Org Namespace Differences

The source files in `force-app-unpackaged/` use bare names (no `kqexe__` prefix) because they were authored in the developer org where the namespace is active and both `Item__c` and `kqexe__Item__c` resolve to the same object. In subscriber orgs, only the prefixed names work.

`postInstall.js` bridges this gap automatically:

| Problem | Transform applied |
|---|---|
| `<object>Customer__c</object>` in PermissionSet | → `kqexe__Customer__c` |
| `<sobjectType>Item__c</sobjectType>` in FlexiPage | → `kqexe__Item__c` |
| `<componentName>dynamicFieldCounter</componentName>` in FlexiPage | → `kqexe:dynamicFieldCounter` |
| `<tabs>Item__c</tabs>` in App | → `kqexe__Item__c` |
| `<utilityBar>Spares_Planning_UtilityBar</utilityBar>` | removed (FlexiPage doesn't exist) |
| `<recordTypeVisibilities>` in PermissionSet | removed (can't reference package RecordTypes from outside the package) |
| `<externalCredentialPrincipalAccesses>` in PermissionSet | removed (can't grant package External Credential access from outside the package) |
| Layout filename `Order__c-Demand Order Layout.layout-meta.xml` | renamed → `kqexe__Order__c-Demand Order Layout.layout-meta.xml` |
| `<field>Item__c.Failure_Rate__c</field>` in Report | → `kqexe__Item__c.kqexe__Failure_Rate__c` |
| `<reportType>CustomEntity$Item__c</reportType>` in Report | → `CustomEntity$kqexe__Item__c` |
| `<recordType>Order__c.Demand_Order</recordType>` in Profile | → `kqexe__Order__c.Demand_Order` |
| `<layout>Order__c-Demand Order Layout</layout>` in Profile | → `kqexe__Order__c-Demand Order Layout` |

RecordType visibility and External Credential access are granted by the package's own permission set (`kqexe__Lumen_Planning_Permission_Set_1`), which is assigned in Step 2.

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `reached its daily limit` | Max ~6 version creates/day per Dev Hub | Wait until midnight UTC |
| `ErrorAncestorNoneNotAllowedError` | `ancestorVersion: NONE` but released versions exist | Add `--skip-ancestor-check` to the create command |
| `ErrorAncestorNotHighestError` | Ancestor version is not the latest released | Use `ancestorVersion: HIGHEST` or bump to a higher version number |
| `a released package version with version number X.Y.Z already exists` | Version number not bumped | Increment `versionNumber` in `sfdx-project.json` (e.g. `4.0.0.NEXT` → `5.0.0.NEXT`) |
| `Item__c: Item_Record_Page does not exist or is not a valid override` | Packaged object file has a FlexiPage action override | Remove the `<type>Flexipage</type>` `<actionOverrides>` blocks from the object XML; keep only `<type>Default</type>` |
| `Lumen_Planning_Permission_Set_1: invalid cross reference id` | Packaged permission set references a Named Credential not in the package | Remove `<externalCredentialPrincipalAccesses>` block from `force-app/.../Lumen_Planning_Permission_Set_1.permissionset-meta.xml` |
| `Apex Test Failure: AppConstantsTest ... Expected: Dispo_, Actual: Disposition_` | Test assertion stale after constant rename | Update the expected value in `AppConstantsTest.cls` to match the current constant in `AppConstants.cls` |
| `Can't promote this package version because it was created without validation` | Version was created with `--skip-validation` | Re-create the version without that flag (and with `--code-coverage`) |
| `Code coverage has not been run for this version` | Version created without `--code-coverage` | Re-create the version with `--code-coverage` |
| `The given ancestorVersion is not in the correct format` | Wrong format for `ancestorVersion` | Use dot notation `1.0.0.LATEST`, not dash `1.0.0-2` |
| `The object type you specified Item__c is invalid` (FlexiPage deploy) | FlexiPage `<sobjectType>` not namespaced for subscriber org | `postInstall.js` handles this automatically via namespace transform |
| `no CustomObject named Customer__c found` (PermissionSet deploy) | PermissionSet uses bare names in subscriber org | `postInstall.js` handles this automatically via namespace transform |
| `no FlexiPage named Spares_Planning_UtilityBar found` (App deploy) | App references a non-existent utility bar FlexiPage | `postInstall.js` strips this reference automatically |
| `invalid cross reference id` (PermissionSet deploy to subscriber org) | PermissionSet references package External Credential principal | `postInstall.js` strips `<externalCredentialPrincipalAccesses>` automatically |
| `We couldn't retrieve the design time component information for component c:dynamicFieldCounter` | FlexiPage LWC component uses `c:` namespace prefix instead of `kqexe:` | `postInstall.js` transforms component names automatically |
| `Record Type ID: this ID value isn't valid for the user` | User missing package permission set (`kqexe__Lumen_Planning_Permission_Set_1`) before data import | `postInstall.js` assigns both permission sets in Step 2 — ensure it runs before data import |
| `Unable to create/update fields: kqexe__Days_At_Vendor__c` | `Days_At_Vendor__c` is a formula field — can't be inserted via DML | Remove `Days_At_Vendor__c` from `data/order-Order__c.json` |
| `We couldn't process your request because you don't have access to kqexe__<Field>__c` | Data file or FlexiPage references a field removed from the current package version | Remove the field from the FlexiPage XML in `force-app-unpackaged/flexipages/` and/or from the relevant `data/*.json` file |
| `The object type kqexe__Item__c is invalid` | Package not installed in target org | Run `sf package install` before `postInstall.js` |
| `no CustomObject named kqexe__Customer__c found` | Package not installed | Install the package first |
| `Duplicate PermissionSetAssignment` | Permission set already assigned | Safe to ignore — `postInstall.js` handles this gracefully |
| `entity type cannot be inserted: Package` | Wrong Dev Hub user or 2GP not enabled for that user | Use `--target-dev-hub lumenProd` (not `lumenDevHub`) |

---

## Uninstall a Package

```bash
sf package uninstall --package <04t-id> --target-org <orgAlias> --wait 10
```

---

## Quick Reference

| Task | Command |
|---|---|
| Create version | `sf package version create --package kqexe --installation-key-bypass --skip-ancestor-check --code-coverage --wait 30 --target-dev-hub lumenProd` |
| List versions | `sf package version list --target-dev-hub lumenProd` |
| Promote version | `sf package version promote --package <04t-id> --target-dev-hub lumenProd --no-prompt` |
| Install | `sf package install --package <04t-id> --target-org <org> --wait 15` |
| Post-install setup | `node scripts/postInstall.js <org>` |
| Deploy unpackaged only | `sf project deploy start --source-dir force-app-unpackaged --target-org <org>` |
| List installed | `sf package installed list --target-org <org>` |
| Uninstall | `sf package uninstall --package <04t-id> --target-org <org> --wait 10` |
