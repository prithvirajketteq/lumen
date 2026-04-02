@IsTest
public class TestDataFactory {
    public static void createItems(Integer count){

        List<Item__c> items = new List<Item__c>();

        for(Integer i = 0; i < count; i++){

            items.add(new Item__c(
                Name = 'Item ' + i,
                Supplier_Part_Number__c = 'SP-' + i
            ));
        }

        insert items;
    }


    public static void createItemsForRepairBatch(){

        List<Item__c> items = new List<Item__c>();

        items.add(new Item__c(
            Name='Item Repair 1',
            Supplier_Part_Number__c=null,
            Failures_Repair__c=1
        ));

        items.add(new Item__c(
            Name='Item Repair 2',
            Supplier_Part_Number__c='SPN-1',
            Failures_Repair__c=10,
            Spare_3PL__c=1,
            Central_Spare__c=1,
          //  Spare_City__c=1,
            In_Repair__c=1,
            Awaiting_Return__c=1,
            Intransit_To_Depots__c=1
        ));

        items.add(new Item__c(
            Name='Item Recycle',
            Supplier_Part_Number__c='SPN-2',
            Failures_Repair__c=0,
            Spare_3PL__c=5,
            Central_Spare__c=5,
          //  Spare_City__c=5,
            Excess_Spares_Good__c=2
        ));

        items.add(new Item__c(
            Name='Item AWR',
            Supplier_Part_Number__c='SPN-3',
            Failures_Repair__c=0,
            Spare_3PL__c=5,
            Central_Spare__c=5,
          //  Spare_City__c=5,
            Excess_Spares_Good__c=0
        ));

        insert items;
    }

    /**
     * Creates and inserts a single primary Item__c (no Item_Parent__c).
     * Returns the inserted record with its Id populated.
     */
    public static Item__c createPrimaryItem(String name) {
    Item__c primary = new Item__c(
        Name = name,
        Primary__c = true  
    );
    insert primary;
    return primary;
}

    /**
     * Creates and inserts `count` secondary Item__c records under the given
     * primary, with all 14 rollup fields set to the supplied perItemValue.
     * Returns the inserted list.
     */
    public static List<Item__c> createSecondaryItemsForRollup(
            Id primaryId, Integer count, Decimal perItemValue) {

        List<Item__c> secondaries = new List<Item__c>();
        for (Integer i = 0; i < count; i++) {
            secondaries.add(new Item__c(
                Name                   = 'Secondary ' + (i + 1),
                Item_Parent__c         = primaryId,
                Order_Same_Day__c      = perItemValue,
                Order_Next_Day__c      = perItemValue,
                Order_180_Days__c      = perItemValue,
                Total_Deployed__c      = perItemValue,
                Total_Required_Spares__c = perItemValue,
                Total_Spares__c        = perItemValue,
                Local_Spares__c        = perItemValue,
                Central_Spare__c       = perItemValue,
                Stock__c               = perItemValue,
                In_Field__c            = perItemValue,
                IN_N_OUT__c            = perItemValue,
                Awaiting_Return__c= perItemValue,
                At_Vendor__c           = perItemValue,
                Intransit_To_Depots__c = perItemValue
            ));
        }
        insert secondaries;
        return secondaries;
    }
    
    

    // Create & insert CHILD Item
    public static Item__c createChildItem(String name, Id parentId){

        Item__c item = new Item__c(
            Name = name,
            Item_Parent__c = parentId//,Primary__c = false 
        );

        insert item;
        return item;
    }

    // Create item without parent
    public static Item__c createItemWithoutParent(String name){

        Item__c item = new Item__c(
            Name = name//,
            //Primary__c  = true // safe default
        );

        insert item;
        return item;
    }

    // Vendor Pricing (VALIDATED)
    public static Vendor_Pricing__c createAndInsertVendorPricing(Id itemId){

        System.assertNotEquals(null, itemId, 'Item Id cannot be null');

        Vendor_Pricing__c vp = new Vendor_Pricing__c(
    Item__c = itemId
        );

        insert vp;
        return vp;
    }

    public static Order__c createOrder(Id itemId){

        System.assertNotEquals(null, itemId, 'Item Id cannot be null');

        Order__c vp = new Order__c(
    Item__c = itemId
        );
        return vp;
    }


}