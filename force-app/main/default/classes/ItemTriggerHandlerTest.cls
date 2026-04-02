@IsTest
private class ItemTriggerHandlerTest {
    // ─── Shared mock config ───────────────────────────────────────────────────
    
    private static List<Application_Config__mdt> mockConfigs() {
        return new List<Application_Config__mdt>{
            new Application_Config__mdt(
                Config_Key__c   = 'kqexe__Month_12_Same_Day_Orders__c',
                Config_Value__c = 'kqexe__Month_12_Same_Day_Orders__c'
            ),
                new Application_Config__mdt(
                    Config_Key__c   = 'kqexe__Month_12_Next_Day_Orders__c',
                    Config_Value__c = 'kqexe__Month_12_Next_Day_Orders__c'
                )
                };
                    }
    
    // ─── Test: rollup fires on insert of secondary item ───────────────────────
    
    @IsTest
    static void testRollupOnInsert() {
        Item__c primary = new Item__c(Name = 'Primary', Primary__c = true);
        insert primary;
        
        ItemTriggerHandler.configOverride = mockConfigs();
        
        Test.startTest();
        insert new List<Item__c>{
            new Item__c(Name = 'Sec1', Item_Parent__c = primary.Id,
                        Month_12_Same_Day_Orders__c = 5,
                        Month_12_Next_Day_Orders__c = 2),
                new Item__c(Name = 'Sec2', Item_Parent__c = primary.Id,
                            Month_12_Same_Day_Orders__c = 3,
                            Month_12_Next_Day_Orders__c = 1)
                };
                    Test.stopTest();
        
        Item__c result = [
            SELECT Month_12_Same_Day_Orders__c, Month_12_Next_Day_Orders__c
            FROM   Item__c
            WHERE  Id = :primary.Id
        ];
        System.assertEquals(8, result.Month_12_Same_Day_Orders__c, 'Same-day rollup: 5+3');
        System.assertEquals(3, result.Month_12_Next_Day_Orders__c, 'Next-day rollup: 2+1');
    }
    
    // ─── Test: rollup recalculates on update of secondary item ───────────────
    
    @IsTest
    static void testRollupOnUpdate() {
        Item__c primary = new Item__c(Name = 'Primary', Primary__c = true);
        insert primary;
        
        Item__c sec1 = new Item__c(Name = 'Sec1', Item_Parent__c = primary.Id,
                                   Month_12_Same_Day_Orders__c = 5);
        Item__c sec2 = new Item__c(Name = 'Sec2', Item_Parent__c = primary.Id,
                                   Month_12_Same_Day_Orders__c = 3);
        insert new List<Item__c>{ sec1, sec2 };
            
            ItemTriggerHandler.configOverride = new List<Application_Config__mdt>{
                new Application_Config__mdt(
                    Config_Key__c   = 'kqexe__Month_12_Same_Day_Orders__c',
                    Config_Value__c = 'kqexe__Month_12_Same_Day_Orders__c'
                )
                    };
                        
                        Test.startTest();
        sec1.Month_12_Same_Day_Orders__c = 10;
        update sec1;
        Test.stopTest();
        
        Item__c result = [SELECT Month_12_Same_Day_Orders__c FROM Item__c WHERE Id = :primary.Id];
        System.assertEquals(13, result.Month_12_Same_Day_Orders__c, 'Rollup after update: 10+3');
    }
    
    // ─── Test: updating a primary item does not trigger rollup ───────────────
    
    @IsTest
    static void testNoRollupForPrimaryItems() {
        Item__c primary = new Item__c(Name = 'Primary', Primary__c = true, Month_12_Same_Day_Orders__c = 99);
        insert primary;
        
        ItemTriggerHandler.configOverride = mockConfigs();
        
        Test.startTest();
        primary.Comment__c = 'Updated';
        update primary;
        Test.stopTest();
        
        Item__c result = [SELECT Month_12_Same_Day_Orders__c FROM Item__c WHERE Id = :primary.Id];
        System.assertEquals(99, result.Month_12_Same_Day_Orders__c,
                            'Primary-only update must not touch rollup fields');
    }
    
    // ─── Test: reparenting recalculates both old and new parents ─────────────
    
