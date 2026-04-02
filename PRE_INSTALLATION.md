# Lumen — Pre-Installation Guide

This guide covers everything that must happen **before** installing the `kqexe` managed package into a subscriber org — from retrieving the latest metadata to building, validating, and promoting a new package version.

Skip to [Quick Reference](#quick-reference) if you already know the process.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Salesforce CLI (`sf`) ≥ 2.x | `sf --version` to verify |
| Node.js ≥ 18 | `node --version` to verify |
| Python ≥ 3.9 | `python --version` to verify |
| Dev Hub org: `lumenProd` | Must be authenticated and have Second-Generation Managed Packages enabled |
| Namespace `kqexe` | Registered and linked to `lumenProd` Dev Hub |
| Package ID | `0Hoa50000002vBtCAI` (already in `sfdx-project.json`) |

### Authenticate the Dev Hub

```bash
sf org login web --alias lumenProd --set-default-dev-hub
```

Verify the connection:

```bash
sf org display --target-org lumenProd
```

---

## Step 1 — Retrieve Latest Metadata from Source Org

Always retrieve fresh metadata before creating a package version. This ensures local files match what is deployed in the source/packaging org (`kqexpkg`).

```powershell
powershell -ExecutionPolicy Bypass -File scripts/retrieve-all.ps1 -OrgAlias kqexpkg
```

**What this script does:**

| Step | Action |
|------|--------|
| 1 | Verifies connection to `kqexpkg` |
| 2 | Prompts for safety confirmation before deleting local files |
| 3 | Clears `force-app/main/default/` and `force-app-unpackaged/main/default/` |
| 4 | Sets `force-app` as default in `sfdx-project.json`, retrieves managed package components via `manifest/package.xml` |
| 5 | Sets `force-app-unpackaged` as default, retrieves unpackaged components via `manifest/unpackaged.xml` |
| 6 | Restores `sfdx-project.json` defaults |
| 7 | Strips `<type>Flexipage</type>` action overrides from `Item__c` object XML |
| 8 | Strips `externalCredentialPrincipalAccesses` from the PermissionSet |
| 9 | Removes `AttachedContentNotes` region from `Item_Record_Page` FlexiPage |

> Type `y` when prompted to confirm deletion of local files.

---

## Step 2 — Update Version Number in `sfdx-project.json`

If the previous package version is already **Released**, the version number in `sfdx-project.json` must be higher than the latest released version.

Open `sfdx-project.json` and update the `versionNumber` and `versionName` fields:

```json
{
  "packageDirectories": [
    {
      "path": "force-app",
      "package": "kqexe",
      "versionName": "ver 6.0 Apr 2026",
      "versionNumber": "6.0.0.NEXT",
      "ancestorVersion": "NONE"
    }
  ]
}
```

| Field | Rule |
|-------|------|
| `versionNumber` | Must be higher than the latest released version. Use `.NEXT` to let Salesforce auto-increment the patch build number. |
| `versionName` | Human-readable label (e.g. `"ver 6.0 Apr 2026"`). Update it to reflect the release. |
| `ancestorVersion` | `NONE` = fresh lineage, no upgrade path from prior versions (requires `--skip-ancestor-check`). `HIGHEST` = maintains upgrade chain from latest released version. |

**Current released versions** (from `sfdx-project.json`):

| Alias | Subscriber Package Version ID |
|-------|-------------------------------|
| `kqexe@4.0.0-1` | `04ta500000D2PPRAA3` |
| `kqexe@4.0.0-2` | `04ta500000D2PR3AAN` |
| `kqexe@5.0.0-1` | `04ta500000D9GKbAAN` ← latest released |

> **Note:** `"namespace"` is intentionally omitted from `sfdx-project.json`. Adding it causes `NamespaceRegistryValidator` failures during scratch org creation. The namespace is baked into the package definition — it does not need to be declared in this file.

---

## Step 3 — Verify the Data Files

Before creating a package version, ensure the sample data files in `data/` are clean:

1. **No formula fields** — Formula fields cannot be inserted via DML. For example, `Days_At_Vendor__c` on `Order__c` is a formula field and must not appear in `data/order-Order__c.json`.
2. **No removed/renamed fields** — If a field was removed from the package, remove it from the data files and from any FlexiPage XML in `force-app-unpackaged/flexipages/`.

```bash
# Quick check: scan data files for known formula fields
grep -r "Days_At_Vendor__c" data/
```

---

## Step 4 — Verify Apex Tests Locally (Optional but Recommended)

Each package version create attempt consumes one of approximately **6 daily quota slots** per Dev Hub. Verifying tests in a connected scratch org first saves quota if there are failures.

```bash
# Run all Apex tests in a scratch org
sf apex run test -o lumenScratch --wait 10 --result-format human

# Run LWC Jest tests locally
npm test
```

All tests must pass before proceeding. Apex tests use `TestDataFactory` for fixtures and `MockAmazonCallout` for HTTP mocks.

> **Note:** If Apex test assertions reference string constants, verify they match the current values in `AppConstants.cls`. A common failure is `AppConstantsTest` failing because a constant was renamed.

---

## Step 5 — Create the Package Version

The `createPackageVersion.sh` script handles all pre-packaging steps automatically (including Step 6 below) and then creates the version.

```bash
bash scripts/createPackageVersion.sh
# With a specific Dev Hub:
bash scripts/createPackageVersion.sh lumenProd
```

**What this script does:**

| Step | Action |
|------|--------|
| 0 | Runs `node scripts/sortComponents.js` — automatically moves unpackaged metadata out of `force-app/` and cleans object XML |
| 1 | Runs `sf package version create` — compiles Apex, runs all Apex tests, enforces ≥ 75% code coverage (~10-20 min) |
| 2 | Parses the output and prints the new `04t...` Subscriber Package Version ID and install URL |
| 3 | Asks whether to promote to Released immediately |

> **Do NOT use `--skip-validation`** — versions created with that flag cannot be promoted to Released.

### To run manually (after `sortComponents.js`):

```bash
node scripts/sortComponents.js

sf package version create \
  --package kqexe \
  --installation-key-bypass \
  --skip-ancestor-check \
  --code-coverage \
  --wait 30 \
  --target-dev-hub lumenProd
```

| Flag | Purpose |
|------|---------|
| `--installation-key-bypass` | No password required for installation |
| `--skip-ancestor-check` | Required when `ancestorVersion: NONE` and released versions already exist |
| `--code-coverage` | Enforces ≥ 75% Apex test coverage — required for promotion to Released |
| `--wait 30` | Waits up to 30 minutes for the build; increase if it times out |

### Check version creation status (if `--wait` timed out):

```bash
sf package version create report \
  --package-create-request-id <08c...> \
  --target-dev-hub lumenProd
```

On success, the CLI prints the `04t...` version ID and **automatically updates `packageAliases` in `sfdx-project.json`**. Commit that file:

```bash
git add sfdx-project.json
git commit -m "chore: add package version alias <version>"
```

---

## Step 6 — What `sortComponents.js` Cleans (Automated by Step 5)

`sortComponents.js` runs automatically as Step 0 of `createPackageVersion.sh`. It ensures the correct separation between packaged and unpackaged metadata before the version is built.

**Directories moved from `force-app/` → `force-app-unpackaged/`:**

| Metadata Type | Why it must be outside the package |
|---------------|------------------------------------|
| `flexipages/` | FlexiPage action overrides on packaged objects cause deploy failures |
| `reports/` | Reports reference org-specific folders; cannot be part of the package |
| `namedCredentials/` | Dev-only credentials must not be distributed in the package |
| `permissionsets/` | The unpackaged PermissionSet grants access beyond package scope |
| Layouts (`*__c-*.layout-meta.xml`) | Custom object layouts reference unpackaged fields and apps |

**Cleaning applied to `force-app/` object XML:**

- Removes all `<actionOverrides>` blocks containing `<type>Flexipage</type>` — these reference the `Item_Record_Page` FlexiPage which lives outside the package. The override is re-applied post-install by `postInstall.js`.

**Cleaning applied to `force-app-unpackaged/flexipages/`:**

- Removes `<visibilityRule>` blocks that reference non-package fields (e.g. `Count_of_Child_Items__c`) — these fields exist in the developer org but are not part of the managed package, causing FlexiPage deploy failures in subscriber orgs.

---

## Step 7 — Test the Beta Version (Before Promoting)

Before promoting to Released, install the **Beta** version in a scratch org or sandbox and run `postInstall.js` to verify the full end-to-end setup.

```bash
# Install the beta version
sf package install --package <04t-id> --target-org <scratchOrgAlias> --wait 15

# Run full post-install setup
node scripts/postInstall.js <scratchOrgAlias>
```

Verify:
- All 8 custom object tabs are visible in the Spares Planning app
- Item records open the `Item_Record_Page` FlexiPage
- All 1,355+ sample records imported successfully
- RecordType picklists work on Vendor, Site, and Order records
- The `dynamicFieldCounter` LWC component renders on the Item Record Page

> Beta versions can be installed in scratch orgs and sandboxes. They cannot be installed in production orgs.

---

## Step 8 — Promote to Released

Promotion is **permanent** — a released version cannot be deleted or modified.

```bash
sf package version promote \
  --package <04t-id> \
  --target-dev-hub lumenProd \
  --no-prompt
```

> The `createPackageVersion.sh` script prompts for promotion automatically after creating the version.

After promotion, the package version can be installed in **production orgs**.

---

## Step 9 — List All Versions

```bash
sf package version list --target-dev-hub lumenProd
# With full details:
sf package version list --target-dev-hub lumenProd --verbose
```

This shows version numbers, Subscriber Package Version IDs (`04t...`), promotion status, code coverage, and ancestor info.

---

## Pre-Installation Checklist

Run through this checklist before every package version create:

- [ ] Dev Hub `lumenProd` is authenticated: `sf org display --target-org lumenProd`
- [ ] Latest metadata retrieved from `kqexpkg` via `retrieve-all.ps1`
- [ ] `versionNumber` in `sfdx-project.json` is higher than the latest released version
- [ ] `versionName` in `sfdx-project.json` is updated (e.g. `"ver 6.0 Apr 2026"`)
- [ ] No formula fields in `data/*.json` (e.g. `Days_At_Vendor__c` removed from `order-Order__c.json`)
- [ ] No removed/renamed package fields in `force-app-unpackaged/flexipages/` or `data/` files
- [ ] All Apex tests pass in a connected scratch org: `sf apex run test -o lumenScratch --wait 10`
- [ ] All LWC Jest tests pass: `npm test`
- [ ] Beta version tested end-to-end in a scratch org before promoting

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `reached its daily limit` | Max ~6 version creates per 24 hours per Dev Hub | Wait until midnight UTC before retrying |
| `ErrorAncestorNoneNotAllowedError` | `ancestorVersion: NONE` but released versions already exist | Add `--skip-ancestor-check` to the create command |
| `ErrorAncestorNotHighestError` | Ancestor version is not the latest released | Use `ancestorVersion: HIGHEST` or bump to a higher version number |
| `a released package version with version number X.Y.Z already exists` | `versionNumber` not bumped | Increment in `sfdx-project.json` (e.g. `5.0.0.NEXT` → `6.0.0.NEXT`) |
| `Can't promote — created without validation` | Version was created with `--skip-validation` | Re-create the version without that flag (and with `--code-coverage`) |
| `Code coverage has not been run for this version` | Version created without `--code-coverage` | Re-create with `--code-coverage` |
| `Item__c: Item_Record_Page does not exist or is not a valid override` | Object XML has a `<type>Flexipage</type>` action override | `sortComponents.js` removes these automatically; re-run it or run `createPackageVersion.sh` |
| `invalid cross reference id` on PermissionSet | Packaged PermissionSet references a Named Credential not in the package | Remove `<externalCredentialPrincipalAccesses>` from `force-app/.../Lumen_Planning_Permission_Set_1.permissionset-meta.xml`; `retrieve-all.ps1` handles this on retrieve |
| `AppConstantsTest: Expected: Dispo_, Actual: Disposition_` | Test assertion stale after constant rename | Update the expected value in `AppConstantsTest.cls` to match `AppConstants.cls` |
| `NamespaceRegistryValidator threw an unhandled exception` | `"namespace": "kqexe"` present in `sfdx-project.json` | Remove the `"namespace"` key from `sfdx-project.json` (intentionally omitted — see Prerequisites note) |
| `The given ancestorVersion is not in the correct format` | Wrong format for `ancestorVersion` | Use dot notation `1.0.0.LATEST`, not dash format `1.0.0-2` |
| `entity type cannot be inserted: Package` | Wrong Dev Hub or 2GP not enabled | Use `--target-dev-hub lumenProd` explicitly |

---

## Quick Reference

| Task | Command |
|------|---------|
| Authenticate Dev Hub | `sf org login web --alias lumenProd --set-default-dev-hub` |
| Retrieve metadata | `powershell -ExecutionPolicy Bypass -File scripts/retrieve-all.ps1 -OrgAlias kqexpkg` |
| Sort components | `node scripts/sortComponents.js` |
| Create version (automated) | `bash scripts/createPackageVersion.sh` |
| Create version (manual) | `sf package version create --package kqexe --installation-key-bypass --skip-ancestor-check --code-coverage --wait 30 --target-dev-hub lumenProd` |
| Check version status | `sf package version create report --package-create-request-id <08c...> --target-dev-hub lumenProd` |
| List all versions | `sf package version list --target-dev-hub lumenProd` |
| Promote to Released | `sf package version promote --package <04t-id> --target-dev-hub lumenProd --no-prompt` |
| Test beta install | `sf package install --package <04t-id> --target-org <alias> --wait 15 && node scripts/postInstall.js <alias>` |
