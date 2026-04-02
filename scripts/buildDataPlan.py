"""
Build a proper sf data import tree plan from kqexpkg org.
Queries all custom objects with their real Salesforce IDs, assigns referenceIds,
then replaces cross-object ID references with @referenceId in the output JSONs.

Usage: python scripts/buildDataPlan.py
Output: data/ directory with JSON files + data-plan.json
"""

import subprocess
import json
import os
import re

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
ORG_ALIAS = "mydevhub"

# Relationship fields per object: {field_name: target_object_api_name}
RELATIONSHIPS = {
    "Item__c": {
        "Vendor__c": "Vendor__c",
        "Item_Parent__c": "Item__c",
    },
    "Interchangeable_Part__c": {
        "Child_Item__c": "Item__c",
        "Parent_Item__c": "Item__c",
    },
    "Item_Site__c": {
        "Item__c": "Item__c",
        "Site__c": "Site__c",
    },
    "Vendor_Pricing__c": {
        "Item__c": "Item__c",
        "Vendor__c": "Vendor__c",
        "Parent_Item__c": "Item__c",
    },
    "Order__c": {
        "Item__c": "Item__c",
        "Vendor__c": "Vendor__c",
        "Customer__c": "Customer__c",
        "Parent_Item__c": "Item__c",
    },
    "Site__c": {
        "Parent_Site__c": "Site__c",
    },
}

# SOQL queries per object (all createable fields)
QUERIES = {
    "Vendor__c": (
        "SELECT Id,OwnerId,Name,RecordTypeId,Active__c,Days_At_Vendor__c,RMA_Number__c,"
        "Received_By_Vendor__c,Region__c,SLA__c,Ship_To_Vendor__c,Supplier_Part_Number__c,"
        "Type__c,Vendor_Code__c,Way_Bill__c,External_ID__c FROM Vendor__c"
    ),
    "Customer__c": (
        "SELECT Id,OwnerId,Name,Address__c,City__c,Customer_Group_Desc__c,Description__c,"
        "Division__c,Geolocation__Latitude__s,Geolocation__Longitude__s,Postal_Code__c,"
        "Region__c,State__c,Country__c,Customer_Group__c,External_ID__c FROM Customer__c"
    ),
    "Site__c": (
        "SELECT Id,OwnerId,Name,RecordTypeId,Designation_Type__c,Region__c,Depot_Code__c,"
        "Parent_Site__c,Stock_Type__c,Country_Code__c,Site_ID__c,Company_Code__c,"
        "External_ID__c FROM Site__c"
    ),
    "Item__c": (
        "SELECT Id,OwnerId,Name,Actual_12_Month_Spares_Orders__c,Actual_Avg_Days_Between_Failures__c,"
        "Adjusted_Required_Spares__c,At_Vendor__c,Awaiting_Repair__c,Awaiting_Return__c,Category__c,"
        "Comment__c,Excess_Spares_Bad__c,Excess_Spares_Good__c,Excess_Spares__c,Failure_Rate__c,"
        "Gap_Cost__c,Gap__c,In_Field__c,In_Repair__c,Interchangeable__c,Intransit_To_Depots__c,"
        "Inventory_Supply_Level__c,Max_Keep_Spares__c,Month_12_Failure_Rate__c,"
        "Month_12_Next_Day_Orders__c,Month_12_Same_Day_Orders__c,Month_3_Total_Orders__c,"
        "Order_180_Days__c,Order_Next_Day__c,Order_Same_Day__c,Repair_Status__c,Vendor__c,"
        "Required_Central_Spares__c,SAP_Price__c,Safety_Spares__c,Spare_3PL__c,Central_Spare__c,"
        "Spares_Trigger__c,Sparing_Strategy__c,Supplier_Part_Number__c,Total_Central_Spares__c,"
        "Total_Current_Spares__c,Total_Deployed__c,Total_Depots__c,Total_Repairs__c,Local_Spares__c,"
        "Total_Required_Spares__c,Platform__c,Failures_Repair__c,SAP_Part_Number__c,Total_Spares__c,"
        "Stock_Good__c,Stock__c,IN_N_OUT__c,AWR__c,Interchangeable_Code__c,Repair_Action__c,"
        "Primary__c,Item_Parent__c,Search_Items__c,External_ID__c FROM Item__c"
    ),
    "Interchangeable_Part__c": (
        "SELECT Id,OwnerId,Name,Child_Item__c,Description__c,Parent_Item__c,External_ID__c "
        "FROM Interchangeable_Part__c"
    ),
    "Item_Site__c": (
        "SELECT Id,Name,Item__c,Site__c,In_Transit_To_Depot__c,Spare_Total__c,Spares_AWR__c,"
        "Spares_Required__c,Spares__c,Stock_AWR__c,Total_Deployed__c,Stock__c,External_ID__c "
        "FROM Item_Site__c"
    ),
    "Vendor_Pricing__c": (
        "SELECT Id,Item__c,Active__c,Default__c,Notes__c,Purchase_Cost__c,Repair_Cost__c,"
        "Vendor__c,Parent_Item__c,External_ID__c FROM Vendor_Pricing__c"
    ),
    "Order__c": (
        "SELECT Id,OwnerId,Name,RecordTypeId,Part_Request_Number__c,RMA_Number__c,Case_Number__c,"
        "Order_Type__c,Urgency__c,Item__c,Part_Owner__c,Ship_To_City__c,Ship_To_State__c,Vendor__c,"
        "Closure_Code__c,Order_Priority__c,Original_Part_Number__c,Region__c,SLA__c,"
        "Days_At_Vendor__c,Way_Bill__c,Line_Number__c,Closed_Date__c,Type__c,Open_QTY__c,"
        "Total_QTY__c,Shipped_QTY__c,Requsted_QTY__c,Source_Plant__c,Manufacturing_Part_Number__c,"
        "Customer__c,Parent_Item__c,External_ID__c,Shipped_To_Vendor__c,Received_By_Vendor__c "
        "FROM Order__c"
    ),
}

