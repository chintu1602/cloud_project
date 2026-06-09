/**
 * NutriAI Health Portal - Process Documents Azure Function
 * HTTP-triggered function that performs OCR on uploaded medical documents
 * using Azure Document Intelligence, then updates the database record.
 */

const { DocumentAnalysisClient, AzureKeyCredential } = require("@azure/ai-form-recognizer");
const { BlobServiceClient } = require("@azure/storage-blob");
const { Client } = require("pg");

// Environment variables
const DATABASE_URL = process.env.DATABASE_URL || "";
const AZURE_STORAGE_CONNECTION_STRING = process.env.AZURE_STORAGE_CONNECTION_STRING || "";
const AZURE_STORAGE_CONTAINER_NAME = process.env.AZURE_STORAGE_CONTAINER_NAME || "health-documents";
const AZURE_DOC_INTELLIGENCE_ENDPOINT = process.env.AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT || "";
const AZURE_DOC_INTELLIGENCE_KEY = process.env.AZURE_DOCUMENT_INTELLIGENCE_KEY || "";

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
 * Download a blob's content from Azure Storage.
 * @param {string} blobName
 * @returns {Promise<Buffer>}
 */
async function downloadBlob(blobName) {
    const blobServiceClient = BlobServiceClient.fromConnectionString(AZURE_STORAGE_CONNECTION_STRING);
    const containerClient = blobServiceClient.getContainerClient(AZURE_STORAGE_CONTAINER_NAME);
    const blobClient = containerClient.getBlobClient(blobName);
    const downloadResponse = await blobClient.download(0);

    // Read the stream into a buffer
    const chunks = [];
    for await (const chunk of downloadResponse.readableStreamBody) {
        chunks.push(chunk);
    }
    return Buffer.concat(chunks);
}

/**
 * Run Azure Document Intelligence OCR on document content.
 * @param {Buffer} documentContent
 * @returns {Promise<string>}
 */
async function runOcr(documentContent) {
    const client = new DocumentAnalysisClient(
        AZURE_DOC_INTELLIGENCE_ENDPOINT,
        new AzureKeyCredential(AZURE_DOC_INTELLIGENCE_KEY)
    );

    const poller = await client.beginAnalyzeDocument("prebuilt-read", documentContent);
    const result = await poller.pollUntilDone();

    // Extract all text content
    let extractedText = "";
    if (result.pages) {
        for (const page of result.pages) {
            if (page.lines) {
                for (const line of page.lines) {
                    extractedText += line.content + "\n";
                }
            }
            extractedText += "\n";
        }
    }

    // Extract tables
    if (result.tables && result.tables.length > 0) {
        extractedText += "\n--- Tables ---\n";
        for (let tableIdx = 0; tableIdx < result.tables.length; tableIdx++) {
            const table = result.tables[tableIdx];
            extractedText += `\nTable ${tableIdx + 1}:\n`;
            let currentRow = -1;
            let rowData = [];
            for (const cell of table.cells) {
                if (cell.rowIndex !== currentRow) {
                    if (rowData.length > 0) {
                        extractedText += rowData.join(" | ") + "\n";
                    }
                    rowData = [];
                    currentRow = cell.rowIndex;
                }
                rowData.push(cell.content);
            }
            if (rowData.length > 0) {
                extractedText += rowData.join(" | ") + "\n";
            }
        }
    }

    return extractedText.trim();
}

/**
 * Process a document: download from Blob Storage, run OCR, update database.
 *
 * Expected JSON body:
 *   {
 *     "document_id": "uuid-string",
 *     "blob_name": "uuid.pdf"
 *   }
 */
module.exports = async function (context, req) {
    context.log("Process Documents function triggered.");

    // Parse request body
    const documentId = req.body && req.body.document_id;
    const blobName = req.body && req.body.blob_name;

    if (!documentId || !blobName) {
        context.res = {
            status: 400,
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ error: "Missing document_id or blob_name" }),
        };
        return;
    }

    let db;
    try {
        db = await getDbClient();

        // Find the document record
        const findResult = await db.query("SELECT id, ocr_status FROM documents WHERE id = $1", [documentId]);
        if (findResult.rows.length === 0) {
            context.res = {
                status: 404,
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ error: "Document not found" }),
            };
            return;
        }

        // Update status to processing
        await db.query("UPDATE documents SET ocr_status = 'processing' WHERE id = $1", [documentId]);
        context.log(`Processing document ${documentId}: ${blobName}`);

        // Download blob content
        const documentContent = await downloadBlob(blobName);
        context.log(`Downloaded blob ${blobName}: ${documentContent.length} bytes`);

        // Run OCR
        const extractedText = await runOcr(documentContent);
        context.log(`OCR completed for ${documentId}: ${extractedText.length} characters extracted`);

        // Update document record with results
        await db.query(
            "UPDATE documents SET ocr_content = $1, ocr_status = 'completed' WHERE id = $2",
            [extractedText, documentId]
        );

        context.res = {
            status: 200,
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                status: "completed",
                document_id: documentId,
                characters_extracted: extractedText.length,
            }),
        };
    } catch (error) {
        context.log.error(`Error processing document ${documentId}: ${error.message}`);

        // Mark as failed in database
        try {
            if (db) {
                await db.query("UPDATE documents SET ocr_status = 'failed' WHERE id = $1", [documentId]);
            }
        } catch (dbError) {
            context.log.error(`Failed to update document status: ${dbError.message}`);
        }

        context.res = {
            status: 500,
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ error: error.message }),
        };
    } finally {
        if (db) {
            await db.end();
        }
    }
};
