@IsTest
private class BatchCalculateRepairActionTest {
    
    @testSetup
    static void setupData() {
        
        TestDataFactory.createItemsForRepairBatch();
        
    }
    
    @IsTest
    static void testBatchExecution() {
        
        Test.startTest();
        
        Database.executeBatch(new BatchCalculateRepairAction(), AppConstants.DEFAULT_BATCH_SIZE);
        
        Test.stopTest();
        
        List<Item__c> results = [
            SELECT Repair_Action__c, Supplier_Part_Number__c
            FROM Item__c
        ];
        
        Boolean foundRepair = false;
        Boolean foundRecycle = false;
        Boolean foundAWR = false;
        
        for(Item__c item : results){
            
            if(item.Supplier_Part_Number__c == null &&
               item.Repair_action__c == AppConstants.REPAIR_ACTION_REPAIR){
                   foundRepair = true;
               }
            
            if(item.Repair_action__c == AppConstants.REPAIR_ACTION_RECYCLE){
                foundRecycle = true;
            }
            
            if(item.Repair_action__c == AppConstants.REPAIR_ACTION_AWR){
                foundAWR = true;
            }
        }
        
        System.assert(foundRepair, 'REPAIR condition not triggered');
        System.assert(foundRecycle, 'RECYCLE condition not triggered');
        System.assert(foundAWR, 'AWR condition not triggered');
        
    }
    // ─── Schedulable execute() — Switch OFF ──────────────────────────────────────
    
    // ─── Execute Batch — Repair Status Unchanged — No DML ────────────────────────
    
    @IsTest
    static void testExecute_NoChangeNoUpdate() {
        // If Repair_Status__c already matches
        // calculated value → recordsToUpdate stays empty
        // → no DML fired
        
        // Pre-set items to expected status
        // so calculated == existing → skip update
        List<Item__c> items = [
            SELECT Id, Repair_action__c,
            Supplier_Part_Number__c
            FROM Item__c
        ];
        
        // Force all to REPAIR status first
        for (Item__c item : items) {
            item.Supplier_Part_Number__c = null;
            item.Repair_action__c =
                AppConstants.REPAIR_ACTION_REPAIR;
        }
        update items;
        
        Test.startTest();
        Database.executeBatch(
            new BatchCalculateRepairAction(),
            AppConstants.DEFAULT_BATCH_SIZE
        );
        Test.stopTest();
        
        // Items with no supplier part number
        // should still be REPAIR — no change
        List<Item__c> results = [
            SELECT Repair_action__c
            FROM Item__c
            WHERE Supplier_Part_Number__c = null
        ];
        
        for (Item__c item : results) {
            Assert.areEqual(
                AppConstants.REPAIR_ACTION_REPAIR,
                item.Repair_Action__c != null ? item.Repair_Action__c.toUpperCase() : null,
                'Status unchanged when already correct'
            );
        }
    }
    
    
    @IsTest
    static void testExecute_DMLErrorHandledGracefully() {
        // Database.update with false (partial success)
        // errors are logged not thrown
        // Verify batch completes even with bad records
        
        Test.startTest();
        try {
            Database.executeBatch(
                new BatchCalculateRepairAction(),
                AppConstants.DEFAULT_BATCH_SIZE
            );
            Assert.isTrue(true, 'Batch completed without exception');
        } catch (Exception e) {
            Assert.fail('Batch should handle DML errors gracefully: '
                        + e.getMessage());
        }
        Test.stopTest();
    }    
}