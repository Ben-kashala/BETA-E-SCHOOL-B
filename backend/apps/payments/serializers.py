from rest_framework import serializers
from .models import FeeType, Payment, FeePayment, PaymentPlan, PaymentReceipt, SchoolExpense, CashMovement


class FeeTypeSerializer(serializers.ModelSerializer):
    school_name = serializers.CharField(source='school.name', read_only=True)
    
    class Meta:
        model = FeeType
        fields = '__all__'
        read_only_fields = ['school']  # school est assigné automatiquement dans perform_create
        extra_kwargs = {
            'school': {'required': False, 'allow_null': True, 'read_only': True}  # Le champ school est assigné automatiquement dans perform_create
        }


class PaymentPlanSerializer(serializers.ModelSerializer):
    class Meta:
        model = PaymentPlan
        fields = '__all__'
        read_only_fields = ['paid_date']


class PaymentReceiptSerializer(serializers.ModelSerializer):
    payment_id = serializers.CharField(source='payment.payment_id', read_only=True)
    
    class Meta:
        model = PaymentReceipt
        fields = '__all__'
        read_only_fields = ['generated_at']


class FeePaymentSerializer(serializers.ModelSerializer):
    fee_type_name = serializers.CharField(source='fee_type.name', read_only=True)
    
    class Meta:
        model = FeePayment
        fields = '__all__'


class PaymentSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source='user.get_full_name', read_only=True)
    student_name = serializers.CharField(source='student.user.get_full_name', read_only=True)
    school_name = serializers.CharField(source='school.name', read_only=True)
    fee_payments = FeePaymentSerializer(many=True, read_only=True)
    installments = PaymentPlanSerializer(many=True, read_only=True)
    receipt = PaymentReceiptSerializer(read_only=True)
    
    class Meta:
        model = Payment
        fields = '__all__'
        read_only_fields = ['created_at', 'updated_at', 'payment_id', 'school']
        extra_kwargs = {
            'school': {'required': False, 'allow_null': True, 'read_only': True},
            'user': {'required': False, 'allow_null': True},  # Comptable/Admin peuvent fournir user (parent)
        }


class SchoolExpenseSerializer(serializers.ModelSerializer):
    recorded_by_name = serializers.SerializerMethodField(read_only=True)
    school_name = serializers.CharField(source='school.name', read_only=True)
    deduct_from_fee_type_name = serializers.SerializerMethodField(read_only=True)

    def get_recorded_by_name(self, obj):
        return obj.recorded_by.get_full_name() if obj.recorded_by else ''

    def get_deduct_from_fee_type_name(self, obj):
        return obj.deduct_from_fee_type.name if obj.deduct_from_fee_type else None

    class Meta:
        model = SchoolExpense
        fields = '__all__'
        read_only_fields = ['created_at', 'updated_at']
        extra_kwargs = {
            'school': {'required': False, 'allow_null': True},
            'recorded_by': {'required': False, 'allow_null': True},
        }


class CashMovementSerializer(serializers.ModelSerializer):
    created_by_name = serializers.SerializerMethodField(read_only=True)
    document_url = serializers.SerializerMethodField(read_only=True)

    def get_created_by_name(self, obj):
        return obj.created_by.get_full_name() if obj.created_by else ''

    def get_document_url(self, obj):
        if obj.document:
            request = self.context.get('request')
            if request:
                return request.build_absolute_uri(obj.document.url)
        return None

    class Meta:
        model = CashMovement
        fields = '__all__'
        read_only_fields = ['created_at']


class CashMovementCreateSerializer(serializers.Serializer):
    """Pour les ajustements manuels : entrée ou sortie."""
    movement_type = serializers.ChoiceField(choices=[('IN', 'Entrée'), ('OUT', 'Sortie')])
    amount = serializers.DecimalField(max_digits=12, decimal_places=2, min_value=0.01)
    currency = serializers.CharField(max_length=3, default='CDF')
    description = serializers.CharField(max_length=255, required=False, allow_blank=True)
    document = serializers.FileField(required=False, allow_null=True)


# --- Paiement Mobile Money & Carte (gateways) ---
MOBILE_MONEY_METHODS = [
    'MOBILE_MONEY_ORANGE', 'MOBILE_MONEY_MPESA', 'MOBILE_MONEY_AIRTEL',
]


class InitiateMobileSerializer(serializers.Serializer):
    """Corps de la requête pour initier un paiement Mobile Money."""
    payment_id = serializers.IntegerField(help_text="ID du paiement (PENDING)")
    phone_number = serializers.CharField(max_length=30, trim_whitespace=True, allow_blank=False)
    payment_method = serializers.ChoiceField(choices=[(m, m) for m in MOBILE_MONEY_METHODS])

    def validate_phone_number(self, value):
        if not value or not value.strip():
            raise serializers.ValidationError("Le numéro de téléphone est requis.")
        return value.strip()


class InitiateCardSerializer(serializers.Serializer):
    """Corps de la requête pour initier un paiement par carte (Stripe)."""
    payment_id = serializers.IntegerField(help_text="ID du paiement (PENDING)")
