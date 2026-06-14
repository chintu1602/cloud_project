"""
NutriAI Health Portal - Diet Plan Service
Orchestrates diet plan generation, retrieval, and PDF download.
"""

import io
import json
import logging
from datetime import datetime
from typing import Optional, List
from uuid import UUID

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle

from sqlalchemy.orm import Session

from app.models.document import Document
from app.models.diet_plan import DietPlan
from app.models.user import User, FoodAllergy
from app.services.openai_service import generate_diet_plan
from app.services.service_bus_service import publish_meal_reminders

logger = logging.getLogger(__name__)


def create_diet_plan(
    db: Session,
    user: User,
    document_ids: List[str],
    additional_notes: Optional[str] = None,
) -> Optional[DietPlan]:
    """
    Orchestrate diet plan generation:
    1. Fetch selected documents and verify ownership
    2. Gather user's food allergies
    3. Combine OCR content from documents
    4. Call OpenAI to generate diet plan
    5. Validate response and save to database
    """
    try:
        # 1. Fetch and verify documents
        documents = []
        combined_ocr = ""
        for doc_id in document_ids:
            doc = db.query(Document).filter(
                Document.id == doc_id,
                Document.user_id == user.id,
                Document.ocr_status == "completed",
            ).first()
            if doc and doc.ocr_content:
                documents.append(doc)
                combined_ocr += f"\n--- Document: {doc.original_filename} (Type: {doc.document_type}) ---\n"
                combined_ocr += doc.ocr_content + "\n"

        if not documents:
            logger.warning(f"No valid documents found for diet plan generation. User: {user.id}")
            return None

        # 2. Gather allergies
        allergies = db.query(FoodAllergy).filter(FoodAllergy.user_id == user.id).all()
        allergy_list = [
            {
                "allergen_name": a.allergen_name,
                "severity": a.severity,
                "notes": a.notes or "",
            }
            for a in allergies
        ]

        # 3. Call OpenAI
        plan_data = generate_diet_plan(
            ocr_content=combined_ocr,
            allergies=allergy_list,
            additional_notes=additional_notes,
        )

        if not plan_data:
            logger.error("OpenAI failed to generate diet plan")
            return None

        # 4. Save to database
        diet_plan = DietPlan(
            user_id=user.id,
            document_ids=[str(d.id) for d in documents],
            plan_title=plan_data.get("plan_title", "Personalized Diet Plan"),
            plan_summary=plan_data.get("plan_summary", ""),
            foods_to_eat=plan_data.get("foods_to_eat", []),
            foods_to_avoid=plan_data.get("foods_to_avoid", []),
            weekly_meal_plan=plan_data.get("weekly_meal_plan", {}),
            nutritional_guidelines=plan_data.get("nutritional_guidelines", {}),
            allergy_notes=plan_data.get("allergy_notes", []),
            additional_recommendations=plan_data.get("additional_recommendations", []),
            is_active=True,
        )
        db.add(diet_plan)
        db.commit()
        db.refresh(diet_plan)

        publish_meal_reminders(diet_plan, user.email)

        logger.info(f"Diet plan created successfully: {diet_plan.id}")
        return diet_plan

    except Exception as e:
        logger.error(f"Error creating diet plan: {e}")
        db.rollback()
        return None


def get_diet_plans(db: Session, user_id: UUID) -> List[DietPlan]:
    """Get all diet plans for a user, ordered by most recent."""
    return (
        db.query(DietPlan)
        .filter(DietPlan.user_id == user_id)
        .order_by(DietPlan.generated_at.desc())
        .all()
    )


def get_diet_plan_detail(db: Session, plan_id: UUID, user_id: UUID) -> Optional[DietPlan]:
    """Get a specific diet plan with ownership verification."""
    return (
        db.query(DietPlan)
        .filter(DietPlan.id == plan_id, DietPlan.user_id == user_id)
        .first()
    )


