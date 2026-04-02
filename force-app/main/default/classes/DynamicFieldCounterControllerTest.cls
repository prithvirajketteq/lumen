@IsTest
private class DynamicFieldCounterControllerTest {

    @IsTest
    static void testGetFieldTotals_basic() {

        // Create parent record
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create child records
        Opportunity opp1 = new Opportunity(
            Name = 'Opp 1',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Amount = 100,
            AccountId = acc.Id
        );

        Opportunity opp2 = new Opportunity(
            Name = 'Opp 2',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Amount = 200,
            AccountId = acc.Id
        );

        insert new List<Opportunity>{opp1, opp2};

        Test.startTest();

        Map<String,Object> result =
            DynamicFieldCounterController.getFieldTotals(
                'Opportunity',
                'AccountId',
                new List<String>{'Amount'},
                null,
                acc.Id
            );

        Test.stopTest();

        Map<String,Decimal> totals =
            (Map<String,Decimal>)result.get('totals');

        System.assertEquals(
            300,
            totals.get('Amount'),
            'Total Amount should equal sum of opportunity amounts'
        );

        Map<String,String> labels =
            (Map<String,String>)result.get('labels');

        System.assertEquals(
            'Amount',
            labels.get('Amount'),
            'Field label should be returned'
        );
    }


    @IsTest
    static void testGetFieldTotals_withFilter() {

        Account acc = new Account(Name = 'Filter Test');
        insert acc;

        Opportunity opp1 = new Opportunity(
            Name = 'Opp Filter 1',
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Amount = 100,
            AccountId = acc.Id
        );

        Opportunity opp2 = new Opportunity(
            Name = 'Opp Filter 2',
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Amount = 500,
            AccountId = acc.Id
        );

        insert new List<Opportunity>{opp1, opp2};

        Test.startTest();

        Map<String,Object> result =
            DynamicFieldCounterController.getFieldTotals(
                'Opportunity',
                'AccountId',
                new List<String>{'Amount'},
                'StageName = \'Closed Won\'',
                acc.Id
            );

        Test.stopTest();

        Map<String,Decimal> totals =
            (Map<String,Decimal>)result.get('totals');

        System.assertEquals(
            500,
            totals.get('Amount'),
            'Filter should include only Closed Won opportunity'
        );
    }


    @IsTest
static void testGetFieldTotals_noMatchingRecords() {

    // Create parent record
    Account acc = new Account(Name = 'No Child Records');
    insert acc;

    Test.startTest();

    Map<String,Object> result =
        DynamicFieldCounterController.getFieldTotals(
            'Opportunity',
            'AccountId',
            new List<String>{'Amount'},
            null,
            acc.Id
        );

    Test.stopTest();

    Map<String,Decimal> totals =
        (Map<String,Decimal>)result.get('totals');

    System.assertEquals(
    null,
    totals.get('Amount'),
    'Sum should return null when no child records exist'
);
}

}