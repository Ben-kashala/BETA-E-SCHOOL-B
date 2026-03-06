"""
Airtel Money — initiation paiement (USSD Push / collect).
Flux officiel : OAuth2 token (auth/oauth2/token) puis POST merchant/v1/payments/.
Compatible Airtel RDC (openapiuat.airtel.cd) et Airtel Africa (openapi.airtel.africa).
"""
import logging
import time
from decimal import Decimal

from django.conf import settings

from apps.payments.gateways.base import GatewayResult

logger = logging.getLogger(__name__)

# Pays / devise par code devise (pour X-Country / X-Currency)
_CURRENCY_TO_COUNTRY = {'CDF': 'CD', 'UGX': 'UG', 'USD': 'UG', 'KES': 'KE', 'TZS': 'TZ', 'NGN': 'NG', 'ZMW': 'ZM'}


class AirtelService:
    """Service Airtel Money. OAuth2 puis API de collecte."""

    @staticmethod
    def _get_config() -> tuple[str, str, str, str]:
        api_key = (getattr(settings, 'AIRTEL_API_KEY', '') or '').strip()
        api_secret = (getattr(settings, 'AIRTEL_API_SECRET', '') or '').strip()
        callback_url = (getattr(settings, 'AIRTEL_CALLBACK_URL', '') or '').strip()
        api_base = (getattr(settings, 'AIRTEL_API_BASE_URL', '') or '').strip()
        return api_key, api_secret, callback_url, api_base

    @classmethod
    def is_configured(cls) -> bool:
        api_key, api_secret, _, api_base = cls._get_config()
        return bool(api_key and api_secret and api_base)

    @classmethod
    def _get_token(cls, api_base: str, client_id: str, client_secret: str) -> tuple[bool, str]:
        """
        OAuth2 client_credentials. Retourne (success, access_token ou message d'erreur).
        Met en cache le token selon expires_in (ex. 180 s) pour éviter une requête à chaque paiement.
        """
        from django.core.cache import cache
        cache_key = "airtel_oauth_token"
        cached = cache.get(cache_key)
        if cached:
            return True, cached

        import requests
        url = f"{api_base.rstrip('/')}/auth/oauth2/token"
        # Beaucoup d'APIs OAuth2 attendent form-urlencoded, pas JSON
        headers = {"Accept": "*/*"}
        # Essai 1 : body en application/x-www-form-urlencoded (standard OAuth2)
        body_form = {
            "client_id": client_id,
            "client_secret": client_secret,
            "grant_type": "client_credentials",
        }
        try:
            # Essai 1 : form-urlencoded (standard OAuth2, souvent requis par Airtel)
            resp = requests.post(
                url,
                data=body_form,
                headers={**headers, "Content-Type": "application/x-www-form-urlencoded"},
                timeout=15,
            )
            if resp.status_code != 200:
                # Essai 2 : JSON (certaines instances Airtel l’acceptent)
                resp2 = requests.post(
                    url,
                    json=body_form,
                    headers={**headers, "Content-Type": "application/json"},
                    timeout=15,
                )
                if resp2.status_code == 200:
                    resp = resp2
            data = resp.json() if (resp.headers.get("content-type") or "").startswith("application/json") else {}
            if resp.status_code == 200:
                token = (data.get("access_token") or data.get("accessToken") or "").strip()
                if token:
                    # expires_in en secondes (ex. "180" ou 180) ; on met en cache un peu moins pour anticiper
                    expires_in = data.get("expires_in", 0)
                    if isinstance(expires_in, str):
                        try:
                            expires_in = int(expires_in)
                        except (TypeError, ValueError):
                            expires_in = 150
                    cache_seconds = max(60, (expires_in - 30) if expires_in else 150)
                    cache.set(cache_key, token, timeout=cache_seconds)
                    return True, token
            msg = data.get("error_description") or data.get("message") or data.get("error") or resp.text[:200]
            return False, msg or "Échec obtention token Airtel"
        except Exception as e:
            logger.exception("Airtel OAuth2 token error: %s", e)
            return False, str(e)

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
        Initie un paiement Airtel Money (USSD Push).
        - Obtient un token OAuth2 (client_id = AIRTEL_API_KEY, client_secret = AIRTEL_API_SECRET).
        - Appelle POST /merchant/v1/payments/ avec X-Country, X-Currency et le body doc Airtel.
        """
        api_key, api_secret, _callback_url, api_base = cls._get_config()
        if not api_key or not api_secret:
            return GatewayResult(
                success=False,
                message="Airtel Money non configuré. Configurez AIRTEL_API_KEY et AIRTEL_API_SECRET (client_id / client_secret).",
            )
        if not api_base:
            return GatewayResult(
                success=False,
                message="Configurez AIRTEL_API_BASE_URL (ex. https://openapiuat.airtel.cd pour la RDC UAT).",
            )

        success, token_or_error = cls._get_token(api_base, api_key, api_secret)
        if not success:
            return GatewayResult(success=False, message=token_or_error)

        # Numéro sans + ni espaces ; Airtel attend parfois sans préfixe pays
        phone_clean = phone.lstrip("+").replace(" ", "").replace("-", "")
        if phone_clean.startswith("243"):
            msisdn = int(phone_clean)  # RDC
        else:
            msisdn = int(phone_clean) if phone_clean.isdigit() else phone_clean
        country = _CURRENCY_TO_COUNTRY.get(currency, "CD")
        transaction_id = reference.replace("-", "")[:32] or str(int(time.time() * 1000))

        import requests
        url = f"{api_base.rstrip('/')}/merchant/v1/payments/"
        headers = {
            "Content-Type": "application/json",
            "Accept": "*/*",
            "X-Country": country,
            "X-Currency": currency,
            "Authorization": f"Bearer {token_or_error}",
        }
        payload = {
            "reference": reference,
            "subscriber": {
                "country": country,
                "currency": currency,
                "msisdn": msisdn,
            },
            "transaction": {
                "amount": int(amount),
                "country": country,
                "currency": currency,
                "id": transaction_id,
            },
        }
        try:
            resp = requests.post(url, json=payload, headers=headers, timeout=15)
            data = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
            if resp.status_code in (200, 201):
                # Réponse type: {"status": {"success": true, ...}, "data": {"transaction_id": "...", ...}}
                status_info = data.get("status") or {}
                if status_info.get("success") or data.get("transaction_id") or data.get("data", {}).get("transaction_id"):
                    tx_id = (
                        data.get("transaction_id")
                        or (data.get("data") or {}).get("transaction_id")
                        or (data.get("data") or {}).get("id")
                        or data.get("id")
                        or transaction_id
                    )
                    return GatewayResult(
                        success=True,
                        transaction_id=str(tx_id),
                        message="Confirmez le paiement sur votre téléphone (Airtel Money).",
                        requires_action=True,
                    )
            msg = (
                (data.get("status") or {}).get("message")
                or data.get("message")
                or data.get("error")
                or resp.text[:200]
                or "Erreur Airtel"
            )
            return GatewayResult(success=False, message=str(msg))
        except Exception as e:
            logger.exception("Airtel initiate_payment error: %s", e)
            return GatewayResult(success=False, message=str(e))