def generate_diet_plan_pdf(plan: DietPlan) -> bytes:
    """
    Generate a PDF document from a diet plan.
    
    Args:
        plan: DietPlan model instance
        
    Returns:
        PDF bytes
    """
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=letter, topMargin=0.5 * inch, bottomMargin=0.5 * inch)

    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "CustomTitle",
        parent=styles["Title"],
        fontSize=20,
        textColor=colors.HexColor("#2E7D32"),
        spaceAfter=12,
    )
    heading_style = ParagraphStyle(
        "CustomHeading",
        parent=styles["Heading2"],
        fontSize=14,
        textColor=colors.HexColor("#1565C0"),
        spaceAfter=8,
        spaceBefore=12,
    )
    body_style = styles["Normal"]
    body_style.fontSize = 10
    body_style.leading = 14

    elements = []

    # Title
    elements.append(Paragraph(f"🥗 {plan.plan_title}", title_style))
    elements.append(Paragraph(f"Generated: {plan.generated_at.strftime('%B %d, %Y')}", body_style))
    elements.append(Spacer(1, 12))

    # Summary
    if plan.plan_summary:
        elements.append(Paragraph("Plan Summary", heading_style))
        elements.append(Paragraph(plan.plan_summary, body_style))
        elements.append(Spacer(1, 8))

    # Foods to Eat
    if plan.foods_to_eat:
        elements.append(Paragraph("✅ Foods to Eat", heading_style))
        table_data = [["Food", "Reason", "Portion", "Timing"]]
        for food in plan.foods_to_eat:
            table_data.append([
                food.get("food_name", ""),
                food.get("reason", ""),
                food.get("portion_size", ""),
                food.get("timing", ""),
            ])
        table = Table(table_data, colWidths=[1.5 * inch, 2.5 * inch, 1.2 * inch, 1.3 * inch])
        table.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#2E7D32")),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTSIZE", (0, 0), (-1, -1), 8),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.HexColor("#E8F5E9"), colors.white]),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ]))
        elements.append(table)
        elements.append(Spacer(1, 8))

    # Foods to Avoid
    if plan.foods_to_avoid:
        elements.append(Paragraph("❌ Foods to Avoid", heading_style))
        table_data = [["Food", "Reason", "Risk Level"]]
        for food in plan.foods_to_avoid:
            table_data.append([
                food.get("food_name", ""),
                food.get("reason", ""),
                food.get("risk_level", ""),
            ])
        table = Table(table_data, colWidths=[2 * inch, 3 * inch, 1.5 * inch])
        table.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#C62828")),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTSIZE", (0, 0), (-1, -1), 8),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.HexColor("#FFEBEE"), colors.white]),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ]))
        elements.append(table)
        elements.append(Spacer(1, 8))

    # Weekly Meal Plan
    if plan.weekly_meal_plan:
        elements.append(Paragraph("📅 Weekly Meal Plan", heading_style))
        days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for day in days:
            day_plan = plan.weekly_meal_plan.get(day, {})
            if day_plan:
                elements.append(Paragraph(f"<b>{day.capitalize()}</b>", body_style))
                for meal_type in ["breakfast", "lunch", "dinner", "snacks"]:
                    meal = day_plan.get(meal_type, "")
                    if meal:
                        elements.append(Paragraph(f"  • {meal_type.capitalize()}: {meal}", body_style))
                elements.append(Spacer(1, 4))

    # Nutritional Guidelines
    if plan.nutritional_guidelines:
        elements.append(Paragraph("📊 Nutritional Guidelines", heading_style))
        ng = plan.nutritional_guidelines
        guidelines_text = f"""
        Daily Calories: {ng.get('daily_calories', 'N/A')} kcal |
        Protein: {ng.get('protein_grams', 'N/A')}g |
        Carbs: {ng.get('carbs_grams', 'N/A')}g |
        Fats: {ng.get('fats_grams', 'N/A')}g |
        Fiber: {ng.get('fiber_grams', 'N/A')}g |
        Water: {ng.get('water_liters', 'N/A')}L
        """
        elements.append(Paragraph(guidelines_text.strip(), body_style))
        elements.append(Spacer(1, 8))

    # Allergy Notes
    if plan.allergy_notes:
        elements.append(Paragraph("⚠️ Allergy Notes", heading_style))
        for note in plan.allergy_notes:
            elements.append(Paragraph(f"• {note}", body_style))
        elements.append(Spacer(1, 8))

    # Additional Recommendations
    if plan.additional_recommendations:
        elements.append(Paragraph("💡 Additional Recommendations", heading_style))
        for rec in plan.additional_recommendations:
            elements.append(Paragraph(f"• {rec}", body_style))

    # Footer
    elements.append(Spacer(1, 20))
    footer_style = ParagraphStyle("Footer", parent=body_style, fontSize=8, textColor=colors.grey)
    elements.append(Paragraph(
        "Generated by NutriAI Health Portal. This plan is AI-generated and should be reviewed by a healthcare professional.",
        footer_style,
    ))

    doc.build(elements)
    pdf_bytes = buffer.getvalue()
    buffer.close()
    return pdf_bytes
