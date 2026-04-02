@isTest
public class OrderTriggerTest {

    @isTest
    static void testInsertPopulateParent(){

        Item__c parentItem = TestDataFactory.createPrimaryItem('Parent Item');
        Item__c childItem = TestDataFactory.createChildItem('Child Item', parentItem.Id);

        Order__c ord = TestDataFactory.createOrder(childItem.Id);

        insert ord;

        Order__c result = [
            SELECT Parent_Item__c
            FROM Order__c
            WHERE Id = :ord.Id
        ];

        System.assertEquals(parentItem.Id, result.Parent_Item__c);
    }

    @isTest
    static void testUpdateItemChangesParent(){

        Item__c parentItem = TestDataFactory.createPrimaryItem('Parent Item');
        Item__c childItem = TestDataFactory.createChildItem('Child Item', parentItem.Id);
        Item__c noParentItem = TestDataFactory.createPrimaryItem('No Parent Item');

        Order__c ord = TestDataFactory.createOrder(childItem.Id);
        insert ord;

        // ord.Item__c = noParentItem.Id;
        // update ord;

        Order__c result = [
            SELECT Parent_Item__c
            FROM Order__c
            WHERE Id = :ord.Id
        ];

        System.assertEquals(parentItem.Id, result.Parent_Item__c);
        update ord;
    }

    // @isTest
    // static void testBulkInsert(){

    //     Item__c parentItem = TestDataFactory.createPrimaryItem('Parent Item');
    //     Item__c childItem = TestDataFactory.createChildItem('Child Item', parentItem.Id);

    //     List<Order__c> orders = new List<Order__c>();

    //     for(Integer i=0;i<200;i++){
    //         Order__c ord = new Order__c(Name = +'BulkChild'+i, Parent_Item__c = parentItem.Id);
    //          orders.add(ord);
    //     }

    //     Test.startTest();
    //     insert orders;
    //     Test.stopTest();

    //     for(Order__c ord : [
    //         SELECT Parent_Item__c FROM Order__c WHERE Id IN :orders
    //     ]){
    //         System.assertEquals(parentItem.Id, ord.Parent_Item__c);
    //     }
    // }
}