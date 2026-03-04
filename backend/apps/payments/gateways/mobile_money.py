"""
Mobile Money gateways: Orange Money, M-Pesa, Airtel Money.
Multi-tenant : config par école (SchoolPaymentConfig) ou paramètres globaux (.env).
"""
import logging
import uuid
from decimal import Decimal
from typing import Optional
from django.conf import settings

from .base import GatewayResult

logger = logging.getLogger(__name__)


def get_mobile_money_provider(school_id: Optional[int] = None) -> str:
    """Retourne le provider Mobile Money pour l'école (config ou global)."""
    if school_id:
        try:
            from apps.payments.models import SchoolPaymentConfig
            config = SchoolPaymentConfig.objects.filter(
                school_id=school_id, is_active=True
            ).first()
            if config:
                return (config.mobile_money_provider or 'mock').lower()
        except Exception as e:
            logger.warning("SchoolPaymentConfig lookup failed for school_id=%s: %s", school_id, e)
    return (getattr(settings, 'MOBILE_MONEY_PROVIDER', 'mock') or 'mock').lower()

# Méthodes backend -> identifiants opérateur (pour agrégateurs)
PROVIDER_CODES = {
    'MOBILE_MONEY_ORANGE': 'orange',
    'MOBILE_MONEY_MPESA': 'mpesa',
    'MOBILE_MONEY_AIRTEL': 'airtel',
}


def _mock_initiate(phone: str, amount: Decimal, currency: str, reference: str, provider: str) -> GatewayResult:
    """
    Simulation pour développement. En prod, remplacer par l'appel à l'API réelle.
    L'utilisateur "confirme" via le bouton "Simuler confirmation" ou un webhook de test.
    """
    tx_id = f"MM-{uuid.uuid4().hex[:12].upper()}"
    logger.info("Mock Mobile Money: provider=%s phone=%s amount=%s ref=%s tx_id=%s", provider, phone, amount, reference, tx_id)
    return GatewayResult(
        success=True,
        transaction_id=tx_id,
        message="Demande envoyée. Confirmez le paiement sur votre téléphone (mode démo : le paiement restera en attente jusqu'à simulation).",
        requires_action=True,
    )


def _flutterwave_initiate(
    phone: str, amount: Decimal, currency: str, reference: str, provider: str,
    secret: str,
) -> GatewayResult:
    """
    Intégration Flutterwave Mobile Money.
    Doc: https://developer.flutterwave.com/docs/mobile-money/collect
    """
    if not secret:
        logger.warning("FLUTTERWAVE_SECRET_KEY non configuré, fallback mock")
        return _mock_initiate(phone, amount, currency, reference, provider)

    try:
        import requests
        provider_code = PROVIDER_CODES.get(provider, 'mpesa')
        payload = {
            "tx_ref": reference,
            "amount": float(amount),
            "currency": currency,
            "phone_number": phone.lstrip('+').replace(' ', ''),
            "network": provider_code,
        }
        resp = requests.post(
            "https://api.flutterwave.com/v3/charges?type=mobile_money",
            json=payload,
            headers={"Authorization": f"Bearer {secret}", "Content-Type": "application/json"},
            timeout=15,
        )
        data = resp.json()
        if data.get('status') == 'success' and data.get('data', {}).get('id'):
            tx_id = str(data['data']['id'])
            return GatewayResult(
                success=True,
                transaction_id=tx_id,
                message="Confirmez le paiement sur votre téléphone.",
                requires_action=True,
            )
        return GatewayResult(
            success=False,
            message=data.get('message', 'Erreur Flutterwave') or resp.text[:200],
        )
    except Exception as e:
        logger.exception("Flutterwave mobile money error: %s", e)
        return GatewayResult(success=False, message=str(e))


def initiate_mobile_money(
    payment_method: str,
    phone_number: str,
    amount: Decimal,
    currency: str,
    reference: str,
    school_id: Optional[int] = None,
) -> GatewayResult:
    """
    Initie un paiement Mobile Money (Orange Money, M-Pesa, Airtel Money).
    Multi-tenant : utilise la config de l'école (SchoolPaymentConfig) ou les paramètres globaux.
    """
    if payment_method not in PROVIDER_CODES:
        return GatewayResult(success=False, message=f"Méthode non supportée: {payment_method}")

    provider = get_mobile_money_provider(school_id)
    if provider == 'flutterwave':
        from .flutterwave_cards import get_flutterwave_keys
        _, secret = get_flutterwave_keys(school_id)
        return _flutterwave_initiate(
            phone_number, amount, currency, reference, payment_method, secret=secret
        )
    return _mock_initiate(phone_number, amount, currency, reference, payment_method)
