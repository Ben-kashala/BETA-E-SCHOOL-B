"""
Teste l'obtention d'un token OAuth2 Airtel avec les variables d'environnement actuelles.
Usage:
  python manage.py test_airtel_token

À lancer en local (avec .env) ou sur Railway (one-off) pour vérifier AIRTEL_API_KEY / AIRTEL_API_SECRET / AIRTEL_API_BASE_URL.
"""
from django.conf import settings
from django.core.management.base import BaseCommand

from apps.payments.services.airtel_service import AirtelService


class Command(BaseCommand):
    help = "Teste l'authentification Airtel (token OAuth2) avec les variables d'environnement."

    def handle(self, *args, **options):
        api_key = (getattr(settings, "AIRTEL_API_KEY", "") or "").strip()
        api_secret = (getattr(settings, "AIRTEL_API_SECRET", "") or "").strip()
        api_base = (getattr(settings, "AIRTEL_API_BASE_URL", "") or "").strip()

        self.stdout.write(f"AIRTEL_API_BASE_URL = {api_base or '(vide)'}")
        self.stdout.write(f"AIRTEL_API_KEY      = {api_key[:4]}...{api_key[-2:] if len(api_key) > 6 else '***'} (longueur {len(api_key)})")
        self.stdout.write(f"AIRTEL_API_SECRET   = {'***' if api_secret else '(vide)'} (longueur {len(api_secret)})")

        if not api_base or not api_key or not api_secret:
            self.stdout.write(self.style.ERROR("Manque AIRTEL_API_BASE_URL, AIRTEL_API_KEY ou AIRTEL_API_SECRET."))
            return

        ok, token_or_error = AirtelService._get_token(api_base, api_key, api_secret)
        if ok:
            self.stdout.write(self.style.SUCCESS("Token Airtel obtenu avec succès."))
        else:
            self.stdout.write(self.style.ERROR(f"Échec: {token_or_error}"))
