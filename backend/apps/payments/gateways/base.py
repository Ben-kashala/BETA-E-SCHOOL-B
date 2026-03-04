"""
Base types for payment gateways.
"""
from dataclasses import dataclass
from typing import Optional


@dataclass
class GatewayResult:
    """Result of a gateway operation (initiate, confirm, etc.)."""
    success: bool
    transaction_id: Optional[str] = None
    message: str = ''
    client_secret: Optional[str] = None  # For Stripe PaymentIntent
    requires_action: bool = False  # e.g. 3DS or USSD confirmation
