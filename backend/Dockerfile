FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    postgresql-client \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy project
COPY . .

# Create logs and staticfiles directories
RUN mkdir -p logs staticfiles

# Expose port
EXPOSE 8000

# Run migrations, collect static files, create/correct superadmin, and start server with gunicorn
# NOTE: seed_initial est temporairement ajouté pour créer/corriger le superadmin
# Retirez-le après le premier démarrage réussi pour éviter de réexécuter à chaque redéploiement
CMD ["sh", "-c", "mkdir -p staticfiles && python manage.py migrate --noinput && python manage.py collectstatic --noinput && python manage.py seed_initial && exec gunicorn config.wsgi:application --bind 0.0.0.0:${PORT:-8000} --log-file -"]
