"""
Orange Money — initiation paiement.
Utilise les clés API globales (ORANGE_API_KEY, ORANGE_API_SECRET, ORANGE_CALLBACK_URL).
"""
import logging
from decimal import Decimal

from django.conf import settings

from apps.payments.gateways.base import GatewayResult

logger = logging.getLogger(__name__)


class OrangeService:
    """Service Orange Money. Clés lues depuis la configuration globale."""

    @staticmethod
    def _get_config() -> tuple[str, str, str, str]:
        api_key = (getattr(settings, 'ORANGE_API_KEY', '') or '').strip()
        api_secret = (getattr(settings, 'ORANGE_API_SECRET', '') or '').strip()
        callback_url = (getattr(settings, 'ORANGE_CALLBACK_URL', '') or '').strip()
        api_base = (getattr(settings, 'ORANGE_API_BASE_URL', '') or '').strip()
        return api_key, api_secret, callback_url, api_base

    @classmethod
    def is_configured(cls) -> bool:
        api_key, api_secret, _, api_base = cls._get_config()
        return bool(api_key and api_secret and api_base)

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
        Initie un paiement Orange Money vers le numéro marchand de l'école.
        """
        api_key, api_secret, callback_url, api_base = cls._get_config()
        if not api_key or not api_secret:
            logger.warning("Orange Money non configuré (ORANGE_API_KEY / ORANGE_API_SECRET)")
            return GatewayResult(
                success=False,
                message="Orange Money non configuré. Configurez ORANGE_API_KEY et ORANGE_API_SECRET.",
            )
        if not api_base:
            logger.warning("Orange Money : ORANGE_API_BASE_URL non configuré")
            return GatewayResult(
                success=False,
                message="Orange Money : configurez ORANGE_API_BASE_URL avec l’URL de l’API fournie par Orange.",
            )

        phone_clean = phone.lstrip('+').replace(' ', '')
        try:
            import requests
            payload = {
                "reference": reference,
                "subscriber_msisdn": phone_clean,
                "amount": str(int(amount)),
                "currency": currency,
                "merchant_msisdn": merchant_number.lstrip('+').replace(' ', ''),
                "callback_url": callback_url or None,
            }
            url = f"{api_base.rstrip('/')}/orange-money/v1/payment"
            resp = requests.post(
                url,
                json=payload,
                headers={
                    "Authorization": f"Bearer {api_key}",  # ou token OAuth selon doc Orange
                    "Content-Type": "application/json",
                },
                timeout=15,
            )
            data = resp.json() if resp.headers.get('content-type', '').startswith('application/json') else {}
            if resp.status_code in (200, 201) and (data.get('status') == 'success' or data.get('transaction_id')):
                tx_id = data.get('transaction_id') or data.get('data', {}).get('id') or data.get('id') or ''
                return GatewayResult(
                    success=True,
                    transaction_id=str(tx_id) if tx_id else None,
                    message="Confirmez le paiement sur votre téléphone (Orange Money).",
                    requires_action=True,
                )
            msg = data.get('message') or data.get('error') or resp.text[:200] or "Erreur Orange Money"
            return GatewayResult(success=False, message=msg)
        except Exception as e:
            logger.exception("Orange initiate_payment error: %s", e)
            return GatewayResult(success=False, message=str(e))
