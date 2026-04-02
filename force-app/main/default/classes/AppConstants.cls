public class AppConstants {

    // Batch sizes
    public static final Integer DEFAULT_BATCH_SIZE = 200;

    // Repair Status values
    public static final String REPAIR_ACTION_REPAIR = 'REPAIR';
    public static final String REPAIR_ACTION_RECYCLE = 'RECYCLE';
    public static final String REPAIR_ACTION_AWR = 'AWR';

    // Named Credentials
    public static final String AMAZON_ENDPOINT = 'callout:Amazon_API_Endpoint';

    // File naming
    public static final String FILE_PREFIX = 'Disposition_';
    public static final String FILE_EXTENSION = '.csv';

    // Metadata names
    public static final String BATCH_REPAIR_SOQL_CONFIG = 'BatchCalculateRepairAction_SOQL1';

}