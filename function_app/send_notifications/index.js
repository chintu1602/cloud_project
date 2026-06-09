/**
 * NutriAI Health Portal - Send Notifications Azure Function
 * Timer-triggered function that runs every hour to:
 * 1. Find documents stuck in 'processing' state for >30 minutes and mark as failed.
 * 2. Find documents stuck in 'pending' state for >1 hour and mark as failed.
 */

const { Client } = require("pg");

// Environment variables
const DATABASE_URL = process.env.DATABASE_URL || "";

/**
 * Create a PostgreSQL client and connect.
 * @returns {Promise<Client>}
 */
async function getDbClient() {
    const client = new Client({ connectionString: DATABASE_URL });
    await client.connect();
    return client;
}

/**
 * Periodic cleanup function that runs every hour.
 *
 * - Finds documents stuck in 'processing' for >30 minutes and marks them as 'failed'.
 * - Finds documents stuck in 'pending' for >1 hour and marks them as 'failed'.
 */
module.exports = async function (context, timer) {
    const utcTimestamp = new Date().toISOString();

    if (timer.isPastDue) {
        context.log("The timer is past due!");
    }

    context.log(`Send Notifications function ran at ${utcTimestamp}`);

    let db;
    try {
        db = await getDbClient();

        // Find documents stuck in 'processing' for more than 30 minutes
        const stuckProcessingResult = await db.query(
            `UPDATE documents
             SET ocr_status = 'failed'
             WHERE ocr_status = 'processing'
               AND uploaded_at < NOW() - INTERVAL '30 minutes'
             RETURNING id, original_filename, uploaded_at`
        );

        for (const doc of stuckProcessingResult.rows) {
            context.log.warn(
                `Document ${doc.id} (${doc.original_filename}) stuck in processing. ` +
                `Uploaded at ${doc.uploaded_at}. Marking as failed.`
            );
        }

        // Find documents stuck in 'pending' for more than 1 hour
        const stuckPendingResult = await db.query(
            `UPDATE documents
             SET ocr_status = 'failed'
             WHERE ocr_status = 'pending'
               AND uploaded_at < NOW() - INTERVAL '1 hour'
             RETURNING id, original_filename, uploaded_at`
        );

        for (const doc of stuckPendingResult.rows) {
            context.log.warn(
                `Document ${doc.id} (${doc.original_filename}) stuck in pending. ` +
                `Uploaded at ${doc.uploaded_at}. Marking as failed.`
            );
        }

        const totalUpdated = stuckProcessingResult.rowCount + stuckPendingResult.rowCount;
        if (totalUpdated > 0) {
            context.log(`Updated ${totalUpdated} stuck documents to 'failed' status.`);
        } else {
            context.log("No stuck documents found.");
        }
    } catch (error) {
        context.log.error(`Error in send_notifications function: ${error.message}`);
    } finally {
        if (db) {
            await db.end();
        }
    }
};
