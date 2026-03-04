from django.contrib import admin
from django.utils.translation import gettext_lazy as _
from .models import SchoolPaymentConfig, FeeType, Payment, FeePayment, PaymentPlan, PaymentReceipt
from apps.schools.admin_base import SchoolScopedAdminMixin


@admin.register(SchoolPaymentConfig)
class SchoolPaymentConfigAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    """Moyens de paiement par école. Admin école : sa config uniquement. Superadmin : toutes les écoles."""
    list_display = ['school', 'is_active', 'has_flutterwave', 'mobile_money_provider', 'updated_at']
    list_filter = ['is_active', 'mobile_money_provider', 'school']
    search_fields = ['school__name', 'school__code']
    raw_id_fields = []  # school géré par le mixin
    fieldsets = (
        (None, {
            'fields': ('school', 'is_active'),
        }),
        (_('Flutterwave (cartes VISA/Mastercard + Mobile Money)'), {
            'fields': ('flutterwave_public_key', 'flutterwave_secret_key'),
            'description': _(
                'Laissez vides pour utiliser les clés globales (paramètres Django / .env). '
                'Sinon, saisissez les clés de l\'école pour que les paiements soient encaissés sur son compte Flutterwave.'
            ),
        }),
        (_('Mobile Money (Orange, M-Pesa, Airtel)'), {
            'fields': ('mobile_money_provider',),
        }),
    )

    def has_flutterwave(self, obj):
        return bool(obj.flutterwave_public_key and obj.flutterwave_secret_key)
    has_flutterwave.short_description = _('Flutterwave configuré')
    has_flutterwave.boolean = True


@admin.register(FeeType)
class FeeTypeAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['name', 'school', 'amount', 'currency', 'is_active']
    list_filter = ['school', 'is_active']
    search_fields = ['name', 'description']


@admin.register(Payment)
class PaymentAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['payment_id', 'user', 'student', 'amount', 'currency', 'payment_method', 'status', 'created_at']
    list_filter = ['status', 'payment_method', 'school', 'created_at']
    search_fields = ['payment_id', 'user__username', 'reference_number', 'transaction_id']
    readonly_fields = ['created_at', 'updated_at']


@admin.register(FeePayment)
class FeePaymentAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['payment', 'fee_type', 'amount', 'academic_year', 'term']
    list_filter = ['academic_year', 'term', 'fee_type']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
            return qs.filter(payment__school=request.user.school)
        return qs


@admin.register(PaymentPlan)
class PaymentPlanAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['payment', 'installment_number', 'amount', 'due_date', 'is_paid']
    list_filter = ['is_paid', 'due_date']
    ordering = ['payment', 'installment_number']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
            return qs.filter(payment__school=request.user.school)
        return qs


@admin.register(PaymentReceipt)
class PaymentReceiptAdmin(SchoolScopedAdminMixin, admin.ModelAdmin):
    list_display = ['receipt_number', 'payment', 'generated_at']
    search_fields = ['receipt_number', 'payment__payment_id']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_authenticated and request.user.is_admin and request.user.school and not request.user.is_superuser:
            return qs.filter(payment__school=request.user.school)
        return qs
