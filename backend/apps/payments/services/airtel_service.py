"""
Airtel Money — initiation paiement.
Utilise les clés API globales (AIRTEL_API_KEY, AIRTEL_API_SECRET, AIRTEL_CALLBACK_URL).
"""
import logging
from decimal import Decimal
from typing import Optional

from django.conf import settings

from apps.payments.gateways.base import GatewayResult

logger = logging.getLogger(__name__)


class AirtelService:
    """Service Airtel Money. Clés lues depuis la configuration globale."""

    @staticmethod
    def _get_config() -> tuple[str, str, str]:
        api_key = (getattr(settings, 'AIRTEL_API_KEY', '') or '').strip()
        api_secret = (getattr(settings, 'AIRTEL_API_SECRET', '') or '').strip()
        callback_url = (getattr(settings, 'AIRTEL_CALLBACK_URL', '') or '').strip()
        return api_key, api_secret, callback_url

    @classmethod
    def is_configured(cls) -> bool:
        api_key, api_secret, _ = cls._get_config()
        return bool(api_key and api_secret)

    @classmethod
    def initiate_payment(
        cls,
        phone: str,
        amount: Decimal,
        reference: str,
        merchant_number: str,
        currency: str = 'CDF',
    ) -> GatewayResult:
        """
        Initie un paiement Airtel Money vers le numéro marchand de l'école.
        phone: numéro du payeur (ex: +243810000001)
        amount: montant
        reference: référence unique (ex: SCH12-STU45-INV889)
        merchant_number: numéro de réception de l'école (ex: +243810000000)
        """
        api_key, api_secret, callback_url = cls._get_config()
        if not api_key or not api_secret:
            logger.warning("Airtel Money non configuré (AIRTEL_API_KEY / AIRTEL_API_SECRET)")
            return GatewayResult(
                success=False,
                message="Airtel Money non configuré. Configurez AIRTEL_API_KEY et AIRTEL_API_SECRET.",
            )

        phone_clean = phone.lstrip('+').replace(' ', '')
        try:
            import requests
            # Exemple d'appel API Airtel (à adapter selon la doc officielle Airtel Money API)
            payload = {
                "reference": reference,
                "subscriber": {"msisdn": phone_clean},
                "transaction": {
                    "amount": str(int(amount)),
                    "currency": currency,
                },
                "payee": {"msisdn": merchant_number.lstrip('+').replace(' ', '')},
                "callback_url": callback_url or None,
            }
            # URL à remplacer par l'endpoint réel Airtel (ex: Airtel Money RDC)
            api_base = (getattr(settings, 'AIRTEL_API_BASE_URL', '') or '').strip() or 'https://api.airtel.africa'
            url = f"{api_base.rstrip('/')}/merchant/v1/payments/"
            resp = requests.post(
                url,
                json=payload,
                auth=(api_key, api_secret),
                headers={"Content-Type": "application/json"},
                timeout=15,
            )
            data = resp.json() if resp.headers.get('content-type', '').startswith('application/json') else {}
            if resp.status_code in (200, 201) and data.get('status', {}).get('success'):
                tx_id = data.get('transaction_id') or data.get('data', {}).get('id') or data.get('id') or ''
                return GatewayResult(
                    success=True,
                    transaction_id=str(tx_id) if tx_id else None,
                    message="Confirmez le paiement sur votre téléphone (Airtel Money).",
                    requires_action=True,
                )
            msg = data.get('message') or data.get('status', {}).get('message') or resp.text[:200] or "Erreur Airtel"
            return GatewayResult(success=False, message=msg)
        except Exception as e:
            logger.exception("Airtel initiate_payment error: %s", e)
            return GatewayResult(success=False, message=str(e))
