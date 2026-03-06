"""
PaymentManager : orchestre l'initiation des paiements Mobile Money.
1. Récupère la configuration de paiement de l'école (SchoolPaymentMethod)
2. Choisit le bon provider (airtel, orange, mpesa)
3. Crée une PaymentTransaction et appelle le bon service.
"""
import logging
from decimal import Decimal
from typing import Optional

from django.db import transaction as db_transaction

from apps.payments.models import Payment, SchoolPaymentMethod, SchoolPaymentConfig, PaymentTransaction
from apps.payments.gateways.base import GatewayResult

logger = logging.getLogger(__name__)

PROVIDER_SERVICE_MAP = {
    'airtel': 'apps.payments.services.airtel_service.AirtelService',
    'orange': 'apps.payments.services.orange_service.OrangeService',
    'mpesa': 'apps.payments.services.mpesa_service.MpesaService',
}


def build_payment_reference(school_id: int, student_id: Optional[int], payment_id: int) -> str:
    """Format SCH12-STU45-INV889 pour identifier école, élève, facture/paiement."""
    student_part = f"STU{student_id}" if student_id else "STU0"
    return f"SCH{school_id}-{student_part}-INV{payment_id}"


class PaymentManager:
    """
    Gestionnaire central des paiements Mobile Money.
    Utilise les clés API globales et les numéros marchands par école (SchoolPaymentMethod).
    """

    @staticmethod
    def get_school_merchant_number(school_id: int, provider: str) -> Optional[str]:
        """
        Retourne le numéro Mobile Money de l'école pour le provider donné (actif uniquement).
        """
        method = (
            SchoolPaymentMethod.objects
            .filter(school_id=school_id, provider=provider, status='active')
            .first()
        )
        return method.merchant_number if method else None

    @staticmethod
    def get_available_providers_for_school(school_id: int) -> list[dict]:
        """
        Liste des moyens de paiement activés pour l'école (provider + numéro marchand masqué).
        """
        config = SchoolPaymentConfig.objects.filter(school_id=school_id, is_active=True).first()
        if not config:
            return []
        methods = (
            SchoolPaymentMethod.objects
            .filter(school_id=school_id, status='active')
            .values('provider', 'merchant_number')
        )
        return [
            {
                'provider': m['provider'],
                'merchant_number': m['merchant_number'],
                'display_number': m['merchant_number'][-4:].rjust(len(m['merchant_number']), '*') if m['merchant_number'] else '',
            }
            for m in methods
        ]

    @classmethod
    def process_payment(
        cls,
        school_id: int,
        provider: str,
        phone: str,
        amount: Decimal,
        student_id: Optional[int],
        payment: Payment,
        currency: str = 'CDF',
    ) -> GatewayResult:
        """
        Initie un paiement Mobile Money pour l'école.
        - Récupère le numéro marchand de l'école pour ce provider
        - Crée une PaymentTransaction
        - Appelle le service du provider (Airtel, Orange, M-Pesa)
        - Retourne le résultat (success + transaction_id ou message d'erreur)
        """
        provider = (provider or '').strip().lower()
        if provider not in PROVIDER_SERVICE_MAP:
            return GatewayResult(success=False, message=f"Provider non supporté: {provider}")

        merchant_number = cls.get_school_merchant_number(school_id, provider)
        if not merchant_number:
            return GatewayResult(
                success=False,
                message=f"L'école n'a pas configuré de numéro Mobile Money pour {provider}. "
                        "Configurez un numéro dans Paramètres > Moyens de paiement.",
            )

        config = SchoolPaymentConfig.objects.filter(school_id=school_id, is_active=True).first()
        if not config:
            return GatewayResult(success=False, message="Paiement en ligne désactivé pour cette école.")

        reference = build_payment_reference(school_id, student_id, payment.id)
        if PaymentTransaction.objects.filter(reference=reference).exists():
            return GatewayResult(success=False, message="Une transaction avec cette référence existe déjà.")

        # Import dynamique du service
        service_path = PROVIDER_SERVICE_MAP[provider]
        module_path, class_name = service_path.rsplit('.', 1)
        import importlib
        mod = importlib.import_module(module_path)
        service_class = getattr(mod, class_name)

        with db_transaction.atomic():
            payment_tx = PaymentTransaction.objects.create(
                school_id=school_id,
                student_id=student_id,
                provider=provider,
                phone=phone,
                amount=amount,
                reference=reference,
                status='pending',
                payment=payment,
            )
            result = service_class.initiate_payment(
                phone=phone,
                amount=amount,
                reference=reference,
                merchant_number=merchant_number,
                currency=currency or payment.currency or 'CDF',
            )
            if result.success and result.transaction_id:
                payment_tx.provider_transaction_id = result.transaction_id
                payment_tx.status = 'processing'
                payment_tx.save(update_fields=['provider_transaction_id', 'status', 'updated_at'])
            else:
                payment_tx.status = 'failed'
                payment_tx.save(update_fields=['status', 'updated_at'])

        return result
