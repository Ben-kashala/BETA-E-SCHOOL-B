"""
Configuration de l'application accounts
"""
from django.apps import AppConfig


class AccountsConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.accounts'
    
    def ready(self):
        """Import des signaux et formulaire de connexion admin personnalisé."""
        import apps.accounts.signals  # noqa
        from django.contrib import admin
        from .forms import ESchoolAdminAuthenticationForm
        admin.site.login_form = ESchoolAdminAuthenticationForm
