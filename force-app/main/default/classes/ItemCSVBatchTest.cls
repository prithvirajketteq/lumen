@IsTest
private class ItemCSVBatchTest {

    private class AmazonMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            System.assertEquals('POST', req.getMethod());

            String fileName = req.getHeader('File-Name');

            System.assertNotEquals(null, fileName);
            System.assert(fileName.startsWith(AppConstants.FILE_PREFIX));
            System.assert(fileName.endsWith(AppConstants.FILE_EXTENSION));

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('SUCCESS');

            return res;
        }
    }

    @testSetup
    static void setupData() {

        TestDataFactory.createItems(5);

    }

    @IsTest
    static void testItemCSVBatchExecution() {

        Test.setMock(HttpCalloutMock.class, new AmazonMock());

        Test.startTest();

        Database.executeBatch(new ItemCSVBatch(), AppConstants.DEFAULT_BATCH_SIZE);

        Test.stopTest();

        System.assert(true);

    }
}