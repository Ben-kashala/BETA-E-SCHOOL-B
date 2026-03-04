from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    FeeTypeViewSet, PaymentViewSet, FeePaymentViewSet,
    PaymentPlanViewSet, PaymentReceiptViewSet, SchoolExpenseViewSet,
    CashMovementViewSet,
    flutterwave_webhook,
)

router = DefaultRouter()
router.register(r'fee-types', FeeTypeViewSet, basename='fee-type')
router.register(r'payments', PaymentViewSet, basename='payment')
router.register(r'fee-payments', FeePaymentViewSet, basename='fee-payment')
router.register(r'payment-plans', PaymentPlanViewSet, basename='payment-plan')
router.register(r'receipts', PaymentReceiptViewSet, basename='receipt')
router.register(r'expenses', SchoolExpenseViewSet, basename='expense')
router.register(r'caisse', CashMovementViewSet, basename='caisse')

urlpatterns = [
    path('', include(router.urls)),
    path('webhook/flutterwave/', flutterwave_webhook),
]