# Import order (respects dependencies)
IMPORT_ORDER = [
    "Vendor__c",
    "Customer__c",
    "Site__c",
    "Item__c",
    "Interchangeable_Part__c",
    "Item_Site__c",
    "Vendor_Pricing__c",
    "Order__c",
]

# File prefix per object
FILE_PREFIXES = {
    "Vendor__c": "vendor",
    "Customer__c": "customer",
    "Site__c": "site",
    "Item__c": "item",
    "Interchangeable_Part__c": "interchangeable",
    "Item_Site__c": "itemsite",
    "Vendor_Pricing__c": "vendorpricing",
    "Order__c": "order",
}


def query_sf(soql):
    """Run a SOQL query against the org and return records."""
    result = subprocess.run(
        ["powershell", "-Command", f'sf data query --query "{soql}" -o {ORG_ALIAS} --json'],
        capture_output=True,
        text=True,
    )
    try:
        d = json.loads(result.stdout)
        return d.get("result", {}).get("records", [])
    except Exception as e:
        print(f"  ERROR parsing query result: {e}")
        return []


def clean_record(record, obj_api_name, id_to_ref):
    """Remove system fields, replace Salesforce IDs with @referenceId."""
    skip_fields = {
        "attributes", "Id", "IsDeleted", "CreatedDate", "CreatedById",
        "LastModifiedDate", "LastModifiedById", "LastViewedDate",
        "LastReferencedDate", "SystemModstamp",
    }
    cleaned = {}
    obj_relationships = RELATIONSHIPS.get(obj_api_name, {})

    for key, value in record.items():
        if key in skip_fields:
            continue
        if value is None:
            continue
        # Replace relationship field Salesforce IDs with @referenceId
        if key in obj_relationships and value and isinstance(value, str):
            if value in id_to_ref:
                cleaned[key] = "@" + id_to_ref[value]
            else:
                # ID from source org not found in our data — skip this field
                print(f"    WARNING: {obj_api_name}.{key} = {value} not found in id_to_ref, skipping")
                continue
        else:
            cleaned[key] = value
    return cleaned


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Step 1: Query all objects and build id_to_ref map
    all_data = {}   # obj_api_name -> list of records (raw)
    id_to_ref = {}  # salesforce_id -> referenceId string

    for obj in IMPORT_ORDER:
        print(f"Querying {obj}...")
        records = query_sf(QUERIES[obj])
        all_data[obj] = records
        prefix = FILE_PREFIXES[obj]
        for i, rec in enumerate(records, 1):
            sf_id = rec.get("Id")
            ref_id = f"{prefix}Ref{i}"
            if sf_id:
                id_to_ref[sf_id] = ref_id
        print(f"  {len(records)} records, referenceIds assigned")

    # Step 2: Build cleaned JSON files with @referenceIds
    plan_entries = []

    for obj in IMPORT_ORDER:
        prefix = FILE_PREFIXES[obj]
        filename = f"{prefix}-{obj}.json"
        filepath = os.path.join(OUTPUT_DIR, filename)

        cleaned_records = []
        for i, rec in enumerate(all_data[obj], 1):
            ref_id = f"{prefix}Ref{i}"
            cleaned = clean_record(rec, obj, id_to_ref)
            entry = {
                "attributes": {
                    "type": obj,
                    "referenceId": ref_id,
                },
            }
            entry.update(cleaned)
            cleaned_records.append(entry)

        output = {"records": cleaned_records}
        with open(filepath, "w") as f:
            json.dump(output, f, indent=2)
        print(f"Wrote {len(cleaned_records)} records to {filename}")

        plan_entries.append({
            "sobject": obj,
            "saveRefs": True,
            "resolveRefs": True,
            "files": [filename],
        })

    # Step 3: Write data-plan.json
    plan_path = os.path.join(OUTPUT_DIR, "data-plan.json")
    with open(plan_path, "w") as f:
        json.dump(plan_entries, f, indent=2)
    print(f"\nWrote data-plan.json with {len(plan_entries)} objects")


if __name__ == "__main__":
    main()
