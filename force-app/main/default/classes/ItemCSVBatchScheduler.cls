global class ItemCSVBatchScheduler implements Schedulable {

    global void execute(SchedulableContext sc) {

        Database.executeBatch(new ItemCSVBatch(), AppConstants.DEFAULT_BATCH_SIZE);

    }
}