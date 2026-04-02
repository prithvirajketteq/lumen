# Lumen (kqexe) — 2GP Managed Package Development Guide

> **Product:** kqexe (Lumen Spares Planning)
> **Namespace:** `kqexe`
> **Dev Hub:** `lumenDevHub`
> **Packaging Org:** `kqexpkg`
> **API Version:** `66.0`

---

## Table of Contents

1. [Project Structure](#1-project-structure)
2. [Key Concepts](#2-key-concepts)
3. [Environment Setup](#3-environment-setup)
4. [Development Workflow](#4-development-workflow)
5. [Retrieving Metadata](#5-retrieving-metadata)
6. [Creating a Scratch Org](#6-creating-a-scratch-org)
7. [Creating a Package Version](#7-creating-a-package-version)
8. [Installing the Package](#8-installing-the-package)
9. [Post Installation Steps](#9-post-installation-steps)
10. [Version Numbering Guide](#10-version-numbering-guide)
11. [What You Can and Cannot Change](#11-what-you-can-and-cannot-change)
12. [Scripts Reference](#12-scripts-reference)

---

## 1. Project Structure

```
lumen/
├── force-app/                        ← MANAGED PACKAGE components
│   └── main/default/
│       ├── classes/                  Apex classes & triggers
│       ├── objects/                  Custom objects & fields
│       ├── lwc/                      Lightning Web Components
│       ├── customMetadata/           Custom metadata types & records
│       ├── globalValueSets/          Global picklist values
│       ├── labels/                   Custom labels
│       └── tabs/                     Custom tabs
│
├── force-app-unpackaged/             ← UNPACKAGED (org-specific) components
│   └── main/default/
│       ├── applications/             Lightning App (Spares_Planning)
│       ├── flexipages/               Record pages (Item_Record_Page)
│       ├── layouts/                  Page layouts
│       ├── namedCredentials/         Named credentials (org-specific)
│       ├── permissionsets/           Permission sets
│       ├── profiles/                 Admin profile (FLS)
│       └── reports/                  Reports
│
├── manifest/
│   ├── package.xml                   Defines what to retrieve into force-app
│   └── unpackaged.xml                Defines what to retrieve into force-app-unpackaged
│
├── config/
│   └── project-scratch-def.json      Scratch org definition
│
├── data/                             Sample data for import
├── scripts/                          Automation scripts
└── sfdx-project.json                 Project configuration
```

### What Goes Where

| Component Type | `force-app` (Managed) | `force-app-unpackaged` |
|---|---|---|
| Apex Classes & Triggers | ✅ | |
| Custom Objects & Fields | ✅ | |
| LWC Components | ✅ | |
| Custom Metadata | ✅ | |
| Global Value Sets | ✅ | |
| Custom Labels | ✅ | |
| Custom Tabs | ✅ | |
| Lightning App | | ✅ |
| FlexiPages / Record Pages | | ✅ |
| Page Layouts | | ✅ |
| Named Credentials | | ✅ |
| Permission Sets | | ✅ |
| Admin Profile (FLS) | | ✅ |
| Reports | | ✅ |

---

## 2. Key Concepts

### Packaging Org (`kqexpkg`) vs Source of Truth

`kqexpkg` is the **packaging org** — the org from which all package versions are created. It contains the latest working version of all managed package components. All development changes must be deployed back to `kqexpkg` before creating a new package version.

### Managed vs Unpackaged Components

**Managed components** (`force-app`) are included in the `kqexe` package and installed in subscriber orgs automatically when the package is installed.

**Unpackaged components** (`force-app-unpackaged`) are org-specific and must be deployed separately after package installation using `npm run post:install`. These components reference managed package fields and objects using the `kqexe__` namespace prefix when deployed to subscriber orgs.

### Namespace Transforms

When deploying unpackaged components to a subscriber org (where the package is installed), all bare custom API names are automatically prefixed with `kqexe__` by `postInstall.js`. For example `Item__c` becomes `kqexe__Item__c`, `Vendor__r` becomes `kqexe__Vendor__r`, and so on.

---

## 3. Environment Setup

### Prerequisites

```powershell
# Verify Salesforce CLI is installed
sf --version

# Verify authenticated orgs
sf org list

# Required org aliases
# lumenDevHub  — Dev Hub org for package version creation
# kqexpkg      — Packaging org (source of truth)
```

### Authenticate Orgs (First Time Only)

```powershell
# Authenticate Dev Hub
sf org login web --alias lumenDevHub --set-default-dev-hub

# Authenticate Packaging Org
sf org login web --alias kqexpkg
```

### `sfdx-project.json` Overview

```json
{
  "packageDirectories": [
    {
      "path": "force-app-unpackaged",
      "default": false
    },
    {
      "path": "force-app",
      "default": true,
      "package": "kqexe",
      "versionName": "ver 5.0 Mar 2026",
      "versionNumber": "5.0.0.NEXT",
      "definitionFile": "config/project-scratch-def.json",
      "ancestorVersion": "NONE"
    }
  ],
  "sourceApiVersion": "66.0"
}
```

---

## 4. Development Workflow

### Standard Development Flow

```
1. npm run retrieve -- kqexpkg     ← Pull latest from packaging org
          ↓
2. npm run org:init                 ← Create scratch org & deploy everything
          ↓
3. Develop in scratch org           ← Make changes, test thoroughly
          ↓
4. Pull changes back locally        ← Retrieve from scratch org
          ↓
5. Deploy back to kqexpkg           ← Sync packaging org
          ↓
6. bash scripts/createPackageVersion.sh   ← Create new package version
          ↓
7. Test in sandbox                  ← Install & run post:install
          ↓
8. Promote version (if stable)      ← Make available for production
```

### Day-to-Day Commands

```powershell
# Start your day — always retrieve latest first
npm run retrieve -- kqexpkg

# Create fresh scratch org for development
npm run org:init

# Retrieve your changes from scratch org back to local
sf project retrieve start --target-org lumenScratch-1

# Deploy your changes back to packaging org
sf project deploy start --source-dir force-app --target-org kqexpkg
sf project deploy start --source-dir force-app-unpackaged --target-org kqexpkg
```

---

## 5. Retrieving Metadata

Retrieval pulls the latest metadata from `kqexpkg` into both local folders. Always run this before starting any development work.

### Command

```powershell
npm run retrieve -- kqexpkg
```

### What It Does

The `scripts/retrieve-all.ps1` script performs these steps automatically:

1. Verifies connection to `kqexpkg`
2. Asks for confirmation before deleting local files
3. Cleans `force-app/main/default/` and `force-app-unpackaged/main/default/`
4. Retrieves managed components using `manifest/package.xml` → `force-app`
5. Retrieves unpackaged components using `manifest/unpackaged.xml` → `force-app-unpackaged`
6. Restores `sfdx-project.json` defaults
7. Runs automatic post-retrieve cleanup:
   - Removes FlexiPage `actionOverrides` from `Item__c` object
   - Removes `externalCredentialPrincipalAccesses` from PermissionSet
   - Removes `AttachedContentNotes` related list from `Item_Record_Page`

### Manifest Files

**`manifest/package.xml`** — Managed package components (retrieved into `force-app`):
- All Apex Classes and Triggers
- All Custom Metadata Types and Records
- All Custom Objects (Item__c, Vendor__c, Order__c, Site__c, Customer__c, Interchangeable_Part__c, Item_Site__c, Vendor_Pricing__c, Application_Config__mdt, CSV_Field_Config__mdt, Trigger_Setting__mdt)
- All Custom Tabs, Labels, Global Value Sets
- Page Layouts for all objects
- LWC Component (dynamicFieldCounter)
- Custom Application (Spares_Planning)
- FlexiPage (Item_Record_Page)
- Permission Set (Lumen_Planning_Permission_Set_1)
- Admin Profile (for FLS — retrieved with objects to ensure completeness)

**`manifest/unpackaged.xml`** — Unpackaged components (retrieved into `force-app-unpackaged`):
- Named Credentials
- Reports

> **Note:** Admin Profile is retrieved via `package.xml` (alongside objects for complete FLS) but lives in `force-app-unpackaged` after retrieval.

---

## 6. Creating a Scratch Org

Scratch orgs are used for development and testing. They are temporary (30 days) and fully isolated.

### Command

```powershell
# Creates scratch org with auto-incremented alias (lumenScratch-1, lumenScratch-2, etc.)
npm run org:init

# Or with a custom alias
node scripts/orgInit.js myFeatureScratch

# Or with a custom alias and dev hub
node scripts/orgInit.js myFeatureScratch lumenDevHub
```

### What It Does

The `scripts/orgInit.js` script performs these steps:

1. **Retrieves latest metadata** from `kqexpkg` automatically
2. **Asks confirmation** — "Do you want to create a scratch org and run post-deployment?"
   - Answer `n` → stops after retrieve (useful for metadata-only sync)
   - Answer `y` → continues with scratch org setup
3. **Creates scratch org** from `config/project-scratch-def.json` (30-day duration)
4. **Deploys `force-app`** — all managed package components
5. **Deploys `force-app-unpackaged`** — app, flexipages, layouts, named credentials, reports, permission set
6. **Assigns permission set** — `Lumen_Planning_Permission_Set_1`
7. **Resolves RecordType IDs** — runs `scripts/fixRecordTypes.py` to match target org IDs
8. **Imports sample data** — all 8 objects (Vendor, Customer, Site, Item, Interchangeable_Part, Item_Site, Vendor_Pricing, Order)
9. **Opens org** in browser

### Scratch Org Definition (`config/project-scratch-def.json`)

```json
{
  "orgName": "Lumen Scratch Org",
  "edition": "Developer",
  "features": ["EnableSetPasswordInApi"],
  "settings": {
    "lightningExperienceSettings": {
      "enableS1DesktopEnabled": true
    }
  }
}
```

> **Note:** `AttachedContentNotes` related list is removed from `Item_Record_Page` automatically during retrieval since the Notes feature is not enabled in scratch orgs. Add it back manually via Setup → App Builder after scratch org creation if needed.

---

## 7. Creating a Package Version

### When to Create a Package Version

Create a new package version when you have:
- Bug fixes ready to ship
- New features developed and tested in scratch org
- All changes deployed back to `kqexpkg`
- All Apex tests passing (75%+ coverage required for promoted versions)

### Command

```bash
# Run from project root (uses lumenProd as default dev hub)
bash scripts/createPackageVersion.sh lumenDevHub
```

### What It Does

The `scripts/createPackageVersion.sh` script performs these steps:

1. **Sorts components** — runs `node scripts/sortComponents.js` which:
   - Moves flexipages, layouts, reports, named credentials, permission sets from `force-app` → `force-app-unpackaged`
   - Strips FlexiPage `actionOverrides` from object XML
   - Removes `Count_of_Child_Items__c` visibilityRules from FlexiPages
2. **Creates package version** — waits up to 30 minutes for Salesforce to compile and run tests
3. **Prints install URL** — for immediate testing
4. **Asks for promotion** — "Promote to Released? (y/n)"
   - Answer `n` → Beta version only (sandbox/dev orgs)
   - Answer `y` → Promoted version (installable in production)

### Before Creating a Version — Checklist

```
✅ Retrieved latest from kqexpkg (npm run retrieve -- kqexpkg)
✅ All changes deployed to kqexpkg
✅ Tested in scratch org (npm run org:init)
✅ All Apex tests passing
✅ sfdx-project.json versionNumber updated if needed
✅ sfdx-project.json versionName updated to describe the release
```

### Updating Version Number in `sfdx-project.json`

```json
{
  "versionName": "ver 5.1 Apr 2026",
  "versionNumber": "5.1.0.NEXT",
  "ancestorVersion": "HIGHEST"
}
```

### Manual Package Version Creation

```powershell
# Beta version (no code coverage required, sandbox only)
sf package version create --package kqexe --target-dev-hub lumenDevHub --installation-key-bypass --wait 10

# Release candidate (with code coverage, required before promoting)
sf package version create --package kqexe --target-dev-hub lumenDevHub --installation-key-bypass --code-coverage --wait 30

# Promote to Released (installable in production)
sf package version promote --package kqexe@5.0.0-2 --target-dev-hub lumenDevHub
```

---

## 8. Installing the Package

### Install via Browser

Get the `04t` subscriber package version ID from:
```powershell
sf package version list --target-dev-hub lumenDevHub
```

Then use the install URL:
```
# Production / Developer Org
https://login.salesforce.com/packaging/installPackage.apexp?p0=<04t_ID>

# Sandbox
https://test.salesforce.com/packaging/installPackage.apexp?p0=<04t_ID>
```

### Install via CLI

```powershell
# Install package
sf package install --package kqexe@5.0.0-1 --target-org <org-alias> --wait 10

# Then immediately run post-install
npm run post:install -- <org-alias>
```

### Current Package Versions

| Version | Released | Notes |
|---|---|---|
| `kqexe@4.0.0-1` | No | Beta |
| `kqexe@4.0.0-2` | Yes | Released |
| `kqexe@5.0.0-1` | Yes | Current (ID: 04ta500000D9GKbAAN) |

---

## 9. Post Installation Steps

After installing the package in any org (sandbox, developer, or production), run the post-install script to deploy unpackaged components and import sample data.

### Command

```powershell
npm run post:install -- <org-alias>

# Example
npm run post:install -- lumen-dev1
npm run post:install -- myProductionOrg
```

### What It Does

The `scripts/postInstall.js` script performs these steps:

1. **Preflight check** — verifies `kqexe` package is installed in target org
2. **Clears temp directory** — ensures fresh namespace transforms every run
3. **Namespace transforms** (Step 0) — prepares all unpackaged components:
   - Prefixes all bare `__c`/`__r` API names with `kqexe__`
   - Renames layout filenames (`Order__c-` → `kqexe__Order__c-`)
   - Prefixes LWC component names in FlexiPage (`c:foo` → `kqexe:foo`)
   - Prefixes `{!Record.Field__c}` references in FlexiPage
   - Removes `AttachedContentNotes` region from FlexiPage
   - Removes `Count_of_Child_Items__c` visibilityRules from FlexiPage
   - Strips `recordTypeVisibilities` from PermissionSet
   - Strips `externalCredentialPrincipalAccesses` from PermissionSet
   - Strips `utilityBar` reference from App
4. **Deploys unpackaged components** (Step 1) — App, FlexiPage, PermissionSet, Named Credentials, Reports, Layouts
5. **Deploys Item__c action override** (Step 1b) — activates `Item_Record_Page` as the record page for `kqexe__Item__c`
6. **Assigns permission sets** (Step 2):
   - `kqexe__Lumen_Planning_Permission_Set_1` (from package)
   - `Lumen_Planning_Permission_Set_1` (unpackaged)
7. **Resolves RecordType IDs** (Step 3) — queries org for actual IDs
8. **Transforms data files** (Step 4) — prefixes all API names in data JSON files
9. **Imports sample data** (Step 5) — 1,355+ records across 8 objects
10. **Opens org** in browser (Step 6)

### Manual Post-Install Steps

After running `npm run post:install`, do these manually if needed:

```
1. Setup → Named Credentials
   → Create External Credential: Ketteq_API_Credential_Dev
   → Then Named Credential Ketteq_API_Dev will work

2. Setup → App Builder → Item Record Page
   → Add "Notes & Attachments" related list back to sidebar
   → Activate the page
```

---

## 10. Version Numbering Guide

Version numbers follow `Major.Minor.Patch.Build` format. The Build number is always `NEXT` in `sfdx-project.json` — Salesforce auto-increments it.

### When to Use Each

| Version Type | Format | Use When |
|---|---|---|
| **Patch** | `5.0.1.NEXT` | Bug fixes only, no new fields or objects |
| **Minor** | `5.1.0.NEXT` | New features, new fields/objects, backwards compatible |
| **Major** | `6.0.0.NEXT` | Breaking changes, architecture redesign |

### Decision Tree

```
Did you break anything existing?
        ↓ YES              ↓ NO
      Major          Did you add new features?
                       ↓ YES        ↓ NO
                     Minor       Bug fixes only?
                                   ↓ YES
                                  Patch
```

### Beta vs Promoted

| | Beta | Promoted |
|---|---|---|
| Installable in | Sandbox & Developer orgs | Production orgs too |
| Can uninstall | Yes | No |
| Can upgrade | No | Yes |
| Code coverage | Not required | 75% minimum |
| Use for | Testing, QA, internal validation | Customer-facing releases |

**Rule:** Always test in sandbox with `npm run post:install` before promoting any version.

---

## 11. What You Can and Cannot Change

### In a Promoted Managed Package

| Change | Allowed |
|---|---|
| Change Apex class logic | ✅ Yes |
| Add new Apex methods | ✅ Yes |
| Add new custom fields | ✅ Yes |
| Add new custom objects | ✅ Yes |
| Change field labels | ✅ Yes |
| Change API name of field | ❌ Never |
| Change API name of object | ❌ Never |
| Delete a custom field | ❌ Never (deprecate instead) |
| Delete a custom object | ❌ Never (deprecate instead) |
| Remove a `global` Apex method | ❌ Never |

### Deprecating Fields (Instead of Deleting)

```xml
<CustomField>
    <fullName>Old_Field__c</fullName>
    <deprecated>true</deprecated>
</CustomField>
```

### If You Need Breaking Changes

If you need to rename or delete fields/objects and have no real production customers yet:

1. Export all data from test orgs
2. Uninstall package from all test orgs
3. Make breaking changes locally
4. Update `sfdx-project.json`:
   ```json
   {
     "versionNumber": "6.0.0.NEXT",
     "ancestorVersion": "NONE"
   }
   ```
5. Create fresh package version
6. Reinstall and reimport data
7. Update `postInstall.js` for new API names

---

## 12. Scripts Reference

| Script | Command | Description |
|---|---|---|
| `retrieve-all.ps1` | `npm run retrieve -- <org>` | Retrieve all metadata from packaging org |
| `orgInit.js` | `npm run org:init` | Create scratch org with full setup |
| `createPackageVersion.sh` | `bash scripts/createPackageVersion.sh` | Create new package version |
| `postInstall.js` | `npm run post:install -- <org>` | Deploy unpackaged components after package install |
| `sortComponents.js` | Auto-run by createPackageVersion.sh | Sort components between force-app folders |
| `buildDataPlan.py` | `npm run data:rebuild` | Rebuild data plan from packaging org |
| `fixRecordTypes.py` | Auto-run by orgInit.js | Resolve RecordType IDs for target org |

### Quick Reference

```powershell
# Sync latest from packaging org
npm run retrieve -- kqexpkg

# Create scratch org for development
npm run org:init

# Create new package version
bash scripts/createPackageVersion.sh lumenDevHub

# Install package in org
sf package install --package kqexe@5.0.0-1 --target-org <alias> --wait 10

# Deploy unpackaged components after package install
npm run post:install -- <org-alias>

# List all package versions
sf package version list --target-dev-hub lumenDevHub

# Promote a package version
sf package version promote --package kqexe@5.0.0-2 --target-dev-hub lumenDevHub
```

---

*Last updated: April 2026 | Package: kqexe | Version: 5.0.0*
