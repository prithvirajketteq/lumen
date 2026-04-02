trigger OrderTrigger on Order__c (before insert, before update) {
    new OrderTriggerHandler().run();
}