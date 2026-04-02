public class OrderTriggerHandler extends TriggerHandler {

    private List<Order__c> newList;
    private Map<Id, Order__c> oldMap;

    public OrderTriggerHandler() {
        this.newList = Trigger.new    != null ? (List<Order__c>)    Trigger.new    : new List<Order__c>();
        this.oldMap  = Trigger.oldMap != null ? (Map<Id, Order__c>) Trigger.oldMap : new Map<Id, Order__c>();
    }

    protected override void beforeInsert() {
        GenericUtility.populateParentItemFromItem(newList, null);
    }

    protected override void beforeUpdate() {
        GenericUtility.populateParentItemFromItem(newList, oldMap);
    }
}