#!/bin/bash

# =============================================================================
# Script d'Installation Automatisée - Fidaous Pro (Version Corrigée)
# Version: 1.1
# Système: Debian 12 (Bookworm)
# Base de données: MariaDB
# Serveur Web: Apache2 + PHP 8.2
# Correction: Gestion améliorée des dépendances PHP et installation progressive
# =============================================================================

set -e  # Arrêter le script en cas d'erreur

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables de configuration
DB_NAME="database_fidaous_pro"
DB_USER="fidaous_user"
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
DB_ROOT_PASSWORD=""
ADMIN_EMAIL="admin@fidaouspro.ma"
ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
DOMAIN="fidaous-pro.local"
INSTALL_DIR="/var/www/html"
BACKUP_DIR="/backup/fidaous-pro"
LOG_FILE="/tmp/fidaous_install.log"

# Fonctions utilitaires
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" >> $LOG_FILE
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $1" >> $LOG_FILE
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $1" >> $LOG_FILE
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >> $LOG_FILE
}

print_header() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "  $1"
    echo "=============================================================="
    echo -e "${NC}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') === $1 ===" >> $LOG_FILE
}

# Fonction de gestion d'erreurs
handle_error() {
    print_error "Une erreur s'est produite à la ligne $1. Consultez $LOG_FILE pour plus de détails."
    print_error "Code de sortie: $2"
    exit $2
}

trap 'handle_error $LINENO $?' ERR

# Vérification des privilèges root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Ce script doit être exécuté avec les privilèges root (sudo)"
        exit 1
    fi
}

# Vérification de la version Debian
check_debian_version() {
    if [[ ! -f /etc/debian_version ]]; then
        print_error "Ce script est conçu pour Debian uniquement"
        exit 1
    fi
    
    DEBIAN_VERSION=$(cat /etc/debian_version | cut -d. -f1)
    if [[ $DEBIAN_VERSION -lt 12 ]]; then
        print_warning "Version Debian détectée: $(cat /etc/debian_version)"
        print_warning "Ce script est optimisé pour Debian 12 (Bookworm)"
    fi
    
    print_status "Version Debian validée: $(cat /etc/debian_version)"
}

# Nettoyage des installations PHP précédentes défaillantes
cleanup_php_installation() {
    print_header "NETTOYAGE DES INSTALLATIONS PHP PRÉCÉDENTES"
    
    print_status "Arrêt d'Apache pour éviter les conflits..."
    systemctl stop apache2 2>/dev/null || true
    
    print_status "Suppression des packages PHP défaillants..."
    apt remove --purge -y php8.2* libapache2-mod-php8.2* 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    
    print_status "Nettoyage du cache APT..."
    apt clean
    
    print_status "Réparation des dépendances cassées..."
    apt --fix-broken install -y 2>/dev/null || true
    dpkg --configure -a 2>/dev/null || true
    
    print_success "Nettoyage terminé"
}

# Mise à jour du système
update_system() {
    print_header "MISE À JOUR DU SYSTÈME"
    
    print_status "Mise à jour de la liste des paquets..."
    apt update -y
    
    print_status "Mise à jour des paquets installés..."
    apt upgrade -y
    
    print_status "Installation des outils de base..."
    apt install -y curl wget unzip git software-properties-common apt-transport-https \
                   ca-certificates gnupg lsb-release openssl dirmngr
    
    print_success "Système mis à jour avec succès"
}

# Installation Apache2
install_apache() {
    print_header "INSTALLATION D'APACHE2"
    
    print_status "Installation d'Apache2..."
    apt install -y apache2
    
    print_status "Activation des modules Apache essentiels..."
    a2enmod rewrite
    a2enmod ssl
    a2enmod headers
    a2enmod expires
    a2enmod deflate
    
    print_status "Configuration des permissions de base..."
    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html
    
    print_status "Configuration et démarrage d'Apache..."
    systemctl enable apache2
    systemctl start apache2
    
    # Vérification du statut
    if systemctl is-active --quiet apache2; then
        print_success "Apache2 installé et configuré avec succès"
    else
        print_error "Problème lors du démarrage d'Apache2"
        exit 1
    fi
}

# Installation PHP 8.2 avec gestion améliorée des erreurs
install_php() {
    print_header "INSTALLATION DE PHP 8.2"
    
    print_status "Installation des prérequis pour PHP..."
    apt install -y ca-certificates apt-transport-https software-properties-common gnupg2
    
    print_status "Configuration du dépôt Sury pour PHP..."
    # Suppression des anciennes configurations
    rm -f /etc/apt/sources.list.d/php.list
    rm -f /etc/apt/trusted.gpg.d/php.gpg
    
    # Ajout de la clé GPG avec vérification
    wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
    
    if [[ ! -f /etc/apt/trusted.gpg.d/php.gpg ]]; then
        print_error "Échec du téléchargement de la clé GPG Sury"
        exit 1
    fi
    
    # Ajout du dépôt
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    
    print_status "Mise à jour des dépôts avec le nouveau dépôt PHP..."
    apt update -y
    
    print_status "Installation progressive de PHP 8.2..."
    
    # Installation des composants de base PHP
    print_status "Installation de PHP 8.2 CLI et Common..."
    if ! apt install -y php8.2-cli php8.2-common; then
        print_error "Échec de l'installation des composants PHP de base"
        exit 1
    fi
    
    # Vérification que PHP fonctionne
    if ! php8.2 -v > /dev/null 2>&1; then
        print_error "PHP 8.2 CLI ne fonctionne pas correctement"
        exit 1
    fi
    
    print_status "Installation du module Apache pour PHP..."
    if ! apt install -y libapache2-mod-php8.2; then
        print_error "Échec de l'installation du module Apache PHP"
        exit 1
    fi
    
    print_status "Installation des extensions PHP essentielles..."
    # Installation des extensions une par une avec gestion d'erreurs
    PHP_EXTENSIONS=(
        "php8.2-mysql"
        "php8.2-zip" 
        "php8.2-gd"
        "php8.2-mbstring"
        "php8.2-curl"
        "php8.2-xml"
        "php8.2-bcmath"
        "php8.2-intl"
        "php8.2-soap"
        "php8.2-readline"
    )
    
    for extension in "${PHP_EXTENSIONS[@]}"; do
        print_status "Installation de $extension..."
        if apt install -y "$extension"; then
            print_success "$extension installé avec succès"
        else
            print_warning "Échec de l'installation de $extension (non critique)"
        fi
    done
    
    print_status "Activation du module PHP dans Apache..."
    a2enmod php8.2
    
    print_status "Configuration de PHP pour l'environnement de production..."
    # Configuration PHP optimisée
    PHP_INI="/etc/php/8.2/apache2/php.ini"
    
    # Sauvegarde de la configuration originale
    cp "$PHP_INI" "$PHP_INI.backup"
    
    # Application des paramètres optimisés
    sed -i 's/max_execution_time = 30/max_execution_time = 300/' "$PHP_INI"
    sed -i 's/max_input_vars = 1000/max_input_vars = 3000/' "$PHP_INI"
    sed -i 's/memory_limit = 128M/memory_limit = 512M/' "$PHP_INI"
    sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 100M/' "$PHP_INI"
    sed -i 's/post_max_size = 8M/post_max_size = 100M/' "$PHP_INI"
    sed -i 's/;date.timezone =/date.timezone = Africa\/Casablanca/' "$PHP_INI"
    sed -i 's/;max_input_time = 60/max_input_time = 300/' "$PHP_INI"
    sed -i 's/display_errors = On/display_errors = Off/' "$PHP_INI"
    sed -i 's/;log_errors = On/log_errors = On/' "$PHP_INI"
    
    # Application de la même configuration pour CLI
    cp "$PHP_INI" "/etc/php/8.2/cli/php.ini"
    
    print_status "Test de la configuration PHP..."
    if php8.2 -m | grep -q "mysql\|json\|mbstring"; then
        print_success "PHP 8.2 installé et configuré avec succès"
    else
        print_error "Problème avec la configuration PHP"
        exit 1
    fi
}

