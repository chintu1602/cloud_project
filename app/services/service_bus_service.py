"""
NutriAI Health Portal - Service Bus Service
Meal reminder pipeline:
  - publish_meal_reminders(): publishes 28 scheduled messages after diet plan generation
  - service_bus_consumer():   async background task that consumes messages and sends emails
"""

import asyncio
import json
import logging
import smtplib
from datetime import datetime, timedelta
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Optional

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


# ============================================================
# Email
# ============================================================

def build_meal_reminder_html(data: dict) -> str:
    """Build styled HTML email for a meal reminder."""
    meal_type = data.get("meal_type", "meal").capitalize()
    day_name = data.get("day_name", "Today")
    foods_to_eat = data.get("foods_to_eat", [])
    foods_to_avoid = data.get("foods_to_avoid", [])
    app_url = settings.APP_URL

    eat_rows = ""
    for food in foods_to_eat:
        eat_rows += f"""
        <tr>
            <td style="padding:8px 12px;border-bottom:1px solid #e0e0e0;color:#333">{food.get('food_name','')}</td>
            <td style="padding:8px 12px;border-bottom:1px solid #e0e0e0;color:#666">{food.get('portion_size','')}</td>
            <td style="padding:8px 12px;border-bottom:1px solid #e0e0e0;color:#666">{food.get('timing','')}</td>
        </tr>"""

    avoid_rows = ""
    for food in foods_to_avoid:
        avoid_rows += f"""
        <tr>
            <td style="padding:8px 12px;border-bottom:1px solid #e0e0e0;color:#333">{food.get('food_name','')}</td>
            <td style="padding:8px 12px;border-bottom:1px solid #e0e0e0;color:#666">{food.get('reason','')}</td>
            <td style="padding:8px 12px;border-bottom:1px solid #e0e0e0;color:#666">{food.get('risk_level','')}</td>
        </tr>"""

    return f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;font-family:Arial,sans-serif;background:#f5f5f5">
  <div style="max-width:600px;margin:0 auto;background:#fff">
    <div style="background:linear-gradient(135deg,#2E7D32 0%,#1565C0 100%);padding:24px;text-align:center">
      <h1 style="color:#fff;margin:0;font-size:24px">🍽️ NutriAI Meal Reminder</h1>
      <p style="color:rgba(255,255,255,.9);margin:8px 0 0;font-size:14px">Your {meal_type} for {day_name}</p>
    </div>
    <div style="padding:24px">
      <h2 style="color:#2E7D32;font-size:18px;border-bottom:2px solid #2E7D32;padding-bottom:8px">✅ What to Eat</h2>
      <table style="width:100%;border-collapse:collapse;background:#E8F5E9;border-radius:8px;overflow:hidden">
        <thead>
          <tr style="background:#2E7D32">
            <th style="padding:10px 12px;text-align:left;color:#fff;font-size:13px">Food</th>
            <th style="padding:10px 12px;text-align:left;color:#fff;font-size:13px">Portion</th>
            <th style="padding:10px 12px;text-align:left;color:#fff;font-size:13px">Timing</th>
          </tr>
        </thead>
        <tbody>{eat_rows}</tbody>
      </table>
      <h2 style="color:#C62828;font-size:18px;border-bottom:2px solid #C62828;padding-bottom:8px;margin-top:24px">❌ What NOT to Eat</h2>
      <table style="width:100%;border-collapse:collapse;background:#FFEBEE;border-radius:8px;overflow:hidden">
        <thead>
          <tr style="background:#C62828">
            <th style="padding:10px 12px;text-align:left;color:#fff;font-size:13px">Food</th>
            <th style="padding:10px 12px;text-align:left;color:#fff;font-size:13px">Reason</th>
            <th style="padding:10px 12px;text-align:left;color:#fff;font-size:13px">Risk</th>
          </tr>
        </thead>
        <tbody>{avoid_rows}</tbody>
      </table>
    </div>
    <div style="background:#212121;padding:20px;text-align:center">
      <p style="color:rgba(255,255,255,.7);margin:0 0 8px;font-size:13px">View your full diet plan on NutriAI Health Portal</p>
      <a href="{app_url}/dashboard"
         style="display:inline-block;background:#2E7D32;color:#fff;padding:10px 24px;border-radius:20px;text-decoration:none;font-weight:600;font-size:14px">
        Open NutriAI →
      </a>
      <p style="color:rgba(255,255,255,.5);margin:12px 0 0;font-size:11px">© 2026 NutriAI Health Portal. This is an automated reminder.</p>
    </div>
  </div>
