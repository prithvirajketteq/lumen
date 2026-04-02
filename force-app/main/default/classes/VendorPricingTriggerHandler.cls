public class VendorPricingTriggerHandler extends TriggerHandler {

    private List<Vendor_Pricing__c> newList;
    private Map<Id, Vendor_Pricing__c> oldMap;

    public VendorPricingTriggerHandler() {
        this.newList = Trigger.new    != null ? (List<Vendor_Pricing__c>)    Trigger.new    : new List<Vendor_Pricing__c>();
        this.oldMap  = Trigger.oldMap != null ? (Map<Id, Vendor_Pricing__c>) Trigger.oldMap : new Map<Id, Vendor_Pricing__c>();
    }

    protected override void beforeInsert() {
        GenericUtility.populateParentItemFromItem(newList, null);
    }

    protected override void beforeUpdate() {
        GenericUtility.populateParentItemFromItem(newList, oldMap);
    }
}