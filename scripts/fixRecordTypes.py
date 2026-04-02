#!/usr/bin/env python3
"""
Resolves org-specific RecordType IDs in data files before import.

Usage: python scripts/fixRecordTypes.py <org-alias>

How it works:
  1. Reads data/record-type-ids.json to find which IDs are currently in data files
  2. Queries the target org for the real IDs (by DeveloperName + SObjectType)
  3. Replaces old IDs with new ones across all data files
  4. Updates record-type-ids.json to reflect the new IDs (for the next run)
"""

import sys
import json
import subprocess
import os

if len(sys.argv) < 2:
    print("Usage: python scripts/fixRecordTypes.py <org-alias>")
    sys.exit(1)

ORG = sys.argv[1]
MAPPING_FILE = "data/record-type-ids.json"
DATA_PLAN = "data/data-plan.json"


def query_org(soql):
    query_file = os.path.join(os.environ.get("TEMP", os.environ.get("TMP", "/tmp")), "_rt_query.txt")
    with open(query_file, "w") as f:
        f.write(soql)
    result = subprocess.run(
        f'sf data query --file "{query_file}" --target-org {ORG} --json',
        capture_output=True,
        text=True,
        shell=True,
    )
    raw = result.stdout if result.stdout.strip() else result.stderr
    data = json.loads(raw)
    return data["result"]["records"]


# Load current mapping: sobject -> { developer_name -> current_id_in_data_files }
with open(MAPPING_FILE) as f:
    mapping = json.load(f)

# Build reverse lookup: current_id -> (sobject, developer_name)
old_id_map = {}
for sobject, rt_map in mapping.items():
    for dev_name, old_id in rt_map.items():
        if old_id:
            old_id_map[old_id] = (sobject, dev_name)

# Query the target org for real IDs
sobject_filter = " OR ".join([f"SobjectType='{s}'" for s in mapping.keys()])
soql = f"SELECT Id, DeveloperName, SObjectType FROM RecordType WHERE {sobject_filter}"
records = query_org(soql)

# Build new mapping: (sobject, developer_name) -> new_id
new_id_lookup = {(r.get("SObjectType") or r.get("SobjectType"), r["DeveloperName"]): r["Id"] for r in records}

# Build replacement map: old_id -> new_id
replacement = {}
for old_id, (sobject, dev_name) in old_id_map.items():
    new_id = new_id_lookup.get((sobject, dev_name))
    if new_id and old_id != new_id:
        replacement[old_id] = new_id

if not replacement:
    print("  RecordType IDs already match target org — no changes needed.")
    sys.exit(0)

print(f"  Replacing {len(replacement)} RecordType ID(s):")
for old, new in replacement.items():
    sobject, dev_name = old_id_map[old]
    print(f"    {sobject}.{dev_name}: {old} -> {new}")

# Patch each data file listed in the plan
with open(DATA_PLAN) as f:
    plan = json.load(f)

for step in plan:
    for fname in step.get("files", []):
        fpath = os.path.join("data", fname)
        with open(fpath) as f:
            content = f.read()
        patched = content
        for old, new in replacement.items():
            patched = patched.replace(old, new)
        if patched != content:
            with open(fpath, "w") as f:
                f.write(patched)
            print(f"    Patched: {fname}")

# Update mapping file so next run knows the current IDs
new_mapping = {}
for sobject, rt_map in mapping.items():
    new_mapping[sobject] = {}
    for dev_name, old_id in rt_map.items():
        new_mapping[sobject][dev_name] = new_id_lookup.get((sobject, dev_name), old_id)

with open(MAPPING_FILE, "w") as f:
    json.dump(new_mapping, f, indent=2)
