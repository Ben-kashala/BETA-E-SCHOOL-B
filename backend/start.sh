#!/usr/bin/env bash
set -e
# Railway fournit PORT à l'exécution ; obligatoire pour que le proxy atteigne l'app
PORT="${PORT:-8000}"
mkdir -p staticfiles
python manage.py migrate --noinput
python manage.py collectstatic --noinput
# --log-file - envoie les logs sur stdout (évite "severity: error" sur Railway)
exec gunicorn config.wsgi:application --bind "0.0.0.0:${PORT}" --log-file -
