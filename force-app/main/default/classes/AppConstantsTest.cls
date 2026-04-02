@IsTest
private class AppConstantsTest {

    @IsTest
    static void validateConstants() {

        System.assertEquals(200, AppConstants.DEFAULT_BATCH_SIZE);

        System.assertEquals('REPAIR', AppConstants.REPAIR_ACTION_REPAIR);
        System.assertEquals('RECYCLE', AppConstants.REPAIR_ACTION_RECYCLE);
        System.assertEquals('AWR', AppConstants.REPAIR_ACTION_AWR);

        System.assertEquals('callout:Amazon_API_Endpoint', AppConstants.AMAZON_ENDPOINT);

        System.assertEquals('Disposition_', AppConstants.FILE_PREFIX);
        System.assertEquals('.csv', AppConstants.FILE_EXTENSION);

        System.assertEquals(
            'BatchCalculateRepairAction_SOQL1',
            AppConstants.BATCH_REPAIR_SOQL_CONFIG
        );
    }
}