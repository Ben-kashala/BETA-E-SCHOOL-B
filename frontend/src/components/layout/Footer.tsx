import { Mail, Phone, MapPin, Facebook, Twitter, Linkedin, Instagram } from 'lucide-react'
import { useAuthStore } from '@/store/authStore'

export default function Footer() {
  const { user } = useAuthStore()
  const currentYear = new Date().getFullYear()
  const schoolName = user?.school?.name || 'E-School Management'

  return (
    <footer className="bg-eschool-header border-t border-eschool-header-text/20 mt-auto transition-colors">
      <div className="max-w-7xl mx-auto px-6 py-8">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8">
          {/* À propos */}
          <div>
            <h3 className="text-lg font-semibold text-eschool-header-text mb-4">
              À propos
            </h3>
            <p className="text-sm text-eschool-header-text/80 mb-4">
              {schoolName} - Plateforme de gestion scolaire moderne et intuitive pour une meilleure expérience éducative.
            </p>
            <div className="flex space-x-4">
              <a href="#" className="text-eschool-header-text/70 hover:text-eschool-header-text transition-colors" aria-label="Facebook">
                <Facebook className="w-5 h-5" />
              </a>
              <a href="#" className="text-eschool-header-text/70 hover:text-eschool-header-text transition-colors" aria-label="Twitter">
                <Twitter className="w-5 h-5" />
              </a>
              <a href="#" className="text-eschool-header-text/70 hover:text-eschool-header-text transition-colors" aria-label="LinkedIn">
                <Linkedin className="w-5 h-5" />
              </a>
              <a href="#" className="text-eschool-header-text/70 hover:text-eschool-header-text transition-colors" aria-label="Instagram">
                <Instagram className="w-5 h-5" />
              </a>
            </div>
          </div>

          {/* Liens rapides */}
          <div>
            <h3 className="text-lg font-semibold text-eschool-header-text mb-4">
              Liens rapides
            </h3>
            <ul className="space-y-2">
              <li><a href="#" className="text-sm text-eschool-header-text/80 hover:text-eschool-header-text transition-colors">Tableau de bord</a></li>
              <li><a href="#" className="text-sm text-eschool-header-text/80 hover:text-eschool-header-text transition-colors">Cours</a></li>
              <li><a href="Library" className="text-sm text-eschool-header-text/80 hover:text-eschool-header-text transition-colors">Bibliothèque</a></li>
              <li><a href="#" className="text-sm text-eschool-header-text/80 hover:text-eschool-header-text transition-colors">Calendrier</a></li>
            </ul>
          </div>

          {/* Support */}
          <div>
            <h3 className="text-lg font-semibold text-eschool-header-text mb-4">
              Support
            </h3>
            <ul className="space-y-2">
              <li><a href="#" className="text-sm text-eschool-header-text/80 hover:text-eschool-header-text transition-colors">Centre d'aide</a></li>
              <li><a href="#" className="text-sm text-eschool-header-text/80 hover:text-eschool-header-text transition-colors">Documentation</a></li>
              <li><a href="#" className="text-sm text-eschool-header-text/80 hover:text-eschool-header-text transition-colors">Contact</a></li>
              <li><a href="#" className="text-sm text-eschool-header-text/80 hover:text-eschool-header-text transition-colors">FAQ</a></li>
            </ul>
          </div>

          {/* Contact */}
          <div>
            <h3 className="text-lg font-semibold text-eschool-header-text mb-4">
              Contact
            </h3>
            <ul className="space-y-3">
              <li className="flex items-start space-x-3">
                <MapPin className="w-5 h-5 text-eschool-body mt-0.5 flex-shrink-0" />
                <span className="text-sm text-eschool-header-text/80">{user?.school?.address || "Adresse de l'école"}</span>
              </li>
              <li className="flex items-center space-x-3">
                <Phone className="w-5 h-5 text-eschool-body flex-shrink-0" />
                <span className="text-sm text-eschool-header-text/80">{user?.school?.phone || '+243 XXX XXX XXX'}</span>
              </li>
              <li className="flex items-center space-x-3">
                <Mail className="w-5 h-5 text-eschool-body flex-shrink-0" />
                <span className="text-sm text-eschool-header-text/80">{user?.school?.email || 'contact@ecole.com'}</span>
              </li>
            </ul>
          </div>
        </div>

        {/* Copyright */}
        <div className="mt-8 pt-6 border-t border-eschool-header-text/20">
          <div className="flex flex-col md:flex-row justify-between items-center space-y-2 md:space-y-0">
            <p className="text-sm text-eschool-header-text/80">
              © {currentYear} {schoolName}. Tous droits réservés.
            </p>
            <div className="flex space-x-6">
              <a href="#" className="text-sm text-eschool-header-text/80 hover:text-eschool-header-text transition-colors">Politique de confidentialité</a>
              <a href="#" className="text-sm text-eschool-header-text/80 hover:text-eschool-header-text transition-colors">Conditions d'utilisation</a>
            </div>
          </div>
        </div>
      </div>
    </footer>
  )
}
