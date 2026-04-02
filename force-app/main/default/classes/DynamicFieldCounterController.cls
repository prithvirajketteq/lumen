public with sharing class DynamicFieldCounterController {

    @AuraEnabled(cacheable=true)
    public static Map<String,Object> getFieldTotals(
        String childObject,
        String parentLookupField,
        List<String> fieldNames,
        String filterCondition,
        Id parentId
    ){

        Map<String,Object> result = new Map<String,Object>();
        Map<String,Decimal> totals = new Map<String,Decimal>();
        Map<String,String> labels = new Map<String,String>();

        Schema.DescribeSObjectResult objDescribe =
            Schema.getGlobalDescribe().get(childObject).getDescribe();

        Map<String,Schema.SObjectField> fieldMap =
            objDescribe.fields.getMap();

        List<String> aggregates = new List<String>();

        for(String field : fieldNames){

            aggregates.add('SUM(' + field + ') ' + field);

            labels.put(
                field,
                fieldMap.get(field).getDescribe().getLabel()
            );
        }

        String soql =
            'SELECT ' + String.join(aggregates, ',') +
            ' FROM ' + childObject +
            ' WHERE ' + parentLookupField + ' = :parentId';

        if(String.isNotBlank(filterCondition)){
            soql += ' AND (' + filterCondition + ')';
        }

        AggregateResult ar = Database.query(soql);

        for(String field : fieldNames){
            totals.put(field,(Decimal)ar.get(field));
        }

        result.put('totals', totals);
        result.put('labels', labels);

        return result;
    }
}