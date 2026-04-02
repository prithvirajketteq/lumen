trigger VendorPricingTrigger on Vendor_Pricing__c (before insert, before update) {
    new VendorPricingTriggerHandler().run();
}