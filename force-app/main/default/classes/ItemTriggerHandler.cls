/**
 * ItemTriggerHandler
 *
 * Trigger handler for Item__c. Extends TriggerHandler and owns the full
 * rollup logic — config loading, change detection, and aggregation.
 *
 * Configuration driven by Application_Config__mdt (DeveloperName LIKE 'ItemRollup_%'):
 *   Config_Key__c   — field on secondary item to sum
 *   Config_Value__c — field on primary item to write result to
 *   Active__c       — enable/disable per field without code change
 */
public class ItemTriggerHandler extends TriggerHandler {

    private List<Item__c> newList;
    private List<Item__c> oldList;
    private Map<Id, Item__c> oldMap;
    private List<Application_Config__mdt> configs;

    @TestVisible
    private static List<Application_Config__mdt> configOverride;
    private static Boolean rollupRunning = false;

    public ItemTriggerHandler() {
        this.newList  = Trigger.new     != null ? (List<Item__c>)    Trigger.new    : new List<Item__c>();
        this.oldList  = Trigger.old     != null ? (List<Item__c>)    Trigger.old    : new List<Item__c>();
        this.oldMap   = Trigger.oldMap  != null ? (Map<Id, Item__c>) Trigger.oldMap : new Map<Id, Item__c>();
        this.configs  = getRollupConfigs();
    }

    // ─── Trigger Events ───────────────────────────────────────────────────────

    protected override void afterInsert() {
        System.debug('In afterInsert	::	');
        if (rollupRunning || configs.isEmpty()) return;

        Set<Id> primaryIds = new Set<Id>();
        for (Item__c item : newList) {
            if (item.Item_Parent__c != null) primaryIds.add(item.Item_Parent__c);
        }
        GenericUtility.rebuildParentSearchItems(newList, oldMap);
        if (!primaryIds.isEmpty()) performRollup(primaryIds, configs);
    }

    protected override void afterUpdate() {
        System.debug('In afterUpdate	::	');
        if (rollupRunning || configs.isEmpty()) return;

        Set<Id> primaryIds = new Set<Id>();
        for (Item__c item : newList) {
            Item__c oldItem = oldMap.get(item.Id);

            // Reparenting — recalculate both old and new parent
            if (oldItem.Item_Parent__c != item.Item_Parent__c) {
                if (item.Item_Parent__c    != null) primaryIds.add(item.Item_Parent__c);
                if (oldItem.Item_Parent__c != null) primaryIds.add(oldItem.Item_Parent__c);
                continue;
            }

            // Not a secondary item — nothing to roll up
            if (item.Item_Parent__c == null) continue;

            // Only recalculate if at least one configured field value changed
            for (Application_Config__mdt cfg : configs) {
                if (item.get(cfg.Config_Key__c) != oldItem.get(cfg.Config_Key__c)) {
                    primaryIds.add(item.Item_Parent__c);
                    break;
                }
            }
        }
        GenericUtility.rebuildParentSearchItems(newList, oldMap);
        if (!primaryIds.isEmpty()) performRollup(primaryIds, configs);
    }

    protected override void afterDelete() {
        System.debug('In afterInsert	::	');
        if (configs.isEmpty()) return;

        Set<Id> primaryIds = new Set<Id>();
        for (Item__c item : oldList) {
            if (item.Item_Parent__c != null) primaryIds.add(item.Item_Parent__c);
        }

        if (!primaryIds.isEmpty()) performRollup(primaryIds, configs);
    }

    protected override void afterUndelete() {
        if (configs.isEmpty()) return;

        Set<Id> primaryIds = new Set<Id>();
        for (Item__c item : newList) {
            if (item.Item_Parent__c != null) primaryIds.add(item.Item_Parent__c);
        }

        if (!primaryIds.isEmpty()) performRollup(primaryIds, configs);
    }

    // ─── Config Loading ───────────────────────────────────────────────────────

    private static List<Application_Config__mdt> getRollupConfigs() {
        if (configOverride != null) return configOverride;
        return [
            SELECT Config_Key__c, Config_Value__c
            FROM   Application_Config__mdt
            WHERE  DeveloperName LIKE 'ItemRollup_%'
            AND    Active__c = true
        ];
    }

    // ─── Rollup Execution ─────────────────────────────────────────────────────

    private static void performRollup(Set<Id> primaryItemIds, List<Application_Config__mdt> configs) {

        Set<String> fieldSet = new Set<String>{ 'kqexe__Item_Parent__c' };
        for (Application_Config__mdt cfg : configs) fieldSet.add(cfg.Config_Key__c);

        String soql = 'SELECT ' + String.join(new List<String>(fieldSet), ', ')
                    + ' FROM kqexe__Item__c WHERE kqexe__Item_Parent__c IN :primaryItemIds';

        List<Item__c> secondaryItems;
        try {
            secondaryItems = Database.query(soql);
        } catch (Exception e) {
            System.debug('ItemTriggerHandler | Query failed: ' + e.getMessage());
            return;
        }

        if (secondaryItems.isEmpty()) return;

        Map<Id, List<Item__c>> byParent = new Map<Id, List<Item__c>>();
        for (Item__c sec : secondaryItems) {
            if (!byParent.containsKey(sec.Item_Parent__c)) {
                byParent.put(sec.Item_Parent__c, new List<Item__c>());
            }
            byParent.get(sec.Item_Parent__c).add(sec);
        }

        // Pre-build a zero-initialised totals map keyed by source field
        Map<String, Decimal> zeroTotals = new Map<String, Decimal>();
        for (Application_Config__mdt cfg : configs) zeroTotals.put(cfg.Config_Key__c, 0);

        List<Item__c> toUpdate = new List<Item__c>();
        for (Id primaryId : primaryItemIds) {
            List<Item__c> children = byParent.get(primaryId);
            if (children == null || children.isEmpty()) continue;

            // Single pass over children — accumulate all field totals at once
            Map<String, Decimal> totals = zeroTotals.clone();
            for (Item__c child : children) {
                for (Application_Config__mdt cfg : configs) {
                    Decimal val = (Decimal) child.get(cfg.Config_Key__c);
                    if (val != null) totals.put(cfg.Config_Key__c, totals.get(cfg.Config_Key__c) + val);
                }
            }

            Item__c primary = new Item__c(Id = primaryId);
            for (Application_Config__mdt cfg : configs) {
                primary.put(cfg.Config_Value__c, totals.get(cfg.Config_Key__c));
            }
            toUpdate.add(primary);
        }

        if (!toUpdate.isEmpty()) {
            rollupRunning = true;
            try {
                Database.update(toUpdate, false);
            } finally {
                rollupRunning = false;
            }
        }
    }
}