from rest_framework import viewsets, permissions, status
from rest_framework import mixins
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.pagination import PageNumberPagination
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from django.http import HttpResponse, JsonResponse
from django.db.models import Sum, Count, Q, DecimalField, Value
from django.db import models
from django.db.models.functions import Coalesce
from decimal import Decimal
import logging
import uuid

logger = logging.getLogger(__name__)
from .models import (
    FeeType, Payment, FeePayment, PaymentPlan, PaymentReceipt,
    SchoolExpense, CashMovement, PaymentTransaction, SchoolPaymentMethod,
)
from .serializers import (
    FeeTypeSerializer, PaymentSerializer, FeePaymentSerializer,
    PaymentPlanSerializer, PaymentReceiptSerializer, SchoolExpenseSerializer,
    CashMovementSerializer, CashMovementCreateSerializer,
    InitiateMobileSerializer, SchoolPaymentMethodSerializer,
)
from .services import PaymentManager


class FeeTypeViewSet(viewsets.ModelViewSet):
    serializer_class = FeeTypeSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['school', 'is_active']
    search_fields = ['name', 'description']
    
    def get_queryset(self):
        queryset = FeeType.objects.filter(is_active=True)
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        return queryset
    
    def perform_create(self, serializer):
        """Automatically assign the fee type to the user's school"""
        serializer.save(school=self.request.user.school)


class SchoolPaymentMethodViewSet(viewsets.ModelViewSet):
    """
    Moyens de paiement Mobile Money de l'école (Airtel, Orange, M-Pesa).
    Chaque école active un ou plusieurs providers et renseigne son numéro de réception.
    """
    serializer_class = SchoolPaymentMethodSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['provider', 'status']

    def get_queryset(self):
        queryset = SchoolPaymentMethod.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        return queryset.order_by('provider')

    def perform_create(self, serializer):
        if not self.request.user.school:
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied("Aucune école associée.")
        serializer.save(school=self.request.user.school)


# Mapping méthode frontend -> provider (airtel, orange, mpesa)
PAYMENT_METHOD_TO_PROVIDER = {
    'MOBILE_MONEY_ORANGE': 'orange',
    'MOBILE_MONEY_MPESA': 'mpesa',
    'MOBILE_MONEY_AIRTEL': 'airtel',
}


def _complete_mobile_money_payment(payment_tx: PaymentTransaction):
    """
    Marque la transaction et le paiement comme complétés, crée le reçu et le mouvement de caisse.
    Appelé par les callbacks opérateurs ou par confirm_mobile.
    """
    if payment_tx.status == 'completed':
        return
    payment_tx.status = 'completed'
    payment_tx.save(update_fields=['status', 'updated_at'])
    payment = payment_tx.payment
    if not payment or payment.status == 'COMPLETED':
        return
    payment.status = 'COMPLETED'
    payment.payment_date = timezone.now()
    payment.transaction_id = payment_tx.provider_transaction_id or payment_tx.reference
    payment.save()
    receipt_number = f"REC-{uuid.uuid4().hex[:12].upper()}"
    PaymentReceipt.objects.get_or_create(payment=payment, defaults={'receipt_number': receipt_number})
    if not CashMovement.objects.filter(
        school=payment.school, reference_type='payment', reference_id=payment.id
    ).exists():
        _create_cash_movement(
            school=payment.school,
            movement_type='IN',
            amount=payment.amount,
            currency=payment.currency,
            payment_method=payment.payment_method,
            source='PAYMENT',
            description=f'Paiement {payment.payment_id}',
            reference_type='payment',
            reference_id=payment.id,
            created_by=None,
        )
    try:
        from apps.communication.notifications import notify_payment_made
        notify_payment_made(payment)
    except Exception as e:
        logger.exception("notify_payment_made: %s", e)


def process_mobile_money_payment(payment, phone_number, transaction_id):
    """
    Mock function for Mobile Money payment processing
    In production, integrate with actual Mobile Money APIs:
    - M-Pesa (Kenya/Tanzania)
    - Orange Money (West/Central Africa)
    - Airtel Money (Africa)
    - MTN Mobile Money (Africa)
    """
    # Mock implementation
    # In production, this would:
    # 1. Call the Mobile Money API
    # 2. Verify the transaction
    # 3. Handle webhooks for payment confirmation
    # 4. Update payment status based on API response
    
    # For now, simulate success
    import random
    return random.choice([True, True, True, False])  # 75% success rate for demo


