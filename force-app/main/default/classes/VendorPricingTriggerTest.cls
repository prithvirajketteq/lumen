@isTest
public class VendorPricingTriggerTest {

   @isTest
    static void testInsertPopulateParent(){

        Item__c parentItem = TestDataFactory.createPrimaryItem('Parent Item1');
        Item__c childItem = TestDataFactory.createChildItem('Child Item1', parentItem.Id);

        Vendor_Pricing__c vp = new Vendor_Pricing__c(
            
            Item__c = childItem.Id
        );

        insert vp;

        Vendor_Pricing__c result = [
            SELECT Parent_Item__c
            FROM Vendor_Pricing__c
            WHERE Id = :vp.Id
        ];

        System.assertEquals(parentItem.Id, result.Parent_Item__c);
    }

    @isTest
    static void testUpdateItemChangesParent(){

        Item__c parent1 = TestDataFactory.createPrimaryItem('Parent A');
        Item__c parent2 = TestDataFactory.createPrimaryItem('Parent B');

        Item__c child1 = TestDataFactory.createChildItem('Child A', parent1.Id);
        Item__c child2 = TestDataFactory.createChildItem('Child B', parent2.Id);

        Vendor_Pricing__c vp = new Vendor_Pricing__c(
           
            Item__c = child1.Id
        );

        insert vp;

        vp = [SELECT Parent_Item__c FROM Vendor_Pricing__c WHERE Id = :vp.Id];
        System.assertEquals(parent1.Id, vp.Parent_Item__c);

        vp.Item__c = child2.Id;
        update vp;

        vp = [SELECT Parent_Item__c FROM Vendor_Pricing__c WHERE Id = :vp.Id];

        System.assertEquals(parent2.Id, vp.Parent_Item__c);
    }

    @isTest
    static void testBulkInsert(){

        Item__c parentItem = TestDataFactory.createPrimaryItem('Parent Item3');
        Item__c childItem = TestDataFactory.createChildItem('Child Item3', parentItem.Id);

        List<Vendor_Pricing__c> records = new List<Vendor_Pricing__c>();

        for(Integer i = 0; i < 200; i++){
            records.add(new Vendor_Pricing__c(
                
                Item__c = childItem.Id
            ));
        }

        Test.startTest();
        insert records;
        Test.stopTest();

        for(Vendor_Pricing__c vp : [
            SELECT Parent_Item__c FROM Vendor_Pricing__c WHERE Id IN :records
        ]){
            System.assertEquals(parentItem.Id, vp.Parent_Item__c);
        }
    }
}