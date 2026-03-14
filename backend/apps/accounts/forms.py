"""
Formulaires personnalisés (ex. connexion admin avec vérification du verrouillage plateforme).
"""
from django import forms
from django.contrib.admin.forms import AdminAuthenticationForm


class ESchoolAdminAuthenticationForm(AdminAuthenticationForm):
    """
    Formulaire de connexion à l'admin Django. Si la plateforme est verrouillée,
    seul le superadmin peut se connecter.
    """

    def clean(self):
        cleaned_data = super().clean()
        user = self.get_user()
        if user is None:
            return cleaned_data
        try:
            from .models import PlatformSettings
            ps = PlatformSettings.get_singleton()
            if ps.is_platform_locked and not getattr(user, 'is_protected_superadmin', False):
                msg = ps.locked_message or (
                    'La plateforme est temporairement indisponible. '
                    'Seul le superadmin peut se connecter.'
                )
                raise forms.ValidationError(msg)
        except Exception:
            pass
        return cleaned_data
