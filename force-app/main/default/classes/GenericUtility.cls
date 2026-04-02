public class GenericUtility {

    /*
    Null safe decimal
    */
    public static Decimal nvl(Decimal val){
        return val == null ? 0 : val;
    }

    /*
    CSV File Name Generator
    */
    public static String generateCSVFileName(){

        Datetime nowDT = Datetime.now();

        String datePart = nowDT.format('yyyyMMdd');
        String timePart = nowDT.format('HHmmss');

        return AppConstants.FILE_PREFIX + datePart + '_' + timePart + AppConstants.FILE_EXTENSION;
    }

    /*
    Amazon Callout
    */
    public static HttpResponse sendCSVToAmazon(String csvContent, String fileName){
    
        Application_Config__mdt config = Application_Config__mdt.getInstance('Ketteq_Named_Credential');
        String namedCred = config.Config_Value__c;
        
        Blob fileBlob = Blob.valueOf(csvContent);
        String encodedFileName = EncodingUtil.urlEncode(fileName, 'UTF-8');
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:'+namedCred+'/sfdc/upload/lumen?filename=output_files_sfdc/' + encodedFileName);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/csv');
        req.setBodyAsBlob(fileBlob);
    
        Http http = new Http();
    
        return http.send(req);
    }
    
    public static void updateRecordsPartial(List<SObject> recordsToUpdate){

        if(recordsToUpdate == null || recordsToUpdate.isEmpty()){
            return;
        }

        Database.SaveResult[] results = Database.update(recordsToUpdate, false);

        for(Integer i = 0; i < results.size(); i++){

            if(!results[i].isSuccess()){

                for(Database.Error err : results[i].getErrors()){

                    System.debug('Record Failed: ' + recordsToUpdate[i]);
                    System.debug('Error Message: ' + err.getMessage());
                }
            }
        }
    }
    

 public static void populateParentItemFromItem(List<SObject> records, Map<Id, SObject> oldMap) {

    Set<Id> itemIds = new Set<Id>();

    // Step 1: Collect Item__c values
    for (SObject rec : records) {

        Id itemId = (Id)rec.get('kqexe__Item__c');

        if(itemId != null){
            itemIds.add(itemId);
        }
    }

    if(itemIds.isEmpty()){
        return;
    }

    system.debug('@@@itemids ='+itemIds);
    // Step 2: Query Items with Parent + Primary flag
    Map<Id, Item__c> itemMap = new Map<Id, Item__c>([
        SELECT Id, Item_Parent__c, Item_Parent__r.Primary__c
        FROM Item__c
        WHERE Id IN :itemIds
    ]);
    system.debug('itemMap: ' + itemMap.values());
    // Step 3: Assign Parent_Item__c safely
    for(SObject rec : records){

        Id itemId = (Id)rec.get('kqexe__Item__c');

        if(itemId == null){
            rec.put('kqexe__Parent_Item__c', null);
            continue;
        }

        Item__c item = itemMap.get(itemId);

        if(item != null &&
           item.Item_Parent__c != null &&
           item.Item_Parent__r != null &&
           item.Item_Parent__r.Primary__c == true){

           system.debug('@@@item.kqexe__Item_Parent__c ='+item.Item_Parent__c);
            rec.put('kqexe__Parent_Item__c', item.Item_Parent__c);

        } else {
          
            rec.put('kqexe__Parent_Item__c', null);
        }
    }
}
     /*Commented by Mohsinpublic static void populateParentItemFromItem(List<SObject> records, Map<Id, SObject> oldMap) {

    Set<Id> itemIds = new Set<Id>();

    for (SObject rec : records) {

        Id itemId = (Id)rec.get('Item__c');

        if(itemId == null){
            rec.put('Parent_Item__c', null);
            continue;
        }

        if(oldMap != null){
            SObject oldRec = oldMap.get((Id)rec.get('Id'));

            if(oldRec != null && itemId == (Id)oldRec.get('Item__c')){
                continue;
            }
        }

        itemIds.add(itemId);
    }

    if(itemIds.isEmpty()){
        return;
    }

    Map<Id, Item__c> itemMap = new Map<Id, Item__c>([
        SELECT Id, Item_Parent__c, Item_Parent__r.Id, Item_Parent__r.Primary__c
        FROM Item__c
        WHERE Id IN :itemIds
    ]);

    for(SObject rec : records){

        Id itemId = (Id)rec.get('Item__c');

        if(itemId == null){
            rec.put('Parent_Item__c', null);
            continue;
        }

        Item__c item = itemMap.get(itemId);

        if(item != null &&
           item.Item_Parent__c != null &&
           item.Item_Parent__r != null &&
           item.Item_Parent__r.Primary__c == true){

            rec.put('Parent_Item__c', item.Item_Parent__c);

        } else {
            rec.put('Parent_Item__c', null);
        }
    }
}*/    
    public static void rebuildParentSearchItems(List<Item__c> newList,
                                                Map<Id, Item__c> oldMap){

        Set<Id> parentIds = new Set<Id>();

        for(Item__c rec : newList){

            if(rec.Item_Parent__c != null){
                parentIds.add(rec.Item_Parent__c);
            }

            if(oldMap != null){
                Item__c oldRec = oldMap.get(rec.Id);

                if(oldRec != null && oldRec.Item_Parent__c != null &&
                   oldRec.Item_Parent__c != rec.Item_Parent__c){

                    parentIds.add(oldRec.Item_Parent__c);
                }
            }
        }

        if(parentIds.isEmpty()){
            return;
        }

        Map<Id,List<String>> parentToNames = new Map<Id,List<String>>();

        for(Item__c child : [
            SELECT Name, Item_Parent__c
            FROM Item__c
            WHERE Item_Parent__c IN :parentIds
        ]){

            if(!parentToNames.containsKey(child.Item_Parent__c)){
                parentToNames.put(child.Item_Parent__c, new List<String>());
            }

            parentToNames.get(child.Item_Parent__c).add(child.Name);
        }

        List<Item__c> parentsToUpdate = new List<Item__c>();

        for(Id parentId : parentIds){

            String value = null;

            if(parentToNames.containsKey(parentId)){
                value = String.join(parentToNames.get(parentId), ',');
            }

            parentsToUpdate.add(new Item__c(
                Id = parentId,
                Search_Items__c = value
            ));
        }

        if(!parentsToUpdate.isEmpty()){
            update parentsToUpdate;
        }
    }
}