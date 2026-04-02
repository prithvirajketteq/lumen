@IsTest
private class GenericUtilityTest {

    /*
    Test NVL utility
    */
    @IsTest
    static void testNVL() {

        System.assertEquals(0, GenericUtility.nvl(null));
        System.assertEquals(5, GenericUtility.nvl(5));

    }

    /*
    Test CSV file name generator
    */
    @IsTest
    static void testGenerateCSVFileName() {

        String fileName = GenericUtility.generateCSVFileName();

        System.assert(fileName.startsWith(AppConstants.FILE_PREFIX));
        System.assert(fileName.endsWith(AppConstants.FILE_EXTENSION));

    }

    /*
    Test Partial DML Utility
    */
    @IsTest
    static void testUpdateRecordsPartial() {

        List<Account> accounts = new List<Account>();

        accounts.add(new Account(Name='Test Account 1'));
        accounts.add(new Account(Name='Test Account 2'));

        insert accounts;

        for(Account acc : accounts){
            acc.Name = acc.Name + ' Updated';
        }

        Test.startTest();
        GenericUtility.updateRecordsPartial(accounts);
        Test.stopTest();

        List<Account> updatedAccounts = [
            SELECT Name
            FROM Account
            WHERE Id IN :accounts
        ];

        System.assertEquals(2, updatedAccounts.size());

    }

    /*
    Test HTTP Callout
    */
    @IsTest
    static void testSendCSVToAmazon() {

        Test.setMock(HttpCalloutMock.class, new MockAmazonCallout());

        Test.startTest();

        HttpResponse res =
            GenericUtility.sendCSVToAmazon('test,data', 'test.csv');

        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());

    }

}