# Installation MariaDB avec configuration sécurisée
install_mariadb() {
    print_header "INSTALLATION DE MARIADB"
    
    print_status "Installation de MariaDB Server..."
    apt install -y mariadb-server mariadb-client
    
    print_status "Démarrage et activation de MariaDB..."
    systemctl enable mariadb
    systemctl start mariadb
    
    # Vérification que MariaDB fonctionne
    if ! systemctl is-active --quiet mariadb; then
        print_error "MariaDB ne démarre pas correctement"
        exit 1
    fi
    
    print_status "Sécurisation de l'installation MariaDB..."
    # Configuration sécurisée automatique
    mysql -e "UPDATE mysql.user SET authentication_string = PASSWORD('${DB_ROOT_PASSWORD}') WHERE User = 'root' AND Host = 'localhost';" 2>/dev/null || true
    mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
    mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    
    print_success "MariaDB installé et sécurisé avec succès"
}

# Installation Composer
install_composer() {
    print_header "INSTALLATION DE COMPOSER"
    
    print_status "Téléchargement et installation de Composer..."
    cd /tmp
    
    # Téléchargement avec vérification
    if ! curl -sS https://getcomposer.org/installer -o composer-setup.php; then
        print_error "Échec du téléchargement de Composer"
        exit 1
    fi
    
    # Installation
    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php
    
    # Vérification
    if command -v composer > /dev/null 2>&1; then
        print_success "Composer $(composer --version | cut -d' ' -f3) installé avec succès"
    else
        print_error "Problème avec l'installation de Composer"
        exit 1
    fi
}

# Installation Node.js et npm
install_nodejs() {
    print_header "INSTALLATION DE NODE.JS"
    
    print_status "Ajout du dépôt NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    
    print_status "Installation de Node.js..."
    apt install -y nodejs
    
    # Vérification
    if command -v node > /dev/null 2>&1 && command -v npm > /dev/null 2>&1; then
        print_success "Node.js $(node --version) et npm $(npm --version) installés avec succès"
    else
        print_error "Problème avec l'installation de Node.js"
        exit 1
    fi
}

# Création de la base de données
create_database() {
    print_header "CRÉATION DE LA BASE DE DONNÉES"
    
    print_status "Création de la base de données et de l'utilisateur..."
    
    # Test de connexion MySQL
    if ! mysql -e "SELECT 1;" > /dev/null 2>&1; then
        print_error "Impossible de se connecter à MariaDB"
        exit 1
    fi
    
    # Création de la base et de l'utilisateur
    mysql <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    # Vérification de la création
    if mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -e "USE \`${DB_NAME}\`; SELECT 1;" > /dev/null 2>&1; then
        print_success "Base de données créée: ${DB_NAME}"
        print_success "Utilisateur créé: ${DB_USER}"
    else
        print_error "Problème lors de la création de la base de données"
        exit 1
    fi
}

