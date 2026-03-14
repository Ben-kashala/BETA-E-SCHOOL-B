"""
Signals pour le modèle User
"""
from django.db.models.signals import pre_save, post_save
from django.dispatch import receiver
from django.contrib.contenttypes.models import ContentType
from django.contrib.auth.models import Permission
from django.conf import settings
from .models import User
from .constants import SUPERADMIN_USERNAME

# Mots de passe par défaut pour les parents et élèves
# Ces valeurs peuvent être surchargées via les variables d'environnement
DEFAULT_PARENT_PASSWORD = getattr(settings, 'DEFAULT_PARENT_PASSWORD', 'Parent@@')
DEFAULT_STUDENT_PASSWORD = getattr(settings, 'DEFAULT_STUDENT_PASSWORD', 'Eleve@@')


@receiver(pre_save, sender=User)
def enforce_unique_protected_superadmin(sender, instance, **kwargs):
    """
    Seul l'utilisateur Alidorsabue peut avoir is_superuser=True.
    Tout autre utilisateur qui tenterait d'avoir is_superuser est forcé à False.
    """
    if instance.is_superuser and instance.username != SUPERADMIN_USERNAME:
        instance.is_superuser = False


@receiver(pre_save, sender=User)
def auto_activate_staff_for_admin(sender, instance, **kwargs):
    """
    Active automatiquement is_staff pour les administrateurs (école ou plateforme)
    afin qu'ils puissent accéder à Django Admin.
    """
    if instance.role == 'ADMIN':
        instance.is_staff = True


@receiver(post_save, sender=User)
def grant_admin_permissions_to_school_admin(sender, instance, created, **kwargs):
    """
    Donne automatiquement toutes les permissions nécessaires aux administrateurs
    (d'école ou plateforme) pour qu'ils puissent voir et modifier les objets dans Django Admin.
    """
    if instance.role == 'ADMIN' and instance.is_staff:
        # Donner toutes les permissions à l'administrateur d'école
        # Cela permet d'accéder à tous les modèles dans Django Admin
        # Le filtrage par école sera géré par SchoolScopedAdminMixin
        
        # Récupérer toutes les permissions de contenu
        content_types = ContentType.objects.all()
        permissions = Permission.objects.filter(content_type__in=content_types)
        
        # Assigner toutes les permissions à l'utilisateur
        instance.user_permissions.set(permissions)


@receiver(post_save, sender=User)
def set_default_password_for_parents_and_students(sender, instance, created, **kwargs):
    """
    Définit automatiquement le mot de passe par défaut lors de la création
    d'un nouveau parent ou élève si aucun mot de passe n'a été défini.
    
    Ce signal s'exécute après la création d'un utilisateur et vérifie si :
    - L'utilisateur vient d'être créé (created=True)
    - C'est un parent ou un élève
    - Le mot de passe n'a pas été défini (password vide ou None)
    
    Si ces conditions sont remplies, le mot de passe par défaut est défini.
    
    Note: Ce signal sert de filet de sécurité. Dans la plupart des cas,
    le mot de passe sera déjà défini lors de la création (via create_user()
    dans enrollment/views.py). Ce signal garantit que même si un utilisateur
    est créé sans mot de passe, il recevra le mot de passe par défaut.
    """
    if created:
        # Nouvel utilisateur créé
        if instance.role == 'PARENT':
            # Vérifier si le mot de passe est vide ou non défini
            # Si l'utilisateur a été créé avec create_user() sans password, 
            # Django peut créer un mot de passe aléatoire, donc on vérifie
            # si le hash correspond à un mot de passe vide
            try:
                # Tenter de vérifier avec un mot de passe vide
                # Si ça échoue, le mot de passe a été défini
                if not instance.password or instance.password == '':
                    instance.set_password(DEFAULT_PARENT_PASSWORD)
                    instance.save(update_fields=['password'])
            except:
                # Le mot de passe a déjà été défini, ne rien faire
                pass
        elif instance.role == 'STUDENT':
            # Même logique pour les élèves
            try:
                if not instance.password or instance.password == '':
                    instance.set_password(DEFAULT_STUDENT_PASSWORD)
                    instance.save(update_fields=['password'])
            except:
                # Le mot de passe a déjà été défini, ne rien faire
                pass
