global class ItemCSVBatch implements 
    Database.Batchable<SObject>, 
    Database.Stateful, 
    Database.AllowsCallouts {

    List<CSV_Field_Config__mdt> fieldConfigs;
    List<String> csvLines = new List<String>();

    global Database.QueryLocator start(Database.BatchableContext bc) {

        fieldConfigs = [
            SELECT Field_API_Name__c, Sequence__c
            FROM CSV_Field_Config__mdt
            WHERE Active__c = TRUE
            ORDER BY Sequence__c
        ];

        List<String> fields = new List<String>();

        for(CSV_Field_Config__mdt config : fieldConfigs){
            fields.add(config.Field_API_Name__c);
        }

        String query = 'SELECT ' + String.join(fields, ',') + ' FROM kqexe__Item__c';

        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc, List<SObject> scope) {

        for(SObject record : scope){

            List<String> rowValues = new List<String>();

            for(CSV_Field_Config__mdt config : fieldConfigs){

                Object val = record.get(config.Field_API_Name__c);

                rowValues.add(val == null ? '' : String.valueOf(val));
            }

            csvLines.add(String.join(rowValues, '|'));
        }
    }

    global void finish(Database.BatchableContext bc) {

        String csvBody = String.join(csvLines, '\n');
        String fileName = GenericUtility.generateCSVFileName();
        System.debug('Generated File Name: ' + fileName);

        try{
            HttpResponse res = GenericUtility.sendCSVToAmazon(csvBody, fileName);

            System.debug('Response Code: ' + res.getStatusCode());
            System.debug('Response Body: ' + res.getBody());

        }catch(Exception e){
            System.debug('Amazon Callout Failed: ' + e.getMessage());
        }
    }
}