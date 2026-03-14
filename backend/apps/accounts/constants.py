"""
Constantes pour le module accounts.
Le superadmin protégé est l'unique propriétaire du système : il ne peut être
modifié ou supprimé que par lui-même. Aucun autre utilisateur (y compris
les admins plateforme) ne peut le modifier ou le supprimer.
"""
# Nom d'utilisateur du superadmin protégé (créé au premier déploiement via seed_initial)
SUPERADMIN_USERNAME = 'Alidorsabue'