</body>
</html>"""


def send_email_smtp(to_email: str, subject: str, html_content: str) -> None:
    """Send an HTML email via SMTP with STARTTLS."""
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = settings.SMTP_FROM_EMAIL
    msg["To"] = to_email
    msg.attach(MIMEText(html_content, "html"))

    with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
        server.starttls()
        server.login(settings.SMTP_USERNAME, settings.SMTP_PASSWORD)
        server.sendmail(settings.SMTP_FROM_EMAIL, to_email, msg.as_string())

    logger.info(f"Meal reminder email sent to {to_email}")


# ============================================================
# Publisher  (called after diet plan is saved)
# ============================================================

def publish_meal_reminders(diet_plan, user_email: str) -> None:
    """
    Publish 28 scheduled Service Bus messages (7 days × 4 meals) for the
    coming week so the consumer can send emails at the right meal time.
    Silently skips if the connection string is not configured.
    """
    if not settings.AZURE_SERVICE_BUS_CONNECTION_STRING:
        logger.warning("Service Bus not configured — meal reminders skipped")
        return

    try:
        from azure.servicebus import ServiceBusClient, ServiceBusMessage

        meal_times = {
            "breakfast": 8,   # 08:00 UTC
            "lunch":     13,  # 13:00 UTC
            "snack":     16,  # 16:00 UTC
            "dinner":    19,  # 19:00 UTC
        }
        days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

        today = datetime.utcnow().date()
        days_ahead = (7 - today.weekday()) % 7 or 7
        next_monday = today + timedelta(days=days_ahead)

        weekly_plan = diet_plan.weekly_meal_plan or {}
        foods_eat = [
            {"food_name": f.get("food_name", ""), "portion_size": f.get("portion_size", ""),
             "timing": f.get("timing", ""), "reason": f.get("reason", "")}
            for f in (diet_plan.foods_to_eat or [])
        ]
        foods_avoid = [
            {"food_name": f.get("food_name", ""), "reason": f.get("reason", ""),
             "risk_level": f.get("risk_level", "")}
            for f in (diet_plan.foods_to_avoid or [])
        ]

        with ServiceBusClient.from_connection_string(settings.AZURE_SERVICE_BUS_CONNECTION_STRING) as client:
            with client.get_topic_sender(topic_name=settings.AZURE_SERVICE_BUS_TOPIC_NAME) as sender:
                count = 0
                for day_index, day_name in enumerate(days):
                    day_date = next_monday + timedelta(days=day_index)
                    day_plan = weekly_plan.get(day_name, {})

                    for meal_type, hour in meal_times.items():
                        meal_key = "snacks" if meal_type == "snack" else meal_type
                        body = json.dumps({
                            "user_id":       str(diet_plan.user_id),
                            "user_email":    user_email,
                            "meal_type":     meal_type,
                            "day_name":      day_name.capitalize(),
                            "meal_description": day_plan.get(meal_key, day_plan.get(meal_type, "")),
                            "foods_to_eat":  foods_eat,
                            "foods_to_avoid": foods_avoid,
                        })
                        scheduled_time = datetime(
                            day_date.year, day_date.month, day_date.day, hour, 0, 0
                        )
                        msg = ServiceBusMessage(
                            body=body,
                            content_type="application/json",
                            subject=f"meal-reminder-{day_name}-{meal_type}",
                            scheduled_enqueue_time_utc=scheduled_time,
                        )
                        sender.send_messages(msg)
                        count += 1

                logger.info(f"Published {count} meal reminder messages to Service Bus for {user_email}")

    except ImportError:
        logger.warning("azure-servicebus not installed — meal reminders skipped")
    except Exception as e:
        logger.error(f"Failed to publish meal reminders: {e}")


# ============================================================
# Consumer  (runs as background task inside the main app)
# ============================================================

async def service_bus_consumer() -> None:
    """
    Async background loop that subscribes to the meal-reminders Service Bus topic
    and sends emails when scheduled messages are delivered.
    Silently exits if the connection string is not configured.
    """
    if not settings.AZURE_SERVICE_BUS_CONNECTION_STRING:
        logger.warning("Service Bus not configured — consumer not started")
        return

    try:
        from azure.servicebus.aio import ServiceBusClient as AsyncServiceBusClient

        logger.info("Service Bus consumer starting...")

        async with AsyncServiceBusClient.from_connection_string(
            settings.AZURE_SERVICE_BUS_CONNECTION_STRING
        ) as client:
            receiver = client.get_subscription_receiver(
                topic_name=settings.AZURE_SERVICE_BUS_TOPIC_NAME,
                subscription_name=settings.AZURE_SERVICE_BUS_SUBSCRIPTION_NAME,
            )
            async with receiver:
                while True:
                    try:
                        messages = await receiver.receive_messages(max_message_count=10, max_wait_time=30)
                        for msg in messages:
                            try:
                                data = json.loads(str(msg))
                                user_email = data.get("user_email", "")
                                meal_type = data.get("meal_type", "meal").capitalize()
                                day_name = data.get("day_name", "Today")

                                if user_email and settings.SMTP_USERNAME:
                                    subject = f"NutriAI Reminder: Your {meal_type} for {day_name}"
                                    html = build_meal_reminder_html(data)
                                    send_email_smtp(user_email, subject, html)
                                else:
                                    logger.warning(
                                        f"Skipping email — user_email={bool(user_email)}, "
                                        f"smtp_configured={bool(settings.SMTP_USERNAME)}"
                                    )

                                await receiver.complete_message(msg)
                                logger.info(f"Processed meal reminder: {meal_type} for {day_name} → {user_email}")

                            except Exception as e:
                                logger.error(f"Error processing Service Bus message: {e}")
                                await receiver.abandon_message(msg)

                    except asyncio.CancelledError:
                        logger.info("Service Bus consumer cancelled")
                        return
                    except Exception as e:
                        logger.error(f"Service Bus receive error: {e}")
                        await asyncio.sleep(10)

    except ImportError:
        logger.warning("azure-servicebus not installed — consumer not started")
    except asyncio.CancelledError:
        logger.info("Service Bus consumer task cancelled")
    except Exception as e:
        logger.error(f"Service Bus consumer fatal error: {e}")
