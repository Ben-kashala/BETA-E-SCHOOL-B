"""
Commande pour créer le SUPERADMIN propriétaire du système (premier utilisateur au déploiement).
Usage: python manage.py seed_initial

Variables d'environnement optionnelles:
- ADMIN_USERNAME (défaut: Alidorsabue — doit rester ce nom pour le superadmin protégé)
- ADMIN_EMAIL (défaut: alidorsabue@africait.com)
- ADMIN_PASSWORD (obligatoire en prod, sans ça la commande ne crée rien)
- SCHOOL_NAME (défaut: COLLEGE VITAL MAURICE) - optionnel, pour créer une première école
- SCHOOL_CODE (défaut: CVMA) - optionnel, pour créer une première école

Le superadmin créé (Alidorsabue) est protégé : aucun autre utilisateur ne peut le modifier
ni le supprimer. Lui seul peut modifier son propre compte. Les admins plateforme (ADMIN sans
école) peuvent créer des écoles et des admins d'école, mais ne peuvent jamais toucher au
compte superadmin.
"""
import os
from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from apps.schools.models import School
from apps.accounts.constants import SUPERADMIN_USERNAME

User = get_user_model()


class Command(BaseCommand):
    help = "Crée un SUPERADMIN (gère tout) depuis les variables d'environnement"

    def handle(self, *args, **options):
        username = os.environ.get('ADMIN_USERNAME', SUPERADMIN_USERNAME)
        email = os.environ.get('ADMIN_EMAIL', 'alidorsabue@africait.com')
        password = os.environ.get('ADMIN_PASSWORD', "Virgi@1996Ali@")
        school_name = os.environ.get('SCHOOL_NAME', 'COLLEGE VITAL MAURICE')
        school_code = os.environ.get('SCHOOL_CODE', 'CVMA')
        create_school = os.environ.get('CREATE_SCHOOL', 'true').lower() == 'true'

        if not password:
            self.stdout.write(
                self.style.WARNING(
                    "ADMIN_PASSWORD non défini. Définissez ADMIN_PASSWORD dans les variables "
                    "d'environnement puis relancez: python manage.py seed_initial"
                )
            )
            return

        # Créer ou récupérer l'école (optionnel, pour faciliter les premiers tests)
        # Cette étape peut être ignorée si CREATE_SCHOOL=false ou si la connexion DB échoue
        school = None
        if create_school:
            try:
                school, created = School.objects.get_or_create(
                    code=school_code,
                    defaults={
                        'name': school_name,
                        'address': 'Adresse de l\'école',
                        'city': 'Kinshasa',
                        'country': 'RDC',
                        'phone': '+243835561737',
                        'email': email,
                        'academic_year': '2026-2027',
                        'currency': 'CDF',
                        'language': 'fr',
                        'is_active': True,
                    }
                )
                if created:
                    self.stdout.write(self.style.SUCCESS(f"✓ École créée: {school.name} (code: {school.code})"))
                else:
                    self.stdout.write(f"École existante: {school.name}")
            except Exception as e:
                self.stdout.write(
                    self.style.WARNING(
                        f"Impossible de créer/récupérer l'école (peut être normal en local): {e}\n"
                        "La création du superadmin continuera sans école."
                    )
                )
                school = None

        # Créer le SUPERADMIN s'il n'existe pas
        try:
            if User.objects.filter(username=username).exists():
                user = User.objects.get(username=username)
                # Si l'utilisateur existe mais que le mot de passe n'est pas hashé (commence par pbkdf2_sha256$)
                # ou s'il n'est pas superuser, le corriger
                needs_update = False
                
                if not user.password.startswith('pbkdf2_sha256$'):
                    # Le mot de passe n'est pas hashé, le hasher
                    from django.contrib.auth.hashers import make_password
                    user.password = make_password(password)
                    needs_update = True
                    self.stdout.write(self.style.WARNING(f"⚠ Mot de passe de '{username}' n'était pas hashé, correction en cours..."))
                
                if not user.is_superuser:
                    user.is_superuser = True
                    needs_update = True
                    self.stdout.write(self.style.WARNING(f"⚠ is_superuser était False, correction en cours..."))
                
                if not user.is_staff:
                    user.is_staff = True
                    needs_update = True
                    self.stdout.write(self.style.WARNING(f"⚠ is_staff était False, correction en cours..."))
                
                if not user.is_active:
                    user.is_active = True
                    needs_update = True
                    self.stdout.write(self.style.WARNING(f"⚠ is_active était False, correction en cours..."))
                
                # S'assurer que le rôle est défini (ADMIN pour le superadmin)
                if not user.role or user.role == '':
                    user.role = 'ADMIN'
                    needs_update = True
                    self.stdout.write(self.style.WARNING(f"⚠ Le rôle n'était pas défini, définition à 'ADMIN'..."))
                
                # Le superadmin n'a pas besoin d'être associé à une école spécifique
                # Il peut gérer toutes les écoles
                if needs_update:
                    user.save()
                    self.stdout.write(self.style.SUCCESS(f"✓ Utilisateur '{username}' mis à jour et promu SUPERADMIN"))
                else:
                    self.stdout.write(f"SUPERADMIN '{username}' existe déjà et est correctement configuré")
                return

            # Créer un SUPERADMIN (is_superuser=True, pas d'école assignée)
            # Le superadmin peut gérer toutes les écoles
            User.objects.create_superuser(
                username=username,
                email=email,
                password=password,
                role='ADMIN',  # Role reste ADMIN mais is_superuser=True le distingue
                # Pas de school assignée - le superadmin gère toutes les écoles
            )
            self.stdout.write(self.style.SUCCESS(f"✓ SUPERADMIN '{username}' créé avec succès !"))
            self.stdout.write(self.style.SUCCESS("  Ce superadmin peut :"))
            self.stdout.write("    - Créer et gérer toutes les écoles")
            self.stdout.write("    - Créer et gérer les admins d'école")
            self.stdout.write("    - Voir toutes les données de toutes les écoles")
            self.stdout.write(f"  Connexion: {username} / (mot de passe défini dans ADMIN_PASSWORD)")
        except Exception as e:
            self.stdout.write(
                self.style.ERROR(
                    f"Erreur lors de la création du superadmin: {e}\n"
                    "Vérifiez votre configuration de base de données dans .env\n"
                    "Pour le développement local, utilisez USE_SQLITE=True ou configurez PostgreSQL local.\n"
                    "Voir UTILISER_SEED_INITIAL_LOCAL.md pour plus d'informations."
                )
            )
            raise