    @IsTest
    static void testRollupOnParentChange() {
        Item__c primary1 = new Item__c(Name = 'Primary1', Primary__c = true);
        Item__c primary2 = new Item__c(Name = 'Primary2', Primary__c = true);
        insert new List<Item__c>{ primary1, primary2 };
            
            Item__c sec = new Item__c(Name = 'Sec', Item_Parent__c = primary1.Id,
                                      Month_12_Same_Day_Orders__c = 7);
        insert sec;
        
        ItemTriggerHandler.configOverride = new List<Application_Config__mdt>{
            new Application_Config__mdt(
                Config_Key__c   = 'kqexe__Month_12_Same_Day_Orders__c',
                Config_Value__c = 'kqexe__Month_12_Same_Day_Orders__c'
            )
                };
                    
                    Test.startTest();
        sec.Item_Parent__c = primary2.Id;
        update sec;
        Test.stopTest();
        
        Map<Id, Item__c> results = new Map<Id, Item__c>([
            SELECT Month_12_Same_Day_Orders__c
            FROM   Item__c
            WHERE  Id IN (:primary1.Id, :primary2.Id)
        ]);
        
        System.assertEquals(null, results.get(primary1.Id).Month_12_Same_Day_Orders__c,
                            'Old parent has no children — value not written');
        System.assertEquals(7, results.get(primary2.Id).Month_12_Same_Day_Orders__c,
                            'New parent should reflect the moved secondary');
    }
    
    // ─── Test: no configs skips rollup ───────────────────────────────────────
    
    @IsTest
    static void testNoConfigsSkipsRollup() {
        Item__c primary = new Item__c(Name = 'Primary', Primary__c = true, Month_12_Same_Day_Orders__c = 50);
        insert primary;

        ItemTriggerHandler.configOverride = new List<Application_Config__mdt>();

        Test.startTest();
        insert new Item__c(Name = 'Sec', Item_Parent__c = primary.Id,
                           Month_12_Same_Day_Orders__c = 10);
        Test.stopTest();

        Item__c result = [SELECT Month_12_Same_Day_Orders__c FROM Item__c WHERE Id = :primary.Id];
        System.assertEquals(50, result.Month_12_Same_Day_Orders__c,
                            'With no configs, primary value must remain unchanged');
    }
    
    // ─── Test: rollup recalculates when a secondary is deleted ───────────────
    
    @IsTest
    static void testRollupOnDelete() {
        Item__c primary = new Item__c(Name = 'Primary', Primary__c = true);
        insert primary;

        Item__c sec1 = new Item__c(Name = 'Sec1', Item_Parent__c = primary.Id,
                                   Month_12_Same_Day_Orders__c = 6);
        Item__c sec2 = new Item__c(Name = 'Sec2', Item_Parent__c = primary.Id,
                                   Month_12_Same_Day_Orders__c = 4);
        insert new List<Item__c>{ sec1, sec2 };
            
            ItemTriggerHandler.configOverride = new List<Application_Config__mdt>{
                new Application_Config__mdt(
                    Config_Key__c   = 'kqexe__Month_12_Same_Day_Orders__c',
                    Config_Value__c = 'kqexe__Month_12_Same_Day_Orders__c'
                )
                    };
                        
                        Test.startTest();
        delete sec1;
        Test.stopTest();
        
        Item__c result = [SELECT Month_12_Same_Day_Orders__c FROM Item__c WHERE Id = :primary.Id];
        System.assertEquals(4, result.Month_12_Same_Day_Orders__c,
                            'After deleting sec1, only sec2 value (4) should remain');
    }
    
    // ─── Test: rollup recalculates when a secondary is undeleted ─────────────
    
    @IsTest
    static void testRollupOnUndelete() {
        Item__c primary = new Item__c(Name = 'Primary', Primary__c = true);
        insert primary;
        
        Item__c sec1 = new Item__c(Name = 'Sec1', Item_Parent__c = primary.Id,
                                   Month_12_Same_Day_Orders__c = 6);
        Item__c sec2 = new Item__c(Name = 'Sec2', Item_Parent__c = primary.Id,
                                   Month_12_Same_Day_Orders__c = 4);
        insert new List<Item__c>{ sec1, sec2 };
            delete sec1;
        
        ItemTriggerHandler.configOverride = new List<Application_Config__mdt>{
            new Application_Config__mdt(
                Config_Key__c   = 'kqexe__Month_12_Same_Day_Orders__c',
                Config_Value__c = 'kqexe__Month_12_Same_Day_Orders__c'
            )
                };
                    
                    Test.startTest();
        undelete sec1;
        Test.stopTest();
        
        Item__c result = [SELECT Month_12_Same_Day_Orders__c FROM Item__c WHERE Id = :primary.Id];
        System.assertEquals(10, result.Month_12_Same_Day_Orders__c,
                            'After undeleting sec1, rollup should be 6+4=10');
    }
}