class PaymentViewSet(viewsets.ModelViewSet):
    serializer_class = PaymentSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['user', 'student', 'school', 'status', 'payment_method']
    search_fields = ['payment_id', 'reference_number', 'transaction_id']
    
    def get_queryset(self):
        queryset = Payment.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        # Admin and accountant can see all school payments; others only their own
        if not (self.request.user.is_admin or self.request.user.is_accountant):
            queryset = queryset.filter(user=self.request.user)
        return queryset
    
    def perform_create(self, serializer):
        # Comptable / Admin : peuvent enregistrer un paiement au nom d'un utilisateur (parent)
        payment_user = self.request.user
        if (getattr(self.request.user, 'is_admin', False) or getattr(self.request.user, 'is_accountant', False)):
            user_id = self.request.data.get('user')
            if user_id and self.request.user.school:
                from apps.accounts.models import User
                payee = User.objects.filter(id=user_id, school=self.request.user.school).first()
                if payee:
                    payment_user = payee
        payment_id = f"PAY-{uuid.uuid4().hex[:12].upper()}"
        payment = serializer.save(
            payment_id=payment_id,
            school=self.request.user.school,
            user=payment_user
        )
        if payment.status == 'COMPLETED':
            from apps.communication.notifications import notify_payment_made
            notify_payment_made(payment)
            receipt_number = f"REC-{uuid.uuid4().hex[:12].upper()}"
            PaymentReceipt.objects.get_or_create(
                payment=payment,
                defaults={'receipt_number': receipt_number}
            )
            _create_cash_movement(
                school=payment.school,
                movement_type='IN',
                amount=payment.amount,
                currency=payment.currency,
                payment_method=payment.payment_method,
                source='PAYMENT',
                description=f'Paiement {payment.payment_id}',
                reference_type='payment',
                reference_id=payment.id,
                created_by=self.request.user,
            )
        # Lier le paiement à un type de frais (Frais d'inscription, Première tranche, etc.) pour le classement
        fee_type_id = self.request.data.get('fee_type')
        if fee_type_id is not None and fee_type_id != '' and self.request.user.school:
            try:
                fee_type_id = int(fee_type_id)
            except (TypeError, ValueError):
                fee_type_id = None
        if fee_type_id and self.request.user.school:
            fee_type = FeeType.objects.filter(
                id=fee_type_id, school=self.request.user.school
            ).first()
            if fee_type:
                academic_year = self.request.data.get('academic_year') or f"{timezone.now().year}-{timezone.now().year + 1}"
                FeePayment.objects.create(
                    payment=payment,
                    fee_type=fee_type,
                    amount=payment.amount,
                    academic_year=academic_year,
                )

    def perform_update(self, serializer):
        """Créer un mouvement de caisse si le paiement passe à COMPLETED (ex. via PATCH)."""
        old_instance = serializer.instance
        instance = serializer.save()
        if instance.status == 'COMPLETED' and getattr(old_instance, 'status', None) != 'COMPLETED':
            from apps.communication.notifications import notify_payment_made
            notify_payment_made(instance)
            if not CashMovement.objects.filter(school=instance.school, reference_type='payment', reference_id=instance.id).exists():
                _create_cash_movement(
                    school=instance.school,
                    movement_type='IN',
                    amount=instance.amount,
                    currency=instance.currency,
                    payment_method=instance.payment_method,
                    source='PAYMENT',
                    description=f'Paiement {instance.payment_id}',
                    reference_type='payment',
                    reference_id=instance.id,
                    created_by=self.request.user,
                )
    
    @action(detail=True, methods=['post'])
    def validate(self, request, pk=None):
        """Validate/Approve a pending payment"""
        payment = self.get_object()
        if payment.status != 'PENDING':
            return Response(
                {'error': 'Seuls les paiements en attente peuvent être validés'},
                status=status.HTTP_400_BAD_REQUEST
            )
        payment.status = 'COMPLETED'
        payment.payment_date = timezone.now()
        payment.save()
        from apps.communication.notifications import notify_payment_made
        notify_payment_made(payment)
        receipt_number = f"REC-{uuid.uuid4().hex[:12].upper()}"
        PaymentReceipt.objects.get_or_create(payment=payment, defaults={'receipt_number': receipt_number})
        if not CashMovement.objects.filter(school=payment.school, reference_type='payment', reference_id=payment.id).exists():
            _create_cash_movement(
                school=payment.school,
                movement_type='IN',
                amount=payment.amount,
                currency=payment.currency,
                payment_method=payment.payment_method,
                source='PAYMENT',
                description=f'Paiement {payment.payment_id}',
                reference_type='payment',
                reference_id=payment.id,
                created_by=request.user,
            )
        return Response(PaymentSerializer(payment).data)
    
    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        """Reject a pending payment"""
        payment = self.get_object()
        if payment.status != 'PENDING':
            return Response(
                {'error': 'Seuls les paiements en attente peuvent être rejetés'},
                status=status.HTTP_400_BAD_REQUEST
            )
        payment.status = 'FAILED'
        payment.notes = request.data.get('notes', 'Paiement rejeté par l\'administrateur')
        payment.save()
        return Response(PaymentSerializer(payment).data)

    @action(detail=False, methods=['get'], url_path='summary-by-fee-type')
    def summary_by_fee_type(self, request):
        """Classement des montants par type de frais (paiements complétés). Inclut les paiements sans type (Non ventilé)."""
        if not request.user.school:
            return Response([])
        # Paiements ventilés par type de frais (FeePayment)
        qs = (
            FeePayment.objects
            .filter(payment__status='COMPLETED', payment__school=request.user.school)
            .values('fee_type', 'fee_type__name', 'fee_type__currency')
            .annotate(total=Sum('amount'), count=Count('id'))
            .order_by('-total')
        )
        result = []
        for rank, row in enumerate(qs, start=1):
            result.append({
                'rank': rank,
                'fee_type_id': row['fee_type'],
                'fee_type_name': row['fee_type__name'] or '-',
                'currency': row['fee_type__currency'] or 'CDF',
                'total_amount': float(row['total']),
                'payment_count': row['count'],
            })
        # Paiements complétés SANS ventilation (aucun FeePayment) — par devise
        payment_ids_with_fee = FeePayment.objects.filter(
            payment__school=request.user.school
        ).values_list('payment_id', flat=True)
        unassigned = (
            Payment.objects
            .filter(school=request.user.school, status='COMPLETED')
            .exclude(id__in=payment_ids_with_fee)
            .values('currency')
            .annotate(total=Sum('amount'), count=Count('id'))
            .order_by('-total')
        )
        for row in unassigned:
            if row['count'] and row['total']:
                result.append({
                    'rank': len(result) + 1,
                    'fee_type_id': None,
                    'fee_type_name': 'Non ventilé',
                    'currency': row['currency'] or 'CDF',
                    'total_amount': float(row['total']),
                    'payment_count': row['count'],
                })
        return Response(result)
    
    @action(detail=False, methods=['get'], url_path='stats-by-payment-method')
    def stats_by_payment_method(self, request):
        """Statistiques des paiements par méthode de paiement."""
        school = getattr(request.user, 'school', None)
        if not school:
            return Response([])
        
        # Récupérer les paiements complétés groupés par méthode de paiement
        qs = (
            Payment.objects
            .filter(school=school, status='COMPLETED')
            .values('payment_method', 'currency')
            .annotate(
                total_amount=Sum('amount'),
                payment_count=Count('id')
            )
            .order_by('-total_amount')
        )
        
        result = []
        for row in qs:
            payment_method = row['payment_method'] or 'CASH'
            method_display = dict(Payment.PAYMENT_METHODS).get(payment_method, payment_method)
            result.append({
                'payment_method': payment_method,
                'payment_method_display': method_display,
                'currency': row['currency'] or 'CDF',
                'total_amount': float(row['total_amount']),
                'payment_count': row['payment_count'],
            })
        
        return Response(result)
    
    @action(detail=False, methods=['post'], url_path='initiate-mobile')
    def initiate_mobile(self, request):
        """Initie un paiement Mobile Money (Airtel, Orange, M-Pesa) via PaymentManager."""
        serializer = InitiateMobileSerializer(data=request.data)
        if not serializer.is_valid():
            err_msg = '; '.join(
                f"{k}: {v[0]}" if isinstance(v, list) else f"{k}: {v}"
                for k, v in serializer.errors.items()
            )
            logger.warning("initiate-mobile validation error: %s (payload keys: %s)", err_msg, list(request.data.keys()))
            return Response({'error': err_msg}, status=status.HTTP_400_BAD_REQUEST)
        data = serializer.validated_data
        payment_id = data['payment_id']
        phone_number = data['phone_number']
        payment_method = data['payment_method']

        payment = Payment.objects.filter(id=payment_id).first()
        if not payment:
            err = 'Paiement introuvable'
            logger.warning("initiate-mobile 400: %s (payment_id=%s)", err, payment_id)
            return Response({'error': err}, status=status.HTTP_404_NOT_FOUND)
        if payment.status != 'PENDING':
            err = 'Seuls les paiements en attente peuvent être initiés'
            logger.warning("initiate-mobile 400: %s (payment_id=%s status=%s)", err, payment_id, payment.status)
            return Response({'error': err}, status=status.HTTP_400_BAD_REQUEST)
        if payment_method not in PAYMENT_METHOD_TO_PROVIDER:
            err = 'Méthode de paiement non supportée pour Mobile Money'
            logger.warning("initiate-mobile 400: %s (payment_id=%s method=%s)", err, payment_id, payment_method)
            return Response({'error': err}, status=status.HTTP_400_BAD_REQUEST)
        if request.user.school and payment.school_id != request.user.school_id:
            return Response({'error': 'Accès refusé'}, status=status.HTTP_403_FORBIDDEN)
        if not (request.user.is_admin or request.user.is_accountant) and payment.user_id != request.user.id:
            return Response({'error': 'Accès refusé'}, status=status.HTTP_403_FORBIDDEN)

        provider = PAYMENT_METHOD_TO_PROVIDER[payment_method]
        payment.payer_phone = phone_number
        payment.payment_method = payment_method
        payment.status = 'PROCESSING'
        payment.save()

        result = PaymentManager.process_payment(
            school_id=payment.school_id,
            provider=provider,
            phone=phone_number,
            amount=payment.amount,
            student_id=payment.student_id,
            payment=payment,
            currency=payment.currency or 'CDF',
        )
        if not result.success:
            logger.warning("initiate-mobile 400 gateway: %s (payment_id=%s)", result.message, payment_id)
            payment.status = 'PENDING'
            payment.save()
            return Response({'error': result.message}, status=status.HTTP_400_BAD_REQUEST)
        payment.transaction_id = result.transaction_id
        payment.save()
        return Response({
            'transaction_id': result.transaction_id,
            'message': result.message,
            'payment_id': payment.id,
            'status': payment.status,
        })

    @action(detail=False, methods=['get'], url_path='payment-methods')
    def payment_methods(self, request):
        """Liste des moyens de paiement Mobile Money activés pour l'école (Airtel, Orange, M-Pesa)."""
        school_id = getattr(request.user, 'school_id', None)
        if not school_id:
            return Response({'providers': []})
        providers = PaymentManager.get_available_providers_for_school(school_id)
        return Response({'providers': providers})

    @action(detail=True, methods=['post'], url_path='confirm-mobile')
    def confirm_mobile(self, request, pk=None):
        """
        Marque un paiement Mobile Money comme complété (après confirmation sur le téléphone).
        Utilise la PaymentTransaction liée si elle existe ; sinon marque le paiement complété (cas manuel/démo).
        """
        payment = self.get_object()
        if payment.status not in ('PENDING', 'PROCESSING'):
            return Response(
                {'error': 'Ce paiement n\'est pas en attente de confirmation'},
                status=status.HTTP_400_BAD_REQUEST
            )
        if payment.payment_method not in ('MOBILE_MONEY_ORANGE', 'MOBILE_MONEY_MPESA', 'MOBILE_MONEY_AIRTEL'):
            return Response(
                {'error': 'Méthode non Mobile Money'},
                status=status.HTTP_400_BAD_REQUEST
            )
        payment_tx = getattr(payment, 'mobile_money_transaction', None)
        if payment_tx and payment_tx.status != 'completed':
            _complete_mobile_money_payment(payment_tx)
        else:
            # Pas de PaymentTransaction (ancien flux ou manuel) : compléter directement
            payment.status = 'COMPLETED'
            payment.payment_date = timezone.now()
            payment.save()
            receipt_number = f"REC-{uuid.uuid4().hex[:12].upper()}"
            PaymentReceipt.objects.get_or_create(payment=payment, defaults={'receipt_number': receipt_number})
            if not CashMovement.objects.filter(school=payment.school, reference_type='payment', reference_id=payment.id).exists():
                _create_cash_movement(
                    school=payment.school,
                    movement_type='IN',
                    amount=payment.amount,
                    currency=payment.currency,
                    payment_method=payment.payment_method,
                    source='PAYMENT',
                    description=f'Paiement {payment.payment_id}',
                    reference_type='payment',
                    reference_id=payment.id,
                    created_by=request.user,
                )
            try:
                from apps.communication.notifications import notify_payment_made
                notify_payment_made(payment)
            except Exception as e:
                logger.exception("notify_payment_made: %s", e)
        return Response(PaymentSerializer(payment).data)

    @action(detail=True, methods=['post'])
    def process(self, request, pk=None):
        """Process a payment"""
        payment = self.get_object()
        
        # Update payment status based on payment method
        payment_method = request.data.get('payment_method', payment.payment_method)
        transaction_id = request.data.get('transaction_id')
        phone_number = request.data.get('phone_number')  # For mobile money
        
        payment.payment_method = payment_method
        payment.transaction_id = transaction_id
        payment.status = 'PROCESSING'
        payment.save()
        
        # Process based on payment method
        if payment_method.startswith('MOBILE_MONEY'):
            # Mock Mobile Money processing
            # In production, integrate with actual Mobile Money APIs (M-Pesa, Orange Money, etc.)
            success = process_mobile_money_payment(payment, phone_number, transaction_id)
            if success:
                payment.status = 'COMPLETED'
                payment.payment_date = timezone.now()
            else:
                payment.status = 'FAILED'
        elif payment_method == 'ONLINE':
            # Paiement en ligne (Mobile Money confirmé par callback)
            payment.status = 'COMPLETED'
            payment.payment_date = timezone.now()
        elif payment_method == 'CASH':
            # Cash payments are marked as completed immediately
            payment.status = 'COMPLETED'
            payment.payment_date = timezone.now()
        else:
            # Other methods
            payment.status = 'COMPLETED'
            payment.payment_date = timezone.now()
        
        payment.save()
        
        # Generate receipt and create cash movement if payment successful
        if payment.status == 'COMPLETED':
            receipt_number = f"REC-{uuid.uuid4().hex[:12].upper()}"
            PaymentReceipt.objects.get_or_create(
                payment=payment,
                defaults={'receipt_number': receipt_number}
            )
            if not CashMovement.objects.filter(school=payment.school, reference_type='payment', reference_id=payment.id).exists():
                _create_cash_movement(
                    school=payment.school,
                    movement_type='IN',
                    amount=payment.amount,
                    currency=payment.currency,
                    payment_method=payment.payment_method,
                    source='PAYMENT',
                    description=f'Paiement {payment.payment_id}',
                    reference_type='payment',
                    reference_id=payment.id,
                    created_by=request.user,
                )
        
        return Response(PaymentSerializer(payment).data)
    
    @action(detail=True, methods=['get'])
    def download_receipt(self, request, pk=None):
        """Génère et télécharge le reçu de paiement en PDF"""
        payment = self.get_object()
        
        # Vérifier que le paiement est complété
        if payment.status != 'COMPLETED':
            return Response(
                {'error': 'Seuls les paiements complétés peuvent générer un reçu'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Obtenir ou créer le reçu
        receipt, created = PaymentReceipt.objects.get_or_create(
            payment=payment,
            defaults={'receipt_number': f"REC-{uuid.uuid4().hex[:12].upper()}"}
        )
        
        # Générer le PDF si nécessaire
        if not receipt.pdf_file or created:
            from .utils import generate_payment_receipt_pdf
            try:
                generate_payment_receipt_pdf(receipt)
            except Exception as e:
                return Response(
                    {'error': 'Échec de la génération du PDF', 'detail': str(e)},
                    status=status.HTTP_500_INTERNAL_SERVER_ERROR
                )
        
        # Retourner le fichier PDF
        from django.http import FileResponse
        return FileResponse(
            receipt.pdf_file.open(),
            content_type='application/pdf',
            as_attachment=True,
            filename=f'receipt_{receipt.receipt_number}.pdf'
        )
    
    @action(detail=True, methods=['post'])
    def create_installments(self, request, pk=None):
        """Create payment plan with installments"""
        payment = self.get_object()
        num_installments = int(request.data.get('num_installments', 1))
        installment_amount = payment.amount / num_installments
        
        # Clear existing installments
        PaymentPlan.objects.filter(payment=payment).delete()
        
        # Create installments
        installments = []
        for i in range(1, num_installments + 1):
            installment = PaymentPlan.objects.create(
                payment=payment,
                installment_number=i,
                amount=installment_amount,
                due_date=request.data.get(f'due_date_{i}')  # Should be provided in request
            )
            installments.append(installment)
        
        return Response({
            'message': f'Created {num_installments} installments',
            'installments': PaymentPlanSerializer(installments, many=True).data
        })


class FeePaymentViewSet(viewsets.ModelViewSet):
    serializer_class = FeePaymentSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['payment', 'fee_type', 'academic_year', 'term']
    
    def get_queryset(self):
        queryset = FeePayment.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(payment__school=self.request.user.school)
        return queryset


class PaymentPlanViewSet(viewsets.ModelViewSet):
    serializer_class = PaymentPlanSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['payment', 'is_paid', 'due_date']
    
    def get_queryset(self):
        queryset = PaymentPlan.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(payment__school=self.request.user.school)
        if not (self.request.user.is_admin or self.request.user.is_accountant):
            queryset = queryset.filter(payment__user=self.request.user)
        return queryset
    
    @action(detail=True, methods=['post'])
    def mark_paid(self, request, pk=None):
        """Mark an installment as paid"""
        installment = self.get_object()
        installment.is_paid = True
        installment.paid_date = timezone.now()
        installment.save()
        return Response(PaymentPlanSerializer(installment).data)


class PaymentReceiptViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = PaymentReceiptSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['payment']
    
    def get_queryset(self):
        queryset = PaymentReceipt.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(payment__school=self.request.user.school)
        if not (self.request.user.is_admin or self.request.user.is_accountant):
            queryset = queryset.filter(payment__user=self.request.user)
        return queryset


def _payment_callback_common(request, provider: str, get_reference_from_payload):
    """
    Helper pour les callbacks Airtel/Orange/M-Pesa.
    get_reference_from_payload(payload) doit retourner la référence (ex: SCH12-STU45-INV889)
    ou None. On retrouve la PaymentTransaction par reference et on la marque complétée.
    """
    try:
        import json
        payload = json.loads(request.body)
    except Exception as e:
        logger.warning("Payment callback %s invalid JSON: %s", provider, e)
        return JsonResponse({'received': True}, status=400)
    reference = get_reference_from_payload(payload)
    if not reference:
        logger.warning("Payment callback %s: reference introuvable dans payload", provider)
        return JsonResponse({'received': True})
    payment_tx = PaymentTransaction.objects.filter(reference=reference, provider=provider).first()
    if not payment_tx:
        logger.warning("Payment callback %s: transaction introuvable ref=%s", provider, reference)
        return JsonResponse({'received': True})
    if payment_tx.status == 'completed':
        return JsonResponse({'received': True})
    _complete_mobile_money_payment(payment_tx)
    return JsonResponse({'received': True})


@csrf_exempt
@require_http_methods(["POST"])
def airtel_callback(request):
    """Callback Airtel Money : vérifier la transaction et mettre à jour le statut."""
    def get_ref(payload):
        return (payload.get('reference') or payload.get('data', {}).get('reference') or '').strip() or None
    return _payment_callback_common(request, 'airtel', get_ref)


@csrf_exempt
@require_http_methods(["POST"])
def orange_callback(request):
    """Callback Orange Money : vérifier la transaction et mettre à jour le statut."""
    def get_ref(payload):
        return (payload.get('reference') or payload.get('data', {}).get('reference') or '').strip() or None
    return _payment_callback_common(request, 'orange', get_ref)


@csrf_exempt
@require_http_methods(["POST"])
def mpesa_callback(request):
    """Callback M-Pesa : vérifier la transaction et mettre à jour le statut."""
    def get_ref(payload):
        return (payload.get('reference') or payload.get('ConversationID') or payload.get('data', {}).get('reference') or '').strip() or None
    return _payment_callback_common(request, 'mpesa', get_ref)


def _create_cash_movement(school, movement_type, amount, currency, payment_method, source, description, reference_type, reference_id, created_by):
    """Enregistre un mouvement de caisse (entrée ou sortie) et génère automatiquement le bon."""
    movement = CashMovement.objects.create(
        school=school,
        movement_type=movement_type,
        amount=amount,
        currency=currency,
        payment_method=payment_method or None,
        source=source,
        description=description[:255] if description else None,
        reference_type=reference_type,
        reference_id=reference_id,
        created_by=created_by,
    )
    # Générer automatiquement le bon d'entrée/sortie
    try:
        from .utils import generate_cash_movement_voucher_pdf
        generate_cash_movement_voucher_pdf(movement)
    except Exception as e:
        logger.error(f"Erreur lors de la génération du bon pour le mouvement {movement.id}: {e}")
    return movement


class SchoolExpenseViewSet(viewsets.ModelViewSet):
    """Dépenses de l'école - comptable crée/modifie ; seul le responsable (admin) peut approuver/rejeter."""
    serializer_class = SchoolExpenseSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['school', 'category', 'status', 'recorded_by']
    search_fields = ['title', 'description', 'reference']

    def get_queryset(self):
        queryset = SchoolExpense.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        if not (self.request.user.is_admin or self.request.user.is_accountant):
            queryset = queryset.none()
        return queryset

    def perform_create(self, serializer):
        data = serializer.validated_data
        deduct_ft = data.get('deduct_from_fee_type')
        school = self.request.user.school
        if deduct_ft and school and getattr(deduct_ft, 'school_id', None) != school.id:
            from rest_framework.exceptions import ValidationError
            raise ValidationError({'deduct_from_fee_type': 'Le type de frais doit appartenir à votre école.'})
        serializer.save(
            school=school,
            recorded_by=self.request.user
        )

    def perform_update(self, serializer):
        old_instance = serializer.instance
        data = serializer.validated_data
        new_status = data.get('status')
        user = self.request.user
        school = getattr(user, 'school', None) or (old_instance.school if old_instance else None)
        fee_type = data.get('deduct_from_fee_type')
        if fee_type and school and getattr(fee_type, 'school_id', None) != school.id:
            from rest_framework.exceptions import ValidationError
            raise ValidationError({'deduct_from_fee_type': 'Le type de frais doit appartenir à votre école.'})
        # Seul le responsable (admin) peut approuver ou rejeter une dépense
        if new_status in ('APPROVED', 'REJECTED'):
            if not getattr(user, 'is_admin', False):
                from rest_framework.exceptions import PermissionDenied
                raise PermissionDenied('Seul le responsable de l\'école peut autoriser ou rejeter une dépense.')
        instance = serializer.save()
        # Quand une dépense passe à Payée : déduction en caisse (sortie)
        if instance.status == 'PAID' and old_instance.status != 'PAID':
            if not CashMovement.objects.filter(school=instance.school, reference_type='expense', reference_id=instance.id).exists():
                _create_cash_movement(
                    school=instance.school,
                    movement_type='OUT',
                    amount=instance.amount,
                    currency=instance.currency,
                    payment_method=getattr(instance, 'payment_method', None) or 'CASH',
                    source='EXPENSE',
                    description=instance.title or f'Dépense #{instance.id}',
                    reference_type='expense',
                    reference_id=instance.id,
                    created_by=user,
                )


class CaissePagination(PageNumberPagination):
    page_size = 100
    page_size_query_param = 'page_size'
    max_page_size = 500


class CashMovementViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, mixins.CreateModelMixin, viewsets.GenericViewSet):
    """Mouvements de caisse (entrées/sorties). Comptable/Admin peuvent ajouter un ajustement."""
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ['movement_type', 'source', 'currency']
    pagination_class = CaissePagination

    def get_queryset(self):
        queryset = CashMovement.objects.all()
        if self.request.user.school:
            queryset = queryset.filter(school=self.request.user.school)
        if not (self.request.user.is_admin or self.request.user.is_accountant):
            queryset = queryset.none()
        return queryset.select_related('created_by', 'school').order_by('-created_at')

    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        school = getattr(request.user, 'school', None)
        count = len(response.data.get('results', response.data)) if isinstance(response.data, dict) else len(response.data)
        logger.info("Caisse list: school_id=%s, count=%s", school.id if school else None, count)
        return response

    def get_serializer_class(self):
        if self.action == 'create':
            return CashMovementCreateSerializer
        return CashMovementSerializer

    def create(self, request, *args, **kwargs):
        if not (getattr(request.user, 'is_admin', False) and not getattr(request.user, 'is_accountant', False)):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied('Seuls le comptable et le responsable peuvent ajouter un mouvement.')
        if not request.user.school:
            return Response({'detail': 'École non associée.'}, status=status.HTTP_400_BAD_REQUEST)
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        movement = CashMovement.objects.create(
            school=request.user.school,
            movement_type=data['movement_type'],
            amount=data['amount'],
            currency=data.get('currency') or 'CDF',
            description=(data.get('description') or '').strip() or None,
            source='ADJUSTMENT',
            created_by=request.user,
            document=data.get('document'),  # Si uploadé manuellement, sinon généré automatiquement
        )
        # Générer automatiquement le bon si aucun document n'a été uploadé
        if not movement.document:
            try:
                from .utils import generate_cash_movement_voucher_pdf
                generate_cash_movement_voucher_pdf(movement)
            except Exception as e:
                logger.error(f"Erreur lors de la génération du bon pour le mouvement {movement.id}: {e}")
        return Response(
            CashMovementSerializer(movement, context={'request': request}).data,
            status=status.HTTP_201_CREATED
        )

    @action(detail=False, methods=['get'], url_path='balance')
    def balance(self, request):
        """Soldes par devise (entrées - sorties), inclut CashMovement + paiements/dépenses orphelins."""
        school = getattr(request.user, 'school', None)
        if not school:
            logger.info("Caisse balance: utilisateur sans école, retour []")
            return Response([])
        decimal_field = DecimalField(max_digits=12, decimal_places=2)
        zero = Value(Decimal('0'), output_field=decimal_field)
        qs = (
            CashMovement.objects
            .filter(school=school)
            .values('currency')
            .annotate(
                total_in=Coalesce(Sum('amount', filter=Q(movement_type='IN'), output_field=decimal_field), zero),
                total_out=Coalesce(Sum('amount', filter=Q(movement_type='OUT'), output_field=decimal_field), zero),
            )
        )
        totals = {}
        for row in qs:
            c = row['currency']
            totals[c] = {'total_in': float(row['total_in']), 'total_out': float(row['total_out'])}
        payment_ids_with_movement = set(
            CashMovement.objects.filter(school=school, reference_type='payment').values_list('reference_id', flat=True)
        )
        for row in Payment.objects.filter(school=school, status='COMPLETED').exclude(id__in=payment_ids_with_movement).values('currency').annotate(s=Sum('amount')):
            c = row['currency'] or 'CDF'
            if c not in totals:
                totals[c] = {'total_in': 0.0, 'total_out': 0.0}
            totals[c]['total_in'] += float(row['s'] or 0)
        expense_ids_with_movement = set(
            CashMovement.objects.filter(school=school, reference_type='expense').values_list('reference_id', flat=True)
        )
        for row in SchoolExpense.objects.filter(school=school, status='PAID').exclude(id__in=expense_ids_with_movement).values('currency').annotate(s=Sum('amount')):
            c = row['currency'] or 'CDF'
            if c not in totals:
                totals[c] = {'total_in': 0.0, 'total_out': 0.0}
            totals[c]['total_out'] += float(row['s'] or 0)
        result = [{'currency': c, 'total_in': t['total_in'], 'total_out': t['total_out'], 'balance': t['total_in'] - t['total_out']} for c, t in totals.items()]
        if not result:
            result = [
                {'currency': 'CDF', 'total_in': 0.0, 'total_out': 0.0, 'balance': 0.0},
                {'currency': 'USD', 'total_in': 0.0, 'total_out': 0.0, 'balance': 0.0},
            ]
        logger.info("Caisse balance: school_id=%s, devises=%s", school.id, [r['currency'] for r in result])
        return Response(result)

    def _fee_type_names_for_payment(self, payment):
        """Noms des types de frais liés à un paiement (FeePayment)."""
        if not payment:
            return ''
        parts = [fp.fee_type.name for fp in payment.fee_payments.all() if getattr(getattr(fp, 'fee_type', None), 'name', None)]
        return ', '.join(filter(None, parts)) if parts else ''

    @action(detail=False, methods=['get'], url_path='operations')
    def operations(self, request):
        """Liste unifiée : mouvements de caisse + paiements complétés + dépenses payées (sans doublon), avec type de frais."""
        school = getattr(request.user, 'school', None)
        if not school:
            return Response([])
        if not (getattr(request.user, 'is_admin', False) or getattr(request.user, 'is_accountant', False)):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied('Accès réservé au comptable et au responsable.')
        payment_ids_with_movement = set(
            CashMovement.objects.filter(school=school, reference_type='payment').values_list('reference_id', flat=True)
        )
        expense_ids_with_movement = set(
            CashMovement.objects.filter(school=school, reference_type='expense').values_list('reference_id', flat=True)
        )
        payment_ids_from_movements = set(
            CashMovement.objects.filter(school=school, reference_type='payment').values_list('reference_id', flat=True)
        )
        expense_ids_from_movements = set(
            CashMovement.objects.filter(school=school, reference_type='expense').values_list('reference_id', flat=True)
        )
        payments_lookup = {}
        if payment_ids_from_movements:
            for p in Payment.objects.filter(id__in=payment_ids_from_movements).prefetch_related('fee_payments__fee_type'):
                payments_lookup[p.id] = self._fee_type_names_for_payment(p)
        expenses_lookup = {}
        if expense_ids_from_movements:
            for e in SchoolExpense.objects.filter(id__in=expense_ids_from_movements).select_related('deduct_from_fee_type'):
                expenses_lookup[e.id] = (e.deduct_from_fee_type.name if e.deduct_from_fee_type else '') or ''
        out = []
        # 1) Tous les mouvements de caisse
        for m in CashMovement.objects.filter(school=school).select_related('created_by').order_by('-created_at'):
            fee_type_name = ''
            if m.reference_type == 'payment' and m.reference_id:
                fee_type_name = payments_lookup.get(m.reference_id, '')
            elif m.reference_type == 'expense' and m.reference_id:
                fee_type_name = expenses_lookup.get(m.reference_id, '')
            document_url = None
            if m.document:
                document_url = request.build_absolute_uri(m.document.url)
            out.append({
                'id': m.id,
                'created_at': m.created_at.isoformat() if m.created_at else None,
                'movement_type': m.movement_type,
                'source': m.source,
                'amount': float(m.amount),
                'currency': m.currency,
                'description': m.description or '',
                'reference_type': m.reference_type,
                'reference_id': m.reference_id,
                'fee_type_name': fee_type_name,
                'document_url': document_url,
            })
        # 2) Paiements complétés orphelins (pas de bon de caisse, donc pas de document_url)
        orphans_payment = Payment.objects.filter(school=school, status='COMPLETED').exclude(id__in=payment_ids_with_movement).prefetch_related('fee_payments__fee_type').order_by('-payment_date', '-updated_at')[:500]
        for p in orphans_payment:
            out.append({
                'id': f'payment-{p.id}',
                'created_at': (p.payment_date or p.updated_at or p.created_at).isoformat() if (p.payment_date or p.updated_at or p.created_at) else None,
                'movement_type': 'IN',
                'source': 'PAYMENT',
                'amount': float(p.amount),
                'currency': p.currency,
                'description': f'Paiement {p.payment_id}',
                'reference_type': 'payment',
                'reference_id': p.id,
                'fee_type_name': self._fee_type_names_for_payment(p),
                'document_url': None,  # Pas de bon de caisse pour les paiements orphelins
            })
        # 3) Dépenses payées orphelines (pas de bon de caisse, donc pas de document_url)
        for e in SchoolExpense.objects.filter(school=school, status='PAID').exclude(id__in=expense_ids_with_movement).select_related('deduct_from_fee_type').order_by('-updated_at', '-created_at')[:500]:
            out.append({
                'id': f'expense-{e.id}',
                'created_at': (e.updated_at or e.created_at).isoformat() if (e.updated_at or e.created_at) else None,
                'movement_type': 'OUT',
                'source': 'EXPENSE',
                'amount': float(e.amount),
                'currency': e.currency,
                'description': e.title or f'Dépense #{e.id}',
                'reference_type': 'expense',
                'reference_id': e.id,
                'fee_type_name': (e.deduct_from_fee_type.name if e.deduct_from_fee_type else '') or '',
                'document_url': None,  # Pas de bon de caisse pour les dépenses orphelines
            })
        out.sort(key=lambda x: x['created_at'] or '', reverse=True)
        out = out[:500]
        logger.info("Caisse operations: school_id=%s, total=%s", school.id, len(out))
        return Response(out)

    @action(detail=False, methods=['post'], url_path='generate-missing-vouchers')
    def generate_missing_vouchers(self, request):
        """Génère les bons d'entrée/sortie manquants pour tous les mouvements sans document, et crée les CashMovement manquants pour les paiements/dépenses orphelins."""
        school = getattr(request.user, 'school', None)
        if not school:
            return Response({'detail': 'École non associée.'}, status=status.HTTP_400_BAD_REQUEST)
        if not (getattr(request.user, 'is_admin', False) or getattr(request.user, 'is_accountant', False)):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied('Accès réservé au comptable et au responsable.')
        
        # 1) Créer les CashMovement manquants pour les paiements orphelins
        payment_ids_with_movement = set(
            CashMovement.objects.filter(school=school, reference_type='payment')
            .values_list('reference_id', flat=True)
        )
        orphan_payments = Payment.objects.filter(
            school=school, 
            status='COMPLETED'
        ).exclude(id__in=payment_ids_with_movement)
        
        created_movements = 0
        for payment in orphan_payments:
            try:
                if not CashMovement.objects.filter(school=school, reference_type='payment', reference_id=payment.id).exists():
                    _create_cash_movement(
                        school=school,
                        movement_type='IN',
                        amount=payment.amount,
                        currency=payment.currency,
                        payment_method=payment.payment_method,
                        source='PAYMENT',
                        description=f'Paiement {payment.payment_id}',
                        reference_type='payment',
                        reference_id=payment.id,
                        created_by=request.user,
                    )
                    created_movements += 1
            except Exception as e:
                logger.error(f"Erreur création CashMovement pour paiement {payment.id}: {e}")
        
        # 2) Créer les CashMovement manquants pour les dépenses orphelines
        expense_ids_with_movement = set(
            CashMovement.objects.filter(school=school, reference_type='expense')
            .values_list('reference_id', flat=True)
        )
        orphan_expenses = SchoolExpense.objects.filter(
            school=school,
            status='PAID'
        ).exclude(id__in=expense_ids_with_movement)
        
        for expense in orphan_expenses:
            try:
                if not CashMovement.objects.filter(school=school, reference_type='expense', reference_id=expense.id).exists():
                    _create_cash_movement(
                        school=school,
                        movement_type='OUT',
                        amount=expense.amount,
                        currency=expense.currency,
                        payment_method=getattr(expense, 'payment_method', None) or 'CASH',
                        source='EXPENSE',
                        description=expense.title or f'Dépense #{expense.id}',
                        reference_type='expense',
                        reference_id=expense.id,
                        created_by=request.user,
                    )
                    created_movements += 1
            except Exception as e:
                logger.error(f"Erreur création CashMovement pour dépense {expense.id}: {e}")
        
        # 3) Générer les bons pour tous les CashMovement sans document
        movements_without_doc = CashMovement.objects.filter(school=school).filter(document__isnull=True)
        total_count = movements_without_doc.count()
        logger.info(f"Génération bons manquants: school_id={school.id}, mouvements_créés={created_movements}, total_mouvements_sans_doc={total_count}")
        count = 0
        errors = []
        for movement in movements_without_doc:
            try:
                from .utils import generate_cash_movement_voucher_pdf
                generate_cash_movement_voucher_pdf(movement)
                # Vérifier que le document a bien été créé
                movement.refresh_from_db()
                if movement.document:
                    count += 1
                else:
                    errors.append(f"Mouvement {movement.id}: Document non créé après génération")
            except Exception as e:
                import traceback
                error_detail = traceback.format_exc()
                errors.append(f"Mouvement {movement.id}: {str(e)}")
                logger.error(f"Erreur génération bon mouvement {movement.id}: {e}\n{error_detail}")
        
        message_parts = []
        if created_movements > 0:
            message_parts.append(f"{created_movements} mouvement(s) créé(s)")
        if count > 0:
            message_parts.append(f"{count} bon(s) généré(s)")
        if not message_parts:
            message_parts.append("Aucune action nécessaire")
        
        return Response({
            'generated': count,
            'created': created_movements,
            'total': total_count,
            'errors': errors[:10] if errors else None,  # Limiter à 10 erreurs pour la réponse
            'message': '. '.join(message_parts) + '.'
        })