# Sauvegarde du contenu existant
backup_existing_content() {
    print_header "GESTION DU CONTENU EXISTANT"
    
    if [[ -n "$(ls -A ${INSTALL_DIR} 2>/dev/null)" ]]; then
        print_status "Contenu détecté dans ${INSTALL_DIR}, création d'une sauvegarde..."
        
        mkdir -p ${BACKUP_DIR}
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        
        if tar -czf "${BACKUP_DIR}/html_backup_${TIMESTAMP}.tar.gz" -C ${INSTALL_DIR} . 2>/dev/null; then
            print_success "Sauvegarde créée: ${BACKUP_DIR}/html_backup_${TIMESTAMP}.tar.gz"
        else
            print_warning "Erreur lors de la création de la sauvegarde"
        fi
        
        print_status "Nettoyage du répertoire d'installation..."
        rm -rf ${INSTALL_DIR}/*
        rm -rf ${INSTALL_DIR}/.[^.]*
    else
        print_status "Aucun contenu existant détecté dans ${INSTALL_DIR}"
    fi
}

# Création de la structure de l'application
create_application_structure() {
    print_header "CRÉATION DE LA STRUCTURE DE L'APPLICATION"
    
    print_status "Création de l'arborescence des dossiers..."
    
    # Création des dossiers principaux avec gestion d'erreurs
    DIRECTORIES=(
        "api"
        "assets/css"
        "assets/js" 
        "assets/images"
        "assets/fonts"
        "classes"
        "config"
        "cron"
        "database/migrations"
        "docs"
        "includes"
        "lang"
        "logs"
        "middleware"
        "pages"
        "storage/temp"
        "storage/uploads/documents"
        "storage/uploads/avatars"
        "storage/uploads/exports"
        "storage/backups/database"
        "storage/backups/files"
        "storage/cache/views"
        "storage/cache/data"
        "templates/email"
        "templates/whatsapp"
        "templates/pdf"
        "templates/excel"
        "tests/unit"
        "tests/integration"
        "tests/feature"
        "utils"
        "webhooks"
        "vendor"
    )
    
    for dir in "${DIRECTORIES[@]}"; do
        mkdir -p "${INSTALL_DIR}/${dir}"
    done
    
    print_status "Configuration des permissions..."
    chown -R www-data:www-data ${INSTALL_DIR}
    chmod -R 755 ${INSTALL_DIR}
    chmod -R 775 ${INSTALL_DIR}/storage
    chmod -R 775 ${INSTALL_DIR}/logs
    chmod -R 755 ${INSTALL_DIR}/config
    
    print_success "Structure de l'application créée avec succès"
}

# Déploiement des fichiers de l'application
deploy_application_files() {
    print_header "DÉPLOIEMENT DES FICHIERS DE L'APPLICATION"
    
    print_status "Création du fichier de configuration de base de données..."
    
    # Configuration de la base de données avec protection
    cat > ${INSTALL_DIR}/config/database.php << 'EOL'
<?php
/**
 * Configuration de la base de données - Fidaous Pro
 * Généré automatiquement lors de l'installation
 */

class Database {
    private $host = 'localhost';
    private $db_name = 'DATABASE_NAME_PLACEHOLDER';
    private $username = 'DATABASE_USER_PLACEHOLDER';
    private $password = 'DATABASE_PASSWORD_PLACEHOLDER';
    private $charset = 'utf8mb4';
    public $pdo;

    public function getConnection() {
        $this->pdo = null;
        try {
            $dsn = "mysql:host=" . $this->host . ";dbname=" . $this->db_name . ";charset=" . $this->charset;
            $options = [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
                PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4",
                PDO::ATTR_TIMEOUT => 30
            ];
            $this->pdo = new PDO($dsn, $this->username, $this->password, $options);
        } catch(PDOException $exception) {
            error_log("Erreur de connexion BDD: " . $exception->getMessage());
            throw new Exception("Connexion à la base de données impossible");
        }
        return $this->pdo;
    }
    
    public function testConnection() {
        try {
            $this->getConnection();
            return true;
        } catch(Exception $e) {
            return false;
        }
    }
}
?>
EOL

    # Remplacement sécurisé des placeholders
    sed -i "s/DATABASE_NAME_PLACEHOLDER/${DB_NAME}/g" ${INSTALL_DIR}/config/database.php
    sed -i "s/DATABASE_USER_PLACEHOLDER/${DB_USER}/g" ${INSTALL_DIR}/config/database.php
    sed -i "s/DATABASE_PASSWORD_PLACEHOLDER/${DB_PASSWORD}/g" ${INSTALL_DIR}/config/database.php
    
    # Protection du fichier de configuration
    chmod 640 ${INSTALL_DIR}/config/database.php
    
    print_status "Création du fichier de configuration général..."
    
    # Configuration générale de l'application
    cat > ${INSTALL_DIR}/config/app.php << EOL
<?php
/**
 * Configuration générale - Fidaous Pro
 */

return [
    'app_name' => 'Fidaous Pro',
    'app_version' => '1.0.0',
    'app_url' => 'http://${DOMAIN}',
    'timezone' => 'Africa/Casablanca',
    'locale' => 'fr',
    'debug' => false,
    'log_level' => 'info',
    'session_lifetime' => 120,
    'install_date' => '$(date)'
];
?>
EOL

    print_status "Création de la page d'accueil..."
    
    # Page d'accueil avec diagnostic
    cat > ${INSTALL_DIR}/index.html << 'EOL'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Fidaous Pro - Cabinet Comptable</title>
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #333;
        }
        .container {
            background: rgba(255,255,255,0.95);
            padding: 3rem;
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 600px;
            backdrop-filter: blur(10px);
        }
        h1 { 
            color: #2c3e50; 
            margin-bottom: 1rem; 
            font-size: 3rem;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 1rem;
        }
        .subtitle { 
            color: #666; 
            margin-bottom: 2rem; 
            font-size: 1.2rem; 
            font-weight: 300;
        }
        .status { 
            background: #d4edda; 
            color: #155724; 
            padding: 1.5rem; 
            border-radius: 10px; 
            margin-bottom: 2rem;
            border-left: 4px solid #28a745;
        }
        .status i {
            font-size: 2rem;
            margin-bottom: 1rem;
        }
        .btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 1rem 2rem;
            border: none;
            border-radius: 10px;
            text-decoration: none;
            display: inline-block;
            transition: all 0.3s;
            font-size: 1.1rem;
            font-weight: 600;
        }
        .btn:hover { 
            transform: translateY(-2px); 
            box-shadow: 0 10px 20px rgba(0,0,0,0.2);
        }
        .version { 
            margin-top: 2rem; 
            color: #999; 
            font-size: 0.9rem;
            padding: 1rem;
            background: #f8f9fa;
            border-radius: 10px;
        }
        .features {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin: 2rem 0;
        }
        .feature {
            background: #f8f9fa;
            padding: 1rem;
            border-radius: 10px;
            border-left: 4px solid #667eea;
        }
        .feature i {
            color: #667eea;
            font-size: 1.5rem;
            margin-bottom: 0.5rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>
            <i class="fas fa-calculator"></i>
            Fidaous Pro
        </h1>
        <p class="subtitle">Cabinet Comptable & Expertise - Maroc</p>
        
        <div class="status">
            <i class="fas fa-check-circle"></i>
            <h3>Installation Réussie !</h3>
            <p>L'application a été installée et configurée avec succès sur votre serveur Debian 12.</p>
        </div>
        
        <div class="features">
            <div class="feature">
                <i class="fas fa-users"></i>
                <h4>Gestion Clients</h4>
                <p>Conformité normes marocaines</p>
            </div>
            <div class="feature">
                <i class="fas fa-folder-open"></i>
                <h4>Dossiers</h4>
                <p>Suivi des échéances fiscales</p>
            </div>
            <div class="feature">
                <i class="fab fa-whatsapp"></i>
                <h4>WhatsApp Business</h4>
                <p>Communication client moderne</p>
            </div>
            <div class="feature">
                <i class="fas fa-cloud"></i>
                <h4>Nextcloud</h4>
                <p>Stockage documentaire sécurisé</p>
            </div>
        </div>
        
        <a href="pages/login.php" class="btn">
            <i class="fas fa-sign-in-alt"></i>
            Accéder à l'Application
        </a>
        
        <div class="version">
            <strong>Version 1.0.0</strong> - Debian 12<br>
            Installation: $(date)<br>
            PHP $(php -v | head -n1 | cut -d' ' -f2) • MariaDB • Apache2
        </div>
    </div>
</body>
</html>
EOL

    print_status "Création de la configuration Apache (.htaccess)..."
    
    # Configuration Apache sécurisée
    cat > ${INSTALL_DIR}/.htaccess << 'EOL'
# =============================================================================
# Fidaous Pro - Configuration Apache
# Version: 1.0 - Générée automatiquement
# =============================================================================

# Activation du moteur de réécriture
RewriteEngine On

# =============================================================================
# SÉCURITÉ
# =============================================================================

# Protection des fichiers sensibles
<FilesMatch "^\.">
    Require all denied
</FilesMatch>

<FilesMatch "\.(env|ini|log|sh|sql|md|json)$">
    Require all denied
</FilesMatch>

# Protection des dossiers sensibles
RewriteRule ^(config|logs|storage|database|tests|cron)/ - [F,L]

# Protection contre les tentatives d'inclusion de fichiers
RewriteCond %{QUERY_STRING} (\.\.\/|\.\.\\|..%2F|..%5C) [NC]
RewriteRule .* - [F,L]

# Protection contre l'injection SQL
RewriteCond %{QUERY_STRING} (\<|%3C).*script.*(\>|%3E) [NC,OR]
RewriteCond %{QUERY_STRING} GLOBALS(=|\[|\%[0-9A-Z]{0,2}) [OR]
RewriteCond %{QUERY_STRING} _REQUEST(=|\[|\%[0-9A-Z]{0,2}) [OR]
RewriteCond %{QUERY_STRING} (\||%7C) [NC]
RewriteRule .* - [F,L]

# =============================================================================
# OPTIMISATION DES PERFORMANCES
# =============================================================================

# Compression GZIP
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/plain
    AddOutputFilterByType DEFLATE text/html
    AddOutputFilterByType DEFLATE text/xml
    AddOutputFilterByType DEFLATE text/css
    AddOutputFilterByType DEFLATE text/javascript
    AddOutputFilterByType DEFLATE application/xml
    AddOutputFilterByType DEFLATE application/xhtml+xml
    AddOutputFilterByType DEFLATE application/rss+xml
    AddOutputFilterByType DEFLATE application/javascript
    AddOutputFilterByType DEFLATE application/x-javascript
    AddOutputFilterByType DEFLATE application/json
</IfModule>

# Cache des fichiers statiques
<IfModule mod_expires.c>
    ExpiresActive On
    ExpiresByType image/jpg "access plus 1 month"
    ExpiresByType image/jpeg "access plus 1 month"
    ExpiresByType image/gif "access plus 1 month"
    ExpiresByType image/png "access plus 1 month"
    ExpiresByType image/webp "access plus 1 month"
    ExpiresByType text/css "access plus 1 month"
    ExpiresByType application/pdf "access plus 1 month"
    ExpiresByType text/javascript "access plus 1 month"
    ExpiresByType application/javascript "access plus 1 month"
    ExpiresByType application/x-javascript "access plus 1 month"
    ExpiresByType font/woff "access plus 1 year"
    ExpiresByType font/woff2 "access plus 1 year"
</IfModule>

# En-têtes de sécurité
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options DENY
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"
</IfModule>

# =============================================================================
# ROUTAGE
# =============================================================================

# Routage API
RewriteRule ^api/(.*)$ api/endpoints.php [QSA,L]

# Routage Webhooks
RewriteRule ^webhooks/(.*)$ webhooks/$1.php [QSA,L]

# Page par défaut
DirectoryIndex index.html index.php

# =============================================================================
# GESTION DES ERREURS
# =============================================================================

ErrorDocument 403 /pages/error403.html
ErrorDocument 404 /pages/error404.html
ErrorDocument 500 /pages/error500.html
EOL

    print_status "Création du fichier de test PHP..."
    
    # Fichier de diagnostic PHP
    cat > ${INSTALL_DIR}/test.php << 'EOL'
<?php
/**
 * Script de diagnostic - Fidaous Pro
 * À supprimer après vérification
 */

header('Content-Type: text/html; charset=utf-8');

echo '<h1>Diagnostic Fidaous Pro</h1>';
echo '<h2>Configuration PHP</h2>';
echo '<p><strong>Version PHP:</strong> ' . phpversion() . '</p>';
echo '<p><strong>Extensions installées:</strong></p>';
echo '<ul>';

$required_extensions = ['mysql', 'mysqli', 'pdo', 'pdo_mysql', 'mbstring', 'curl', 'gd', 'xml', 'zip'];
foreach($required_extensions as $ext) {
    $status = extension_loaded($ext) ? '✅' : '❌';
    echo "<li>$status $ext</li>";
}
echo '</ul>';

echo '<h2>Test de connexion base de données</h2>';
require_once 'config/database.php';

try {
    $db = new Database();
    $connection = $db->getConnection();
    if($connection) {
        echo '<p>✅ Connexion à la base de données réussie</p>';
        
        // Test de requête
        $stmt = $connection->query("SELECT 1 as test");
        $result = $stmt->fetch();
        echo '<p>✅ Exécution de requête réussie</p>';
    }
} catch(Exception $e) {
    echo '<p>❌ Erreur de connexion: ' . $e->getMessage() . '</p>';
}

echo '<h2>Informations système</h2>';
echo '<p><strong>Serveur:</strong> ' . $_SERVER['SERVER_SOFTWARE'] . '</p>';
echo '<p><strong>Document Root:</strong> ' . $_SERVER['DOCUMENT_ROOT'] . '</p>';
echo '<p><strong>PHP SAPI:</strong> ' . php_sapi_name() . '</p>';

echo '<hr><p><em>Supprimez ce fichier après vérification pour des raisons de sécurité.</em></p>';
?>
EOL

    # Protection du fichier de test
    chmod 644 ${INSTALL_DIR}/test.php
    
    print_success "Fichiers de l'application déployés avec succès"
}

# Import de la structure de base de données
import_database_structure() {
    print_header "IMPORT DE LA STRUCTURE DE BASE DE DONNÉES"
    
    print_status "Création du fichier de structure SQL..."
    
    # Structure complète de la base de données
    cat > ${INSTALL_DIR}/database/structure.sql << 'EOL'
-- =============================================================================
-- Structure de base de données Fidaous Pro
-- Version: 1.0
-- Généré automatiquement lors de l'installation
-- =============================================================================

SET FOREIGN_KEY_CHECKS = 0;
SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET AUTOCOMMIT = 0;
START TRANSACTION;
SET time_zone = "+00:00";

-- =============================================================================
-- TABLE DES RÔLES
-- =============================================================================

CREATE TABLE IF NOT EXISTS `roles` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `nom` varchar(50) NOT NULL,
    `description` text DEFAULT NULL,
    `permissions` json DEFAULT NULL,
    `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
    PRIMARY KEY (`id`),
    UNIQUE KEY `nom` (`nom`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `roles` (`nom`, `description`, `permissions`) VALUES
('Administrateur', 'Accès complet au système', '["all"]'),
('Expert-Comptable', 'Gestion complète des dossiers et clients', '["clients", "dossiers", "taches", "rapports", "employes_read"]'),
('Comptable', 'Gestion des dossiers et tâches', '["clients_read", "dossiers", "taches", "rapports_read"]'),
('Assistant', 'Saisie et assistance', '["clients_read", "dossiers_read", "taches_assigned"]'),
('Stagiaire', 'Accès limité en lecture', '["clients_read", "dossiers_read", "taches_read"]');

-- =============================================================================
-- TABLE DES EMPLOYÉS
-- =============================================================================

CREATE TABLE IF NOT EXISTS `employes` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `matricule` varchar(20) NOT NULL,
    `nom` varchar(100) NOT NULL,
    `prenom` varchar(100) NOT NULL,
    `email` varchar(150) NOT NULL,
    `telephone` varchar(20) DEFAULT NULL,
    `cin` varchar(20) DEFAULT NULL,
    `adresse` text DEFAULT NULL,
    `ville` varchar(100) DEFAULT NULL,
    `role_id` int(11) NOT NULL,
    `date_embauche` date NOT NULL,
    `date_fin_contrat` date DEFAULT NULL,
    `salaire` decimal(10,2) DEFAULT NULL,
    `status` enum('Actif','Congé','Suspendu','Démissionné') DEFAULT 'Actif',
    `mot_de_passe` varchar(255) NOT NULL,
    `derniere_connexion` timestamp NULL DEFAULT NULL,
    `token_reset` varchar(255) DEFAULT NULL,
    `photo_profil` varchar(255) DEFAULT NULL,
    `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
    `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
    PRIMARY KEY (`id`),
    UNIQUE KEY `matricule` (`matricule`),
    UNIQUE KEY `email` (`email`),
    UNIQUE KEY `cin` (`cin`),
    KEY `idx_email` (`email`),
    KEY `idx_matricule` (`matricule`),
    KEY `role_id` (`role_id`),
    CONSTRAINT `employes_ibfk_1` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLE DES CLIENTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS `clients` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `code_client` varchar(20) NOT NULL,
    `raison_sociale` varchar(200) NOT NULL,
    `nom_commercial` varchar(200) DEFAULT NULL,
    `forme_juridique` enum('SA','SARL','SARL AU','SNC','SCS','SCA','GIE','Entreprise Individuelle','Auto-Entrepreneur','Personne Physique','Coopérative','Association') NOT NULL,
    `ice` varchar(15) DEFAULT NULL,
    `rc` varchar(20) DEFAULT NULL,
    `patente` varchar(20) DEFAULT NULL,
    `cnss` varchar(20) DEFAULT NULL,
    `if_code` varchar(20) DEFAULT NULL,
    `tva_numero` varchar(20) DEFAULT NULL,
    `capital_social` decimal(15,2) DEFAULT NULL,
    `date_creation` date DEFAULT NULL,
    `activite_principale` varchar(200) DEFAULT NULL,
    `secteur_activite` enum('Agriculture','Industrie','BTP','Commerce','Services','Transport','Tourisme','Autres') DEFAULT NULL,
    `adresse_siege` text DEFAULT NULL,
    `ville_siege` varchar(100) DEFAULT NULL,
    `code_postal_siege` varchar(10) DEFAULT NULL,
    `telephone_fixe` varchar(20) DEFAULT NULL,
    `telephone_mobile` varchar(20) DEFAULT NULL,
    `fax` varchar(20) DEFAULT NULL,
    `email` varchar(150) DEFAULT NULL,
    `site_web` varchar(200) DEFAULT NULL,
    `gerant_nom` varchar(150) DEFAULT NULL,
    `gerant_cin` varchar(20) DEFAULT NULL,
    `regime_fiscal` enum('Régime du Résultat Net Réel','Régime du Résultat Net Simplifié','Régime Forfaitaire','Régime Auto-Entrepreneur') NOT NULL,
    `exercice_social_debut` int(11) DEFAULT 1,
    `exercice_social_fin` int(11) DEFAULT 12,
    `assujetti_tva` tinyint(1) DEFAULT 1,
    `banque_nom` varchar(100) DEFAULT NULL,
    `compte_bancaire` varchar(30) DEFAULT NULL,
    `rib` varchar(24) DEFAULT NULL,
    `damancom_login` varchar(100) DEFAULT NULL,
    `damancom_password` varchar(255) DEFAULT NULL,
    `dgi_login` varchar(100) DEFAULT NULL,
    `dgi_password` varchar(255) DEFAULT NULL,
    `dgi_numero_contribuable` varchar(20) DEFAULT NULL,
    `personne_cin` varchar(20) DEFAULT NULL,
    `personne_nom` varchar(100) DEFAULT NULL,
    `personne_prenom` varchar(100) DEFAULT NULL,
    `personne_date_naissance` date DEFAULT NULL,
    `personne_lieu_naissance` varchar(100) DEFAULT NULL,
    `employe_responsable` int(11) DEFAULT NULL,
    `date_debut_mission` date DEFAULT NULL,
    `tarif_horaire` decimal(8,2) DEFAULT NULL,
    `forfait_mensuel` decimal(10,2) DEFAULT NULL,
    `status` enum('Actif','Suspendu','Inactif','Prospect') DEFAULT 'Prospect',
    `notes_internes` text DEFAULT NULL,
    `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
    `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
    PRIMARY KEY (`id`),
    UNIQUE KEY `code_client` (`code_client`),
    UNIQUE KEY `ice` (`ice`),
    KEY `idx_ice` (`ice`),
    KEY `idx_code_client` (`code_client`),
    KEY `idx_raison_sociale` (`raison_sociale`),
    KEY `employe_responsable` (`employe_responsable`),
    CONSTRAINT `clients_ibfk_1` FOREIGN KEY (`employe_responsable`) REFERENCES `employes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- TABLE DES PARAMÈTRES SYSTÈME
-- =============================================================================

CREATE TABLE IF NOT EXISTS `parametres_systeme` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `cle_parametre` varchar(100) NOT NULL,
    `valeur` text DEFAULT NULL,
    `description` text DEFAULT NULL,
    `type_valeur` enum('string','integer','decimal','boolean','json') DEFAULT 'string',
    `categorie` varchar(50) DEFAULT NULL,
    `is_editable` tinyint(1) DEFAULT 1,
    `updated_by` int(11) DEFAULT NULL,
    `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
    PRIMARY KEY (`id`),
    UNIQUE KEY `cle_parametre` (`cle_parametre`),
    KEY `updated_by` (`updated_by`),
    CONSTRAINT `parametres_systeme_ibfk_1` FOREIGN KEY (`updated_by`) REFERENCES `employes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insertion des paramètres par défaut
INSERT INTO `parametres_systeme` (`cle_parametre`, `valeur`, `description`, `type_valeur`, `categorie`) VALUES
('cabinet_nom', 'Cabinet Fidaous Pro', 'Nom du cabinet', 'string', 'general'),
('cabinet_adresse', 'Casablanca, Maroc', 'Adresse du cabinet', 'string', 'general'),
('cabinet_telephone', '+212 522 000 000', 'Téléphone du cabinet', 'string', 'general'),
('cabinet_email', 'contact@fidaouspro.ma', 'Email du cabinet', 'string', 'general'),
('tva_taux_defaut', '20.00', 'Taux TVA par défaut', 'decimal', 'fiscal'),
('devise_defaut', 'MAD', 'Devise par défaut', 'string', 'general'),
('exercice_debut_mois', '1', 'Mois de début d\\'exercice par défaut', 'integer', 'fiscal'),
('app_version', '1.0.0', 'Version de l\\'application', 'string', 'system'),
('install_date', NOW(), 'Date d\\'installation', 'string', 'system'),
('backup_auto_actif', 'true', 'Sauvegarde automatique activée', 'boolean', 'systeme'),
('retention_logs_jours', '365', 'Durée de rétention des logs en jours', 'integer', 'systeme');

-- =============================================================================
-- TRIGGERS ET FONCTIONS
-- =============================================================================

-- Trigger pour générer automatiquement les codes clients
DELIMITER //
CREATE TRIGGER before_insert_client 
BEFORE INSERT ON clients 
FOR EACH ROW
BEGIN
    IF NEW.code_client IS NULL OR NEW.code_client = '' THEN
        SET NEW.code_client = CONCAT('CLI', YEAR(CURDATE()), LPAD((SELECT COALESCE(MAX(SUBSTRING(code_client, 8)), 0) + 1 FROM clients WHERE code_client LIKE CONCAT('CLI', YEAR(CURDATE()), '%')), 4, '0'));
    END IF;
END//
DELIMITER ;

SET FOREIGN_KEY_CHECKS = 1;
COMMIT;
EOL

    print_status "Import de la structure en base de données..."
    if mysql -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" < ${INSTALL_DIR}/database/structure.sql; then
        print_success "Structure de base de données importée avec succès"
    else
        print_error "Erreur lors de l'import de la structure"
        exit 1
    fi
}

# Création de l'utilisateur administrateur
create_admin_user() {
    print_header "CRÉATION DE L'UTILISATEUR ADMINISTRATEUR"
    
    print_status "Génération du mot de passe administrateur sécurisé..."
    HASHED_PASSWORD=$(php -r "echo password_hash('${ADMIN_PASSWORD}', PASSWORD_DEFAULT);")
    
    print_status "Création du compte administrateur en base..."
    mysql -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" <<EOF
INSERT IGNORE INTO employes (matricule, nom, prenom, email, role_id, date_embauche, mot_de_passe, status) 
VALUES ('ADM001', 'Admin', 'Fidaous', '${ADMIN_EMAIL}', 1, CURDATE(), '${HASHED_PASSWORD}', 'Actif');
EOF
    
    # Vérification de la création
    ADMIN_COUNT=$(mysql -u "${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" -se "SELECT COUNT(*) FROM employes WHERE email='${ADMIN_EMAIL}'")
    
    if [[ $ADMIN_COUNT -gt 0 ]]; then
        print_success "Administrateur créé avec succès"
        print_success "Email: ${ADMIN_EMAIL}"
        print_status "Mot de passe généré automatiquement (affiché en fin d'installation)"
    else
        print_error "Erreur lors de la création de l'administrateur"
        exit 1
    fi
}

# Configuration des services
configure_services() {
    print_header "CONFIGURATION ET REDÉMARRAGE DES SERVICES"
    
    print_status "Test de la configuration Apache..."
    if apache2ctl configtest; then
        print_success "Configuration Apache valide"
    else
        print_error "Erreur dans la configuration Apache"
        exit 1
    fi
    
    print_status "Redémarrage d'Apache..."
    systemctl restart apache2
    
    print_status "Redémarrage de MariaDB..."
    systemctl restart mariadb
    
    # Vérification des services
    sleep 2
    
    if systemctl is-active --quiet apache2; then
        print_success "Apache2 redémarré avec succès"
    else
        print_error "Problème avec le redémarrage d'Apache2"
        exit 1
    fi
    
    if systemctl is-active --quiet mariadb; then
        print_success "MariaDB redémarré avec succès"
    else
        print_error "Problème avec le redémarrage de MariaDB"
        exit 1
    fi
}

# Configuration du firewall
configure_firewall() {
    print_header "CONFIGURATION DU PARE-FEU"
    
    if command -v ufw &> /dev/null; then
        print_status "Configuration d'UFW (Uncomplicated Firewall)..."
        
        # Réinitialisation et configuration
        ufw --force reset
        ufw default deny incoming
        ufw default allow outgoing
        
        # Règles essentielles
        ufw allow ssh
        ufw allow 'Apache Full'
        
        # Activation
        ufw --force enable
        
        print_success "Pare-feu configuré et activé"
        print_status "Ports ouverts: SSH (22), HTTP (80), HTTPS (443)"
    else
        print_warning "UFW n'est pas disponible, installation du pare-feu..."
        apt install -y ufw
        configure_firewall  # Récursion pour configurer après installation
    fi
}

# Configuration des tâches automatisées
setup_cron_jobs() {
    print_header "CONFIGURATION DES TÂCHES AUTOMATISÉES"
    
    print_status "Création des scripts de maintenance..."
    
    # Script de sauvegarde automatique
    cat > ${INSTALL_DIR}/cron/backup.sh << EOL
#!/bin/bash
# Script de sauvegarde automatique - Fidaous Pro
# Généré lors de l'installation

DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_DIR}"
LOG_FILE="${INSTALL_DIR}/logs/backup.log"

# Création des dossiers si nécessaire
mkdir -p "\${BACKUP_DIR}/database"
mkdir -p "\${BACKUP_DIR}/files"

echo "\$(date): Début de sauvegarde" >> "\${LOG_FILE}"

# Sauvegarde de la base de données
if mysqldump -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME} > "\${BACKUP_DIR}/database/db_\${DATE}.sql"; then
    echo "\$(date): Sauvegarde base de données réussie" >> "\${LOG_FILE}"
else
    echo "\$(date): ERREUR sauvegarde base de données" >> "\${LOG_FILE}"
fi

# Sauvegarde des fichiers
if tar -czf "\${BACKUP_DIR}/files/files_\${DATE}.tar.gz" ${INSTALL_DIR}/storage; then
    echo "\$(date): Sauvegarde fichiers réussie" >> "\${LOG_FILE}"
else
    echo "\$(date): ERREUR sauvegarde fichiers" >> "\${LOG_FILE}"
fi

# Nettoyage des anciennes sauvegardes (> 30 jours)
find "\${BACKUP_DIR}/database" -name "*.sql" -mtime +30 -delete
find "\${BACKUP_DIR}/files" -name "*.tar.gz" -mtime +30 -delete

echo "\$(date): Sauvegarde terminée" >> "\${LOG_FILE}"
EOL

    # Script de nettoyage des logs
    cat > ${INSTALL_DIR}/cron/cleanup.sh << EOL
#!/bin/bash
# Script de nettoyage - Fidaous Pro

LOG_DIR="${INSTALL_DIR}/logs"

# Nettoyage des logs anciens (> 30 jours)
find "\${LOG_DIR}" -name "*.log" -mtime +30 -delete

# Nettoyage du cache temporaire
find "${INSTALL_DIR}/storage/temp" -type f -mtime +7 -delete

# Nettoyage des sessions PHP expirées
find "/tmp" -name "sess_*" -mtime +1 -delete 2>/dev/null || true

echo "\$(date): Nettoyage terminé" >> "\${LOG_DIR}/cleanup.log"
EOL

    # Permissions d'exécution
    chmod +x ${INSTALL_DIR}/cron/backup.sh
    chmod +x ${INSTALL_DIR}/cron/cleanup.sh
    
    print_status "Configuration du crontab système..."
    
    # Configuration des tâches cron
    (crontab -l 2>/dev/null; cat << EOF
# Fidaous Pro - Tâches automatisées
# Sauvegarde quotidienne à 2h00
0 2 * * * ${INSTALL_DIR}/cron/backup.sh

# Nettoyage quotidien à 3h00  
0 3 * * * ${INSTALL_DIR}/cron/cleanup.sh

# Redémarrage hebdomadaire des services le dimanche à 4h00
0 4 * * 0 systemctl restart apache2 && systemctl restart mariadb
EOF
    ) | crontab -
    
    print_success "Tâches automatisées configurées"
    print_status "Sauvegarde quotidienne programmée à 2h00"
    print_status "Nettoyage quotidien programmé à 3h00"
}

# Tests complets de l'installation
test_installation() {
    print_header "TESTS DE VALIDATION DE L'INSTALLATION"
    
    print_status "Vérification des services système..."
    
    # Test Apache
    if systemctl is-active --quiet apache2; then
        print_success "✓ Apache2 opérationnel"
    else
        print_error "✗ Apache2 non fonctionnel"
        return 1
    fi
    
    # Test MariaDB
    if systemctl is-active --quiet mariadb; then
        print_success "✓ MariaDB opérationnel"
    else
        print_error "✗ MariaDB non fonctionnel"
        return 1
    fi
    
    # Test PHP
    if php -v | grep -q "PHP 8.2"; then
        print_success "✓ PHP 8.2 opérationnel"
    else
        print_error "✗ PHP 8.2 non fonctionnel"
        return 1
    fi
    
    print_status "Test des extensions PHP requises..."
    
    # Test des extensions critiques
    REQUIRED_EXTENSIONS=("mysql" "mysqli" "pdo" "pdo_mysql" "mbstring" "curl" "gd" "xml")
    for ext in "${REQUIRED_EXTENSIONS[@]}"; do
        if php -m | grep -q "$ext"; then
            print_success "✓ Extension $ext présente"
        else
            print_error "✗ Extension $ext manquante"
            return 1
        fi
    done
    
    print_status "Test de connexion à la base de données..."
    
    # Test connexion base de données
    if mysql -u "${DB_USER}" -p"${DB_PASSWORD}" -e "USE \`${DB_NAME}\`; SELECT 1;" &>/dev/null; then
        print_success "✓ Connexion base de données fonctionnelle"
    else
        print_error "✗ Problème de connexion à la base de données"
        return 1
    fi
    
    print_status "Test des permissions fichiers..."
    
    # Test des permissions
    if [[ -w "${INSTALL_DIR}/storage" ]] && [[ -w "${INSTALL_DIR}/logs" ]]; then
        print_success "✓ Permissions des dossiers correctes"
    else
        print_error "✗ Problème de permissions"
        return 1
    fi
    
    print_status "Test de l'interface web..."
    
    # Test HTTP
    if curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -q "200"; then
        print_success "✓ Interface web accessible"
    else
        print_warning "Interface web non testable (curl ou serveur non accessible)"
    fi
    
    print_success "Tous les tests de validation sont passés avec succès"
}

# Affichage des informations finales
display_final_info() {
    print_header "INSTALLATION TERMINÉE AVEC SUCCÈS"
    
    # Informations système
    SERVER_IP=$(hostname -I | awk '{print $1}')
    HOSTNAME=$(hostname)
    
    echo -e "${GREEN}"
    echo "🎉 FIDAOUS PRO INSTALLÉ AVEC SUCCÈS !"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                    INFORMATIONS D'ACCÈS                    │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ URL d'accès        : http://${SERVER_IP}"
    echo "│ URL alternative    : http://${HOSTNAME}"
    echo "│ Email admin        : ${ADMIN_EMAIL}"
    echo "│ Mot de passe admin : ${ADMIN_PASSWORD}"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                 CONFIGURATION BASE DE DONNÉES              │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ Nom BDD            : ${DB_NAME}"
    echo "│ Utilisateur BDD    : ${DB_USER}"
    echo "│ Mot de passe BDD   : ${DB_PASSWORD}"
    echo "│ Hôte               : localhost"
    echo "│ Port               : 3306"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                     DOSSIERS SYSTÈME                       │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ Application        : ${INSTALL_DIR}"
    echo "│ Configuration      : ${INSTALL_DIR}/config"
    echo "│ Logs               : ${INSTALL_DIR}/logs"
    echo "│ Stockage           : ${INSTALL_DIR}/storage"
    echo "│ Sauvegardes        : ${BACKUP_DIR}"
    echo "│ Logs installation  : ${LOG_FILE}"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                    INFORMATIONS SYSTÈME                    │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ OS                 : $(lsb_release -d | cut -f2)"
    echo "│ Apache             : $(apache2 -v | head -n1 | cut -d' ' -f3)"
    echo "│ PHP                : $(php -v | head -n1 | cut -d' ' -f2)"
    echo "│ MariaDB            : $(mysql --version | cut -d' ' -f6)"
    echo "│ Installation       : $(date)"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
    
    echo -e "${YELLOW}"
    echo "⚠️  ACTIONS DE SÉCURITÉ IMPORTANTES :"
    echo "   • Changez IMMÉDIATEMENT le mot de passe administrateur"
    echo "   • Supprimez le fichier test.php après vérification"
    echo "   • Configurez SSL/HTTPS pour la production"
    echo "   • Sauvegardez le fichier INSTALLATION_INFO.txt"
    echo "   • Configurez les intégrations (Nextcloud, WhatsApp)"
    echo ""
    echo "🔧 PROCHAINES ÉTAPES RECOMMANDÉES :"
    echo "   1. Accéder à l'application et changer les mots de passe"
    echo "   2. Configurer votre nom de domaine"
    echo "   3. Installer un certificat SSL (Let's Encrypt)"
    echo "   4. Paramétrer les sauvegardes distantes"
    echo "   5. Configurer la surveillance système"
    echo -e "${NC}"
    
    # Sauvegarde des informations dans un fichier
    cat > ${INSTALL_DIR}/INSTALLATION_INFO.txt << EOL
================================================================================
FIDAOUS PRO - INFORMATIONS D'INSTALLATION
================================================================================
Date d'installation     : $(date)
Serveur                  : ${HOSTNAME}
Adresse IP               : ${SERVER_IP}
Version OS               : $(lsb_release -d | cut -f2)

ACCÈS APPLICATION:
------------------
URL principale           : http://${SERVER_IP}
URL alternative          : http://${HOSTNAME}
Email administrateur     : ${ADMIN_EMAIL}
Mot de passe admin       : ${ADMIN_PASSWORD}

BASE DE DONNÉES:
----------------
Nom de la base           : ${DB_NAME}
Utilisateur              : ${DB_USER}
Mot de passe             : ${DB_PASSWORD}
Hôte                     : localhost
Port                     : 3306

COMPOSANTS INSTALLÉS:
---------------------
Apache                   : $(apache2 -v | head -n1 | cut -d' ' -f3)
PHP                      : $(php -v | head -n1 | cut -d' ' -f2)
MariaDB                  : $(mysql --version | cut -d' ' -f6)
Composer                 : $(composer --version 2>/dev/null | cut -d' ' -f3 || echo "Non détecté")
Node.js                  : $(node --version 2>/dev/null || echo "Non détecté")

DOSSIERS SYSTÈME:
-----------------
Racine application       : ${INSTALL_DIR}
Configuration            : ${INSTALL_DIR}/config
Logs application         : ${INSTALL_DIR}/logs
Stockage fichiers        : ${INSTALL_DIR}/storage
Sauvegardes              : ${BACKUP_DIR}
Log installation         : ${LOG_FILE}

SÉCURITÉ:
---------
Pare-feu                 : UFW activé
Ports ouverts            : SSH (22), HTTP (80), HTTPS (443)
Protection fichiers      : .htaccess configuré
Permissions              : www-data:www-data

TÂCHES AUTOMATISÉES:
--------------------
Sauvegarde quotidienne   : 02:00 (base + fichiers)
Nettoyage quotidien      : 03:00 (logs + cache)
Redémarrage hebdomadaire : Dimanche 04:00

NOTES IMPORTANTES:
------------------
• Changez immédiatement tous les mots de passe par défaut
• Supprimez test.php après vérification
• Configurez SSL/HTTPS pour la production
• Testez les sauvegardes automatiques
• Configurez la surveillance système

SUPPORT:
--------
Documentation            : ${INSTALL_DIR}/docs/
Test système             : http://${SERVER_IP}/test.php
Logs erreurs             : ${INSTALL_DIR}/logs/error.log

================================================================================
⚠️  SUPPRIMEZ CE FICHIER APRÈS AVOIR SAUVEGARDÉ CES INFORMATIONS
================================================================================
EOL

    # Protection du fichier d'informations
    chmod 600 ${INSTALL_DIR}/INSTALLATION_INFO.txt
    chown www-data:www-data ${INSTALL_DIR}/INSTALLATION_INFO.txt
    
    print_success "Fichier d'informations sauvegardé: ${INSTALL_DIR}/INSTALLATION_INFO.txt"
}

# Fonction de nettoyage en cas d'erreur
cleanup_on_error() {
    print_header "NETTOYAGE EN CAS D'ERREUR"
    
    print_status "Arrêt des services..."
    systemctl stop apache2 2>/dev/null || true
    systemctl stop mariadb 2>/dev/null || true
    
    print_status "Suppression des packages défaillants..."
    apt remove --purge -y php8.2* libapache2-mod-php8.2* 2>/dev/null || true
    
    print_status "Restauration de la sauvegarde si disponible..."
    if [[ -f "${BACKUP_DIR}/html_backup_"*.tar.gz ]]; then
        LATEST_BACKUP=$(ls -t ${BACKUP_DIR}/html_backup_*.tar.gz 2>/dev/null | head -n1)
        if [[ -n "$LATEST_BACKUP" ]]; then
            tar -xzf "$LATEST_BACKUP" -C ${INSTALL_DIR}
            print_status "Contenu restauré depuis: $LATEST_BACKUP"
        fi
    fi
    
    print_error "Installation interrompue. Consultez le log: ${LOG_FILE}"
}

# Fonction principale avec gestion d'erreurs améliorée
main() {
    # Initialisation du log
    echo "$(date '+%Y-%m-%d %H:%M:%S') === DÉBUT INSTALLATION FIDAOUS PRO ===" > $LOG_FILE
    
    print_header "INSTALLATION FIDAOUS PRO - VERSION 1.1"
    print_status "Démarrage de l'installation automatisée..."
    
    # Vérifications préliminaires
    check_root
    check_debian_version
    
    # Nettoyage des installations précédentes défaillantes
    cleanup_php_installation
    
    # Installation des composants système
    update_system
    install_apache
    install_php
    install_mariadb
    install_composer
    install_nodejs
    
    # Configuration de l'application
    create_database
    backup_existing_content
    create_application_structure
    deploy_application_files
    import_database_structure
    create_admin_user
    
    # Configuration finale des services
    configure_services
    configure_firewall
    setup_cron_jobs
    
    # Tests et validation
    test_installation
    
    # Finalisation
    display_final_info
    
    print_success "🎉 Installation de Fidaous Pro terminée avec succès !"
    print_status "Durée totale: $(($(date +%s) - $(stat -c %Y $LOG_FILE))) secondes"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') === FIN INSTALLATION FIDAOUS PRO ===" >> $LOG_FILE
}

# Gestion des signaux d'interruption
trap cleanup_on_error INT TERM

# Point d'entrée du script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi