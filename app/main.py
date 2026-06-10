"""
NutriAI Health Portal - Main Application Entry Point
FastAPI application with Jinja2 templates, static files, and all routers.
"""

import asyncio
import logging
from datetime import date, datetime, timedelta

from fastapi import FastAPI, Request, Depends
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.config import get_settings
from app.database import engine, Base, get_db
from app.dependencies import get_current_user, get_current_user_optional
from app.models.user import User, FoodAllergy
from app.models.document import Document
from app.models.diet_plan import DietPlan
from app.models.health_log import HealthLog

# Import all models to register with Base
from app.models import *

from app.routers import auth, documents, diet_plans, health_tracker, profile, notifications, admin

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

settings = get_settings()

# Create FastAPI application
app = FastAPI(
    title=settings.APP_NAME,
    description="AI-powered diet planning system for patients",
    version="1.0.0",
)

# Mount static files
app.mount("/static", StaticFiles(directory="static"), name="static")

# Setup Jinja2 templates
templates = Jinja2Templates(directory="app/templates")

# Include routers
app.include_router(auth.router)
app.include_router(documents.router)
app.include_router(diet_plans.router)
app.include_router(health_tracker.router)
app.include_router(profile.router)
app.include_router(notifications.router)
app.include_router(admin.router)


@app.on_event("startup")
async def startup_event():
    """Create database tables on startup and start background tasks."""
    logger.info("Starting NutriAI Health Portal...")
    Base.metadata.create_all(bind=engine)
    logger.info("Database tables created/verified.")
    asyncio.create_task(periodic_document_cleanup())
    logger.info("Background document cleanup task started.")


async def periodic_document_cleanup():
    """
    Periodic background task that runs every hour.
    Marks documents stuck in 'processing' (>30 min) or 'pending' (>1 hour) as 'failed'.
    Replaces the send_notifications Azure Function timer trigger.
    """
    while True:
        try:
            await asyncio.sleep(3600)  # Run every hour
            logger.info("Running periodic document cleanup...")

            from app.database import SessionLocal
            db = SessionLocal()
            try:
                now = datetime.utcnow()

                # Mark documents stuck in 'processing' for >30 minutes
                thirty_min_ago = now - timedelta(minutes=30)
                stuck_processing = (
                    db.query(Document)
                    .filter(
                        Document.ocr_status == "processing",
                        Document.uploaded_at < thirty_min_ago,
                    )
                    .all()
                )
                for doc in stuck_processing:
                    logger.warning(
                        f"Document {doc.id} ({doc.original_filename}) stuck in processing. "
                        f"Uploaded at {doc.uploaded_at}. Marking as failed."
                    )
                    doc.ocr_status = "failed"

                # Mark documents stuck in 'pending' for >1 hour
                one_hour_ago = now - timedelta(hours=1)
                stuck_pending = (
                    db.query(Document)
                    .filter(
                        Document.ocr_status == "pending",
                        Document.uploaded_at < one_hour_ago,
                    )
                    .all()
                )
                for doc in stuck_pending:
                    logger.warning(
                        f"Document {doc.id} ({doc.original_filename}) stuck in pending. "
                        f"Uploaded at {doc.uploaded_at}. Marking as failed."
                    )
                    doc.ocr_status = "failed"

                total_updated = len(stuck_processing) + len(stuck_pending)
                if total_updated > 0:
                    db.commit()
                    logger.info(f"Updated {total_updated} stuck documents to 'failed' status.")
                else:
                    logger.info("No stuck documents found.")

            except Exception as e:
                logger.error(f"Error in periodic document cleanup: {e}")
                db.rollback()
            finally:
                db.close()

        except asyncio.CancelledError:
            logger.info("Periodic document cleanup task cancelled.")
            break
        except Exception as e:
            logger.error(f"Unexpected error in cleanup loop: {e}")
            await asyncio.sleep(60)  # Retry after 1 minute on unexpected errors


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown."""
    logger.info("Shutting down NutriAI Health Portal...")


# ============================================================
# Landing Page
# ============================================================

@app.get("/", response_class=HTMLResponse)
async def landing_page(request: Request, current_user=Depends(get_current_user_optional)):
    """Render the landing page."""
    if current_user:
        return RedirectResponse(url="/dashboard", status_code=302)
    return templates.TemplateResponse("landing.html", {
        "request": request,
        "user": None,
    })


# ============================================================
# Dashboard
# ============================================================

@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Render the dashboard with user statistics and recent activity."""
    # Stats
    total_documents = db.query(func.count(Document.id)).filter(
        Document.user_id == current_user.id
    ).scalar()

    total_diet_plans = db.query(func.count(DietPlan.id)).filter(
        DietPlan.user_id == current_user.id
    ).scalar()

    total_health_logs = db.query(func.count(HealthLog.id)).filter(
        HealthLog.user_id == current_user.id
    ).scalar()

    total_allergies = db.query(func.count(FoodAllergy.id)).filter(
        FoodAllergy.user_id == current_user.id
    ).scalar()

    # Recent diet plan
    recent_plan = (
        db.query(DietPlan)
        .filter(DietPlan.user_id == current_user.id)
        .order_by(DietPlan.generated_at.desc())
        .first()
    )

    # Recent documents
    recent_documents = (
        db.query(Document)
        .filter(Document.user_id == current_user.id)
        .order_by(Document.uploaded_at.desc())
        .limit(5)
        .all()
    )

    # Notification count
    pending_docs = db.query(func.count(Document.id)).filter(
        Document.user_id == current_user.id,
        Document.ocr_status.in_(["pending", "processing", "failed"]),
    ).scalar()

    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "user": current_user,
        "stats": {
            "total_documents": total_documents,
            "total_diet_plans": total_diet_plans,
            "total_health_logs": total_health_logs,
            "total_allergies": total_allergies,
        },
        "recent_plan": recent_plan,
        "recent_documents": recent_documents,
        "notification_count": pending_docs,
    })


# ============================================================
# Help Page
# ============================================================

@app.get("/help", response_class=HTMLResponse)
async def help_page(
    request: Request,
    current_user=Depends(get_current_user_optional),
):
    """Render the help page."""
    return templates.TemplateResponse("help.html", {
        "request": request,
        "user": current_user,
    })
