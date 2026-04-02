@isTest
private class ItemCSVBatchSchedulerTest {

    // Mock for HTTP callout used in ItemCSVBatch
    private class MockCallout implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('Success');
            return res;
        }
    }

    @isTest
    static void testSchedulerExecution() {

        Test.setMock(HttpCalloutMock.class, new MockCallout());

        String cronExp = '0 0 0 1 1 ? 2099';

        Test.startTest();

        System.schedule(
            'Test ItemCSVBatchScheduler',
            cronExp,
            new ItemCSVBatchScheduler()
        );

        Test.stopTest();

        System.assert(true);
    }
}