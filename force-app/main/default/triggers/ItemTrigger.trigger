trigger ItemTrigger on Item__c (after insert, after update, after delete, after undelete) {
	new ItemTriggerHandler().run();
}