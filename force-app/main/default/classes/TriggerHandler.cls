/**
 * TriggerHandler
 *
 * Base class for all trigger handlers. Subclass this and override only the
 * event methods you need. The trigger itself becomes a single line:
 *
 *   new MyObjectTriggerHandler().run();
 *
 * Admin skip (Trigger_Setting__mdt):
 *   DeveloperName = {ClassName}             → skips the entire handler class
 *   DeveloperName = {ClassName}_{MethodName} → skips that specific method only
 *   Deleting the record re-enables it. No deployment needed.
 *   e.g. DeveloperName = ItemTriggerHandler            → skips all methods
 *        DeveloperName = ItemTriggerHandler_afterUpdate → skips afterUpdate only
 */
public virtual class TriggerHandler {

    // Cached CMT settings for the transaction — getAll() is in-memory, no SOQL
    private static Map<String, Trigger_Setting__mdt> settingsCache;

    private String handlerName;

    public TriggerHandler() {
        this.handlerName = getHandlerName();
        if (settingsCache == null) {
            settingsCache = Trigger_Setting__mdt.getAll();
        }
    }

    // ─── Main Entry Point ─────────────────────────────────────────────────────

    public void run() {
        if (!Trigger.isExecuting) return;
        if (settingsCache.containsKey(handlerName)) return;

        if (Trigger.isBefore) {
            if      (Trigger.isInsert   && isMethodActive('beforeInsert'))   beforeInsert();
            else if (Trigger.isUpdate   && isMethodActive('beforeUpdate'))   beforeUpdate();
            else if (Trigger.isDelete   && isMethodActive('beforeDelete'))   beforeDelete();
            else if (Trigger.isUndelete && isMethodActive('beforeUndelete')) beforeUndelete();
        } else {
            if      (Trigger.isInsert   && isMethodActive('afterInsert'))    afterInsert();
            else if (Trigger.isUpdate   && isMethodActive('afterUpdate'))    afterUpdate();
            else if (Trigger.isDelete   && isMethodActive('afterDelete'))    afterDelete();
            else if (Trigger.isUndelete && isMethodActive('afterUndelete'))  afterUndelete();
        }
    }

    // ─── Virtual Event Methods — override in subclass as needed ──────────────

    protected virtual void beforeInsert()   {}
    protected virtual void beforeUpdate()   {}
    protected virtual void beforeDelete()   {}
    protected virtual void beforeUndelete() {}
    protected virtual void afterInsert()    {}
    protected virtual void afterUpdate()    {}
    protected virtual void afterDelete()    {}
    protected virtual void afterUndelete()  {}

    // ─── Internal ─────────────────────────────────────────────────────────────

    // Record exists in Trigger_Setting__mdt → skip. No record → run.
    private Boolean isMethodActive(String methodName) {
        return !settingsCache.containsKey(handlerName + '_' + methodName);
    }

    private String getHandlerName() {
        return String.valueOf(this).split(':')[0];
    }
}