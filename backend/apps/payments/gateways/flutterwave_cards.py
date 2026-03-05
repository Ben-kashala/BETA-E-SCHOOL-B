"""
Paiement par carte (VISA, Mastercard) via Flutterwave.
Multi-tenant : clés par école (SchoolPaymentConfig) ou clés globales (.env).
"""
import logging
from decimal import Decimal
from typing import Optional
from django.conf import settings

from .base import GatewayResult

logger = logging.getLogger(__name__)


def get_flutterwave_keys(school_id: Optional[int] = None):
    """
    Retourne (public_key, secret_key) pour Flutterwave.
    Si l'école a une SchoolPaymentConfig avec clés renseignées, on les utilise (chaque école encaisse sur son compte).
    Sinon on utilise les clés globales (même compte pour toutes les écoles).
    """
    if school_id:
        try:
            from apps.payments.models import SchoolPaymentConfig
            config = SchoolPaymentConfig.objects.filter(
                school_id=school_id, is_active=True
            ).first()
            if config and config.flutterwave_public_key and config.flutterwave_secret_key:
                return (config.flutterwave_public_key.strip(), config.flutterwave_secret_key.strip())
        except Exception as e:
            logger.warning("SchoolPaymentConfig lookup failed for school_id=%s: %s", school_id, e)
    pub = (getattr(settings, 'FLUTTERWAVE_PUBLIC_KEY', '') or '').strip()
    sec = (getattr(settings, 'FLUTTERWAVE_SECRET_KEY', '') or '').strip()
    return (pub, sec)


def prepare_card_payment(
    amount: Decimal,
    currency: str,
    payment_id: str,
    payment_db_id: int,
    school_id: int,
    description: str = '',
    customer_email: str = '',
    customer_name: str = '',
) -> GatewayResult:
    """
    Prépare un paiement carte Flutterwave. Ne charge pas la carte.
    Retourne la config pour le frontend (FlutterwaveCheckout) : public_key, tx_ref, amount, currency, redirect_url.
    """
    public_key, secret_key = get_flutterwave_keys(school_id)
    if not public_key:
        logger.warning("FLUTTERWAVE_PUBLIC_KEY non configuré")
        return GatewayResult(success=False, message="Paiement carte non configuré (Flutterwave).")

    currency_upper = (currency or "USD").upper()
    # Flutterwave attend le montant (entier pour CDF/XAF etc., sinon avec décimales)
    if currency_upper in ('CDF', 'XAF', 'XOF', 'NGN', 'JPY', 'KRW'):
        amount_value = int(amount)
    else:
        amount_value = float(amount)

    if amount_value < 1:
        return GatewayResult(success=False, message="Montant trop faible.")

    # tx_ref = référence unique côté plateforme (payment_id suffit, déjà unique)
    tx_ref = payment_id
    return GatewayResult(
        success=True,
        transaction_id=tx_ref,
        message="Config Flutterwave prête.",
    )


def get_card_checkout_config(
    amount: Decimal,
    currency: str,
    payment_id: str,
    payment_db_id: int,
    school_id: int,
    redirect_url: str,
    customer_email: str = '',
    customer_name: str = '',
) -> Optional[dict]:
    """
    Retourne le dictionnaire de config pour FlutterwaveCheckout (frontend).
    Multi-tenant : school_id sert pour des clés par école si besoin.
    """
    result = prepare_card_payment(
        amount=amount,
        currency=currency,
        payment_id=payment_id,
        payment_db_id=payment_db_id,
        school_id=school_id,
        description=f"E-School {payment_id}",
        customer_email=customer_email,
        customer_name=customer_name,
    )
    if not result.success:
        return None
    public_key, _ = get_flutterwave_keys(school_id)
    currency_upper = (currency or "USD").upper()
    if currency_upper in ('CDF', 'XAF', 'XOF', 'NGN', 'JPY', 'KRW'):
        amount_value = int(amount)
    else:
        amount_value = float(amount)
    return {
        'public_key': public_key,
        'tx_ref': payment_id,
        'amount': amount_value,
        'currency': currency_upper,
        'redirect_url': redirect_url,
        'payment_id': payment_db_id,
        'customer': {
            'email': customer_email or 'parent@eschool.rdc',
            'name': customer_name or 'Parent',
        },
    }


def verify_flutterwave_transaction(transaction_id: str, school_id: Optional[int] = None) -> tuple[bool, str, Optional[str]]:
    """
    Vérifie une transaction Flutterwave via l'API (GET /transactions/{id}/verify).
    Retourne (success, message, tx_ref).
    """
    _, secret_key = get_flutterwave_keys(school_id)
    if not secret_key:
        return False, "Flutterwave non configuré", None

    try:
        import requests
        resp = requests.get(
            f"https://api.flutterwave.com/v3/transactions/{transaction_id}/verify",
            headers={"Authorization": f"Bearer {secret_key}", "Content-Type": "application/json"},
            timeout=15,
        )
        data = resp.json()
        if data.get('status') != 'success':
            return False, data.get('message', 'Vérification échouée'), None
        payload = data.get('data', {})
        status = payload.get('status')
        tx_ref = payload.get('tx_ref')
        if status == 'successful':
            return True, "successful", tx_ref
        return False, status or "Transaction non réussie", tx_ref
    except Exception as e:
        logger.exception("Flutterwave verify error: %s", e)
        return False, str(e), None
