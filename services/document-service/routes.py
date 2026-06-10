"""
Document Service - API Routes
"""

import logging

from fastapi import APIRouter, BackgroundTasks, Depends, Request, UploadFile, File, Form, HTTPException
from fastapi.responses import JSONResponse, RedirectResponse
from sqlalchemy.orm import Session

from config import get_settings
from database import get_db
from models import Document
from services import upload_document, get_document_url, delete_document_blob

logger = logging.getLogger(__name__)
settings = get_settings()

router = APIRouter(prefix="/documents", tags=["Documents"])

ALLOWED_EXTENSIONS = {"pdf", "png", "jpg", "jpeg"}
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB


def process_document_ocr(document_id: str, blob_name: str):
    """
    Background task: download blob, run OCR, update database.
    """
    from database import SessionLocal
    from azure.ai.formrecognizer import DocumentAnalysisClient
    from azure.core.credentials import AzureKeyCredential

    db = SessionLocal()
    try:
        # Download blob
        from services import get_blob_service_client
        blob_service_client = get_blob_service_client()
        container_client = blob_service_client.get_container_client(settings.AZURE_STORAGE_CONTAINER_NAME)
        blob_client = container_client.get_blob_client(blob_name)
        download_stream = blob_client.download_blob()
        document_content = download_stream.readall()
        logger.info(f"Downloaded blob {blob_name}: {len(document_content)} bytes")

        # Run OCR
        client = DocumentAnalysisClient(
            endpoint=settings.AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT,
            credential=AzureKeyCredential(settings.AZURE_DOCUMENT_INTELLIGENCE_KEY),
        )
        poller = client.begin_analyze_document(model_id="prebuilt-read", document=document_content)
        result = poller.result()

        extracted_text = ""
        for page in result.pages:
            for line in page.lines:
                extracted_text += line.content + "\n"
            extracted_text += "\n"

        if result.tables:
            extracted_text += "\n--- Tables ---\n"
            for table_idx, table in enumerate(result.tables):
                extracted_text += f"\nTable {table_idx + 1}:\n"
                current_row = -1
                row_data = []
                for cell in table.cells:
                    if cell.row_index != current_row:
                        if row_data:
                            extracted_text += " | ".join(row_data) + "\n"
                        row_data = []
                        current_row = cell.row_index
                    row_data.append(cell.content)
                if row_data:
                    extracted_text += " | ".join(row_data) + "\n"

        extracted_text = extracted_text.strip()
        logger.info(f"OCR completed for {document_id}: {len(extracted_text)} characters extracted")

        # Update document record
        document = db.query(Document).filter(Document.id == document_id).first()
        if document:
            document.ocr_content = extracted_text
            document.ocr_status = "completed"
            db.commit()

    except Exception as e:
        logger.error(f"Error processing document {document_id}: {e}")
        try:
            document = db.query(Document).filter(Document.id == document_id).first()
            if document:
                document.ocr_status = "failed"
                db.commit()
        except Exception:
            db.rollback()
    finally:
        db.close()


@router.get("/list")
async def list_documents(request: Request, db: Session = Depends(get_db)):
    user_id = request.headers.get("X-User-ID")
    if not user_id:
        raise HTTPException(status_code=401, detail="Not authenticated")

    documents = (
        db.query(Document)
        .filter(Document.user_id == user_id)
        .order_by(Document.uploaded_at.desc())
        .all()
    )

    return [
        {
            "id": str(doc.id),
            "document_type": doc.document_type,
            "original_filename": doc.original_filename,
            "blob_url": doc.blob_url,
            "ocr_status": doc.ocr_status,
            "uploaded_at": doc.uploaded_at.isoformat(),
        }
        for doc in documents
    ]


@router.post("/upload")
async def upload_doc(
    request: Request,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    document_type: str = Form("other"),
    db: Session = Depends(get_db),
):
    user_id = request.headers.get("X-User-ID")
    if not user_id:
        raise HTTPException(status_code=401, detail="Not authenticated")

    file_extension = file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else ""
    if file_extension not in ALLOWED_EXTENSIONS:
        return JSONResponse(
            status_code=400,
            content={"error": f"Invalid file type. Allowed: {', '.join(ALLOWED_EXTENSIONS)}"},
        )

    file_content = await file.read()
    if len(file_content) > MAX_FILE_SIZE:
        return JSONResponse(status_code=400, content={"error": "File size exceeds 10MB limit."})

    if len(file_content) == 0:
        return JSONResponse(status_code=400, content={"error": "File is empty."})

    try:
        blob_result = upload_document(
            file_content=file_content,
            original_filename=file.filename,
            content_type=file.content_type or "application/octet-stream",
        )

        document = Document(
            user_id=user_id,
            document_type=document_type,
            original_filename=file.filename,
            blob_name=blob_result["blob_name"],
            blob_url=blob_result["blob_url"],
            ocr_status="pending",
        )
        db.add(document)
        db.commit()
        db.refresh(document)

        # Run OCR processing in background
        document.ocr_status = "processing"
        db.commit()
        background_tasks.add_task(process_document_ocr, str(document.id), document.blob_name)

        return JSONResponse(content={
            "message": "Document uploaded successfully.",
            "document_id": str(document.id),
            "status": document.ocr_status,
        })

    except Exception as e:
        logger.error(f"Error uploading document: {e}")
        return JSONResponse(status_code=500, content={"error": "Failed to upload document."})


@router.get("/{document_id}/status")
async def document_status(
    document_id: str,
    request: Request,
    db: Session = Depends(get_db),
):
    user_id = request.headers.get("X-User-ID")
    document = db.query(Document).filter(
        Document.id == document_id,
        Document.user_id == user_id,
    ).first()

    if not document:
        return JSONResponse(status_code=404, content={"error": "Document not found."})

    return {"id": str(document.id), "ocr_status": document.ocr_status}


@router.get("/{document_id}/preview")
async def document_preview(
    document_id: str,
    request: Request,
    db: Session = Depends(get_db),
):
    user_id = request.headers.get("X-User-ID")
    document = db.query(Document).filter(
        Document.id == document_id,
        Document.user_id == user_id,
    ).first()

    if not document:
        raise HTTPException(status_code=404, detail="Document not found.")

    try:
        sas_url = get_document_url(document.blob_name)
        return JSONResponse(content={"preview_url": sas_url})
    except Exception as e:
        logger.error(f"Error generating preview URL: {e}")
        raise HTTPException(status_code=500, detail="Failed to generate preview URL.")


@router.delete("/{document_id}")
async def delete_doc(
    document_id: str,
    request: Request,
    db: Session = Depends(get_db),
):
    user_id = request.headers.get("X-User-ID")
    document = db.query(Document).filter(
        Document.id == document_id,
        Document.user_id == user_id,
    ).first()

    if not document:
        return JSONResponse(status_code=404, content={"error": "Document not found."})

    try:
        try:
            delete_document_blob(document.blob_name)
        except Exception as e:
            logger.warning(f"Could not delete blob {document.blob_name}: {e}")

        db.delete(document)
        db.commit()
        return JSONResponse(content={"message": "Document deleted successfully."})

    except Exception as e:
        logger.error(f"Error deleting document: {e}")
        db.rollback()
        return JSONResponse(status_code=500, content={"error": "Failed to delete document."})
