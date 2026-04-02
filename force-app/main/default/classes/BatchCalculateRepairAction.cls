global class BatchCalculateRepairAction implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc){
        String query;
        try{
            Application_Config__mdt config =[
                SELECT Config_Value__c
                FROM Application_Config__mdt
                WHERE DeveloperName = :AppConstants.BATCH_REPAIR_SOQL_CONFIG
                AND Active__c = true
                LIMIT 1
            ];

            if(config != null && String.isNotBlank(config.Config_Value__c)){
                query= config.Config_Value__c;
            }
        } catch(Exception ex){
            System.debug('BatchCalculateRepairAction | Metadata read failed: ' + ex.getMessage());
        }

        if(String.isBlank(query)){
            throw new AuraHandledException('BatchCalculateRepairAction: Missing SOQL configuration.');
        }
        return Database.getQueryLocator(query);
    }


    global void execute(Database.BatchableContext bc, List<SObject> scope){
        List<Item__c> recordsToUpdate = new List<Item__c>();

        for(SObject sob : scope) {
            Item__c item = (Item__c)sob;

            String calculatedRepairAction;

            // Rule 1: Missing Supplier Part Number
            if(String.isBlank(item.Supplier_Part_Number__c)) {
                calculatedRepairAction = AppConstants.REPAIR_ACTION_REPAIR;

            } else{

                Decimal availableSpares =
                    GenericUtility.nvl(item.Spare_3PL__c) +
                    GenericUtility.nvl(item.Central_Spare__c) +
                   // GenericUtility.nvl(item.Spare_City__c) +
                    GenericUtility.nvl(item.In_Repair__c) +
                    GenericUtility.nvl(item.Awaiting_Return__c) +
                    GenericUtility.nvl(item.Intransit_To_Depots__c);

                Boolean failureThresholdReached = GenericUtility.nvl(item.Failures_Repair__c) >= availableSpares;
                Boolean stockRequirementReached = (GenericUtility.nvl(item.Required_Central_Spares__c) + GenericUtility.nvl(item.Local_Spares__c)) >= availableSpares;

                if(failureThresholdReached || stockRequirementReached){
                    calculatedRepairAction = AppConstants.REPAIR_ACTION_REPAIR;
                
                } else if(item.Excess_Spares_Good__c != null && item.Excess_Spares_Good__c > 0){
                    calculatedRepairAction = AppConstants.REPAIR_ACTION_RECYCLE;
                    
                } else{
                    calculatedRepairAction = AppConstants.REPAIR_ACTION_AWR;

                }
            }

            if(item.REPAIR_ACTION__c != calculatedRepairAction) {
                item.REPAIR_ACTION__c = calculatedRepairAction;
                recordsToUpdate.add(item);
            }
        }

  
        if(!recordsToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(recordsToUpdate, false);

            for(Integer i = 0; i < results.size(); i++){
                if(!results[i].isSuccess()){

                    for (Database.Error err : results[i].getErrors()) {
                        System.debug('BatchCalculateRepairAction | DML Error | RecordId: ' + recordsToUpdate[i].Id + ' | Message: ' + err.getMessage());
                    }
                }
            }
        }
    }


    global void finish(Database.BatchableContext bc) {
        System.debug('BatchCalculateRepairAction completed successfully.');
         String switchForChaining;
        try{
            Application_Config__mdt config =[
                SELECT Config_Value__c
                FROM Application_Config__mdt
                WHERE DeveloperName = 'ItemCSVBatchChainingSwitch'
                AND Active__c = true
                LIMIT 1
            ];

            if(config != null && String.isNotBlank(config.Config_Value__c)){
                 switchForChaining = config.Config_Value__c;
            }
        } catch(Exception ex){
            System.debug('BatchCalculateRepairAction | Metadata read failed: ' + ex.getMessage());
        }
        if(switchForChaining == 'ON'){
            Database.executeBatch(new ItemCSVBatch(), AppConstants.DEFAULT_BATCH_SIZE);
        }
        else {
            System.debug('Dont call ItemCSVBatch in chaining');
        }
    
    }
       
}