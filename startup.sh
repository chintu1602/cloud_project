# ============================================================
# NutriAI Health Portal - Startup Script
# Runs Alembic migrations then starts Gunicorn with Uvicorn workers
# ============================================================

set -e

echo "🌿 Starting NutriAI Health Portal..."

# Run database migrations
echo "📦 Running database migrations..."
alembic upgrade head 2>/dev/null || echo "⚠️  Alembic migrations skipped (no migrations configured yet)"

# Start the application with Gunicorn + Uvicorn workers
echo "🚀 Starting Gunicorn with Uvicorn workers..."
exec gunicorn app.main:app \
    --bind 0.0.0.0:8000 \
    --workers 4 \
    --worker-class uvicorn.workers.UvicornWorker \
    --timeout 120 \
    --keep-alive 5 \
    --access-logfile - \
    --error-logfile - \
    --log-level info
