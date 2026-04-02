@IsTest
global class MockAmazonCallout implements HttpCalloutMock {

    global HTTPResponse respond(HTTPRequest req) {

        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBody('Success');

        return res;
    }
}