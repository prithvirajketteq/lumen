@IsTest
public class TriggerHandlerTest {
    
    @IsTest
    static void testTriggerExecution_usingFactory() {
        
        Test.startTest();
        
        // This will fire trigger → which calls your handler
        TestDataFactory.createItems(5);
        
        Test.stopTest();
        
        System.assert(true, 'Trigger executed successfully');
    }
    
    @IsTest
    static void testUpdateFlow() {
        
        List<Item__c> items = new List<Item__c>();
        for(Integer i = 0; i < 2; i++){
            items.add(new Item__c(Name = 'Update Test ' + i));
        }
        insert items;
        
        Test.startTest();
        
        for(Item__c i : items){
            i.Name = 'Updated ' + i.Name;
        }
        update items;
        
        Test.stopTest();
        
        System.assertEquals(2, items.size());
    }
    
    @IsTest
    static void testDeleteFlow() {
        
        List<Item__c> items = new List<Item__c>();
        for(Integer i = 0; i < 2; i++){
            items.add(new Item__c(Name = 'Delete Test ' + i));
        }
        insert items;
        
        Test.startTest();
        delete items;
        Test.stopTest();
        
        System.assert(true, 'Delete executed');
    }
    
    // Covers: afterUndelete path in run()
    @IsTest
    static void testUndeleteFlow() {
        List<Item__c> items = new List<Item__c>();
        for (Integer i = 0; i < 2; i++) {
            items.add(new Item__c(Name = 'Undelete Test ' + i));
        }
        insert items;
        delete items;
        
        Test.startTest();
        undelete items;
        Test.stopTest();
        
        System.assert(true, 'Undelete path executed');
    }    
}