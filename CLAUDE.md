# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Lumen** is a Salesforce 2GP Unlocked Package (API v65.0) — a Lightning dashboard for parts inventory analysis. Stack: Apex (backend), LWC (frontend), SOQL, Jest for LWC unit tests.

## Commands

```bash
# Install dependencies
npm install

# Scratch org setup (creates org, deploys, assigns perms, imports data, opens browser)
npm run org:init
# or with alias: bash scripts/orgInit.sh <alias> [devHubAlias]

# Linting
npm run lint                    # ESLint on LWC/Aura JS

# Testing (LWC Jest)
npm test                        # Run all LWC unit tests
npm run test:unit:watch         # Watch mode
npm run test:unit:debug         # Debug mode
npm run test:unit:coverage      # Coverage report

# Formatting
npm run prettier                # Format all files
npm run prettier:verify         # Verify without changes

# Salesforce CLI
sf project deploy start --source-dir force-app --target-org <alias>
sf apex run test -o <alias>                          # Run Apex tests in org
sf data import tree --plan data/data-plan.json --target-org <alias>
sf apex run -f scripts/apex/hello.apex
```

Pre-commit hooks run lint + Prettier + related Jest tests automatically via Husky/lint-staged.

## Architecture

### Data Model

`Item__c` is the central object, organized in a parent-child hierarchy (self-lookup via `Item_Parent__c`). Parent items aggregate rollup values from their children.

| Object | Description |
|--------|-------------|
| `Item__c` | Parts/items with 14 rollup aggregate fields; self-referencing parent-child hierarchy |
| `Vendor__c` | Parts vendors/suppliers |
| `Customer__c` | Customer accounts |
| `Site__c` | Depot/warehouse sites |
| `Item_Site__c` | Item inventory levels per site (junction) |
| `Interchangeable_Part__c` | Interchangeable part relationships |
| `Vendor_Pricing__c` | Vendor pricing per item |
| `Order__c` | Parts orders history |

### Apex Architecture

**Trigger pattern:** All triggers are single-line delegators — `new XxxTriggerHandler().run()`. The abstract `TriggerHandler` base class handles routing and admin bypass via `Trigger_Setting__mdt`. To skip a handler entirely, add a CMT record matching the handler class name; to skip a specific method, add `_{MethodName}` suffix.

**`ItemTriggerHandler`** — The most complex class. Implements parent-child rollup aggregation for `Item__c`. Rollup field mappings are driven entirely by `Application_Config__mdt` records with `DeveloperName LIKE 'ItemRollup_%'` (15 fields). A `rollupRunning` static flag prevents recursive updates when parents are written.

**Key classes:**

| Class | Purpose |
|-------|---------|
| `TriggerHandler` | Abstract base; admin bypass via `Trigger_Setting__mdt` |
| `ItemTriggerHandler` | CMT-driven rollup aggregation on Item__c hierarchy |
| `GenericUtility` | Shared statics: `nvl()`, CSV generation, Amazon callout, partial DML, `populateParentItemFromItem()`, `rebuildParentSearchItems()` |
| `DynamicFieldCounterController` | `@AuraEnabled getFieldTotals()` — dynamic SOQL SUM aggregates for any object/fields |
| `ReusableRelatedListController` | Generic paginated related-list fetcher with field/record-type filtering |
| `BatchCalculateRepairAction` | Batch + Schedulable; calculates `Repair_Status__c` on Item__c using configurable SOQL from `Application_Config__mdt` |
| `ItemCSVBatch` | Exports Item__c records to CSV; field list driven by `CSV_Field_Config__mdt` (ordered by Sequence__c); sends to Amazon via named credential |
| `ItemCSVBatchScheduler` | Schedulable wrapper for `ItemCSVBatch` |

### Configuration-Driven Patterns

Business logic avoids hardcoding by reading `Application_Config__mdt`:
- **Rollup mappings** — `ItemRollup_*` records define which fields to SUM on parent items
- **Batch SOQL** — `BatchCalculateRepairAction_SOQL1` record holds the item query for repair calculation
- **CSV fields** — `CSV_Field_Config__mdt` records define field order and mapping for CSV export
- **Trigger bypass** — `Trigger_Setting__mdt` records let admins skip handlers/methods without code deploys

### LWC

Currently one component: **`dynamicFieldCounter`** — a configurable field-totaling widget that accepts `childObject`, `parentLookupField`, `fieldNames`, and optional `filterCondition` as `@api` properties, calls `DynamicFieldCounterController.getFieldTotals()`, and renders a Lightning datatable of aggregated values.

### Repair Status Logic (`BatchCalculateRepairAction`)

Three-state classification on `Item__c.Repair_Status__c`:
- **REPAIR** — if `Supplier_Part_Number__c` is blank, or failures ≥ available spares, or stock requirement ≥ available spares
- **RECYCLE** — if excess spares > 0
- **AWR** (Awaiting Return) — all other cases

### Custom Permission

`Parts_Dashboard_Edit` — controls edit access within dashboard components.

## Key Conventions

- **ESLint flat config** (`eslint.config.js`) — separate rule sets for Aura, LWC, LWC test files, and Jest mocks.
- **No trailing commas** (`.prettierrc`) — enforced by Prettier on all file types.
- LWC test files live in `__tests__/` subdirectories alongside the component and use `@salesforce/sfdx-lwc-jest`.
- Apex tests use `TestDataFactory` for all fixture creation; `MockAmazonCallout` for HTTP mocks.
- Partial DML (`Database.update(records, false)`) is the standard pattern — errors are logged, not thrown.
- Sample data (1,355+ records) lives in `data/` and is imported via `sf data import tree --plan data/data-plan.json`. Cross-object refs use `@referenceId` format. Rebuild from a connected org with `npm run data:rebuild`.
