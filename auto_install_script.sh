#!/bin/bash

# =============================================================================
# Script d'Installation Automatisée - Fidaous Pro
# Version: 1.0
# Système: Debian 12 (Bookworm)
# Base de données: MariaDB
# Serveur Web: Apache2 + PHP 8.2
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

# Fonctions utilitaires
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "  $1"
    echo "=============================================================="
    echo -e "${NC}"
}

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
                   ca-certificates gnupg lsb-release openssl
    
    print_success "Système mis à jour avec succès"
}

# Installation Apache2
install_apache() {
    print_header "INSTALLATION D'APACHE2"
    
    print_status "Installation d'Apache2..."
    apt install -y apache2
    
    print_status "Activation des modules Apache..."
    a2enmod rewrite
    a2enmod ssl
    a2enmod headers
    a2enmod expires
    
    print_status "Configuration des permissions..."
    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html
    
    systemctl enable apache2
    systemctl start apache2
    
    print_success "Apache2 installé et configuré"
}

# Installation PHP 8.2
install_php() {
    print_header "INSTALLATION DE PHP 8.2"
    
    print_status "Ajout du dépôt Sury pour PHP..."
    wget -qO /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    
    print_status "Mise à jour des dépôts..."
    apt update -y
    
    print_status "Installation de PHP 8.2 et modules requis..."
    # Note: php8.2-json est intégré dans php8.2-common depuis PHP 8.0
    apt install -y php8.2 php8.2-cli php8.2-common php8.2-mysql php8.2-zip \
                   php8.2-gd php8.2-mbstring php8.2-curl php8.2-xml \
                   php8.2-bcmath php8.2-intl php8.2-soap php8.2-readline \
                   php8.2-ldap php8.2-msgpack php8.2-igbinary php8.2-redis \
                   php8.2-memcached php8.2-pcov php8.2-xdebug \
                   libapache2-mod-php8.2
    
    print_status "Configuration de PHP..."
    # Configuration PHP pour production
    sed -i 's/;max_execution_time = 30/max_execution_time = 300/' /etc/php/8.2/apache2/php.ini
    sed -i 's/;max_input_vars = 1000/max_input_vars = 3000/' /etc/php/8.2/apache2/php.ini
    sed -i 's/memory_limit = 128M/memory_limit = 512M/' /etc/php/8.2/apache2/php.ini
    sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 100M/' /etc/php/8.2/apache2/php.ini
    sed -i 's/post_max_size = 8M/post_max_size = 100M/' /etc/php/8.2/apache2/php.ini
    sed -i 's/;date.timezone =/date.timezone = Africa\/Casablanca/' /etc/php/8.2/apache2/php.ini
    
    # Même configuration pour CLI
    cp /etc/php/8.2/apache2/php.ini /etc/php/8.2/cli/php.ini
    
    print_success "PHP 8.2 installé et configuré"
}

# Installation MariaDB
install_mariadb() {
    print_header "INSTALLATION DE MARIADB"
    
    print_status "Installation de MariaDB Server..."
    apt install -y mariadb-server mariadb-client
    
    print_status "Démarrage et activation de MariaDB..."
    systemctl enable mariadb
    systemctl start mariadb
    
    print_status "Sécurisation de MariaDB..."
    # Configuration automatique de la sécurité
    mysql -e "UPDATE mysql.user SET Password = PASSWORD('${DB_ROOT_PASSWORD}') WHERE User = 'root'"
    mysql -e "DROP USER IF EXISTS ''@'localhost'"
    mysql -e "DROP USER IF EXISTS ''@'$(hostname)'"
    mysql -e "DROP DATABASE IF EXISTS test"
    mysql -e "FLUSH PRIVILEGES"
    
    print_success "MariaDB installé et sécurisé"
}

# Installation Composer
install_composer() {
    print_header "INSTALLATION DE COMPOSER"
    
    print_status "Téléchargement et installation de Composer..."
    cd /tmp
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
    
    print_success "Composer installé"
}

# Installation Node.js et npm
install_nodejs() {
    print_header "INSTALLATION DE NODE.JS"
    
    print_status "Ajout du dépôt NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    
    print_status "Installation de Node.js..."
    apt install -y nodejs
    
    print_success "Node.js $(node --version) et npm $(npm --version) installés"
}

# Création de la base de données
create_database() {
    print_header "CRÉATION DE LA BASE DE DONNÉES"
    
    print_status "Création de la base de données et de l'utilisateur..."
    
    mysql <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    print_success "Base de données créée: ${DB_NAME}"
    print_success "Utilisateur créé: ${DB_USER}"
}

# Sauvegarde du contenu existant
backup_existing_content() {
    print_header "SAUVEGARDE DU CONTENU EXISTANT"
    
    if [[ -n "$(ls -A ${INSTALL_DIR} 2>/dev/null)" ]]; then
        print_status "Contenu détecté dans ${INSTALL_DIR}, création d'une sauvegarde..."
        
        mkdir -p ${BACKUP_DIR}
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        tar -czf "${BACKUP_DIR}/html_backup_${TIMESTAMP}.tar.gz" -C ${INSTALL_DIR} . 2>/dev/null || true
        
        print_status "Nettoyage du répertoire d'installation..."
        rm -rf ${INSTALL_DIR}/*
        rm -rf ${INSTALL_DIR}/.[^.]*
        
        print_success "Sauvegarde créée: ${BACKUP_DIR}/html_backup_${TIMESTAMP}.tar.gz"
    else
        print_status "Aucun contenu existant détecté"
    fi
}

# Création de la structure de l'application
create_application_structure() {
    print_header "CRÉATION DE LA STRUCTURE DE L'APPLICATION"
    
    print_status "Création de l'arborescence des dossiers..."
    
    # Création des dossiers principaux
    mkdir -p ${INSTALL_DIR}/{api,assets/{css,js,images,fonts},classes,config,cron,database/{migrations},docs,includes,lang,logs,middleware,pages,storage/{temp,uploads/{documents,avatars,exports},backups/{database,files},cache/{views,data}},templates/{email,whatsapp,pdf,excel},tests/{unit,integration,feature},utils,webhooks,vendor}
    
    # Permissions appropriées
    chown -R www-data:www-data ${INSTALL_DIR}
    chmod -R 755 ${INSTALL_DIR}
    chmod -R 775 ${INSTALL_DIR}/storage
    chmod -R 775 ${INSTALL_DIR}/logs
    
    print_success "Structure de l'application créée"
}

# Déploiement des fichiers de l'application
deploy_application_files() {
    print_header "DÉPLOIEMENT DES FICHIERS DE L'APPLICATION"
    
    print_status "Création du fichier de configuration principal..."
    
    # Fichier de configuration de la base de données
    cat > ${INSTALL_DIR}/config/database.php << 'EOL'
<?php
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
                PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4"
            ];
            $this->pdo = new PDO($dsn, $this->username, $this->password, $options);
        } catch(PDOException $exception) {
            error_log("Erreur de connexion: " . $exception->getMessage());
            throw $exception;
        }
        return $this->pdo;
    }
}
?>
EOL

    # Remplacement des placeholders
    sed -i "s/DATABASE_NAME_PLACEHOLDER/${DB_NAME}/g" ${INSTALL_DIR}/config/database.php
    sed -i "s/DATABASE_USER_PLACEHOLDER/${DB_USER}/g" ${INSTALL_DIR}/config/database.php
    sed -i "s/DATABASE_PASSWORD_PLACEHOLDER/${DB_PASSWORD}/g" ${INSTALL_DIR}/config/database.php
    
    # Fichier de configuration général
    cat > ${INSTALL_DIR}/config/app.php << EOL
<?php
return [
    'app_name' => 'Fidaous Pro',
    'app_version' => '1.0.0',
    'app_url' => 'http://${DOMAIN}',
    'timezone' => 'Africa/Casablanca',
    'locale' => 'fr',
    'debug' => false,
    'log_level' => 'info'
];
?>
EOL

    # Page d'accueil principale
    cat > ${INSTALL_DIR}/index.html << 'EOL'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Fidaous Pro - Cabinet Comptable</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: rgba(255,255,255,0.95);
            padding: 3rem;
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 500px;
        }
        h1 { color: #2c3e50; margin-bottom: 1rem; font-size: 2.5rem; }
        p { color: #666; margin-bottom: 2rem; font-size: 1.1rem; }
        .status { background: #d4edda; color: #155724; padding: 1rem; border-radius: 10px; margin-bottom: 2rem; }
        .btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 1rem 2rem;
            border: none;
            border-radius: 10px;
            text-decoration: none;
            display: inline-block;
            transition: transform 0.3s;
        }
        .btn:hover { transform: translateY(-2px); }
        .version { margin-top: 2rem; color: #999; font-size: 0.9rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🏢 Fidaous Pro</h1>
        <p>Cabinet Comptable & Expertise - Maroc</p>
        <div class="status">
            ✅ Installation réussie !
        </div>
        <p>L'application a été installée avec succès sur votre serveur.</p>
        <a href="/pages/login.php" class="btn">Accéder à l'application</a>
        <div class="version">Version 1.0.0 - Debian 12</div>
    </div>
</body>
</html>
EOL

    # Configuration Apache
    cat > ${INSTALL_DIR}/.htaccess << 'EOL'
# Fidaous Pro - Configuration Apache
RewriteEngine On

# Sécurité - Masquer les fichiers sensibles
<Files ~ "^\.">
    Order allow,deny
    Deny from all
</Files>

<FilesMatch "\.(env|ini|log|sh|sql)$">
    Order allow,deny
    Deny from all
</FilesMatch>

# Protection des dossiers sensibles
RedirectMatch 403 ^/config/
RedirectMatch 403 ^/logs/
RedirectMatch 403 ^/storage/

# Compression GZIP
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/plain
    AddOutputFilterByType DEFLATE text/html
    AddOutputFilterByType DEFLATE text/xml
    AddOutputFilterByType DEFLATE text/css
    AddOutputFilterByType DEFLATE application/xml
    AddOutputFilterByType DEFLATE application/xhtml+xml
    AddOutputFilterByType DEFLATE application/rss+xml
    AddOutputFilterByType DEFLATE application/javascript
    AddOutputFilterByType DEFLATE application/x-javascript
</IfModule>

# Cache des fichiers statiques
<IfModule mod_expires.c>
    ExpiresActive On
    ExpiresByType image/jpg "access plus 1 month"
    ExpiresByType image/jpeg "access plus 1 month"
    ExpiresByType image/gif "access plus 1 month"
    ExpiresByType image/png "access plus 1 month"
    ExpiresByType text/css "access plus 1 month"
    ExpiresByType application/pdf "access plus 1 month"
    ExpiresByType text/javascript "access plus 1 month"
    ExpiresByType application/javascript "access plus 1 month"
</IfModule>

# API Routes
RewriteRule ^api/(.*)$ api/endpoints.php [QSA,L]

# Webhook Routes  
RewriteRule ^webhooks/(.*)$ webhooks/$1.php [QSA,L]

# Page par défaut
DirectoryIndex index.html index.php
EOL

    print_success "Fichiers de l'application déployés"
}

# Import de la structure de base de données
import_database_structure() {
    print_header "IMPORT DE LA STRUCTURE DE BASE DE DONNÉES"
    
    print_status "Création du fichier SQL de structure..."
    
    # Création du fichier SQL avec la structure complète
    cat > ${INSTALL_DIR}/database/structure.sql << 'EOL'
-- Structure de base de données Fidaous Pro
SET FOREIGN_KEY_CHECKS = 0;

-- Table des rôles
CREATE TABLE IF NOT EXISTS roles (
    id INT PRIMARY KEY AUTO_INCREMENT,
    nom VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    permissions JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table des employés
CREATE TABLE IF NOT EXISTS employes (
    id INT PRIMARY KEY AUTO_INCREMENT,
    matricule VARCHAR(20) UNIQUE NOT NULL,
    nom VARCHAR(100) NOT NULL,
    prenom VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    telephone VARCHAR(20),
    cin VARCHAR(20) UNIQUE,
    role_id INT NOT NULL,
    date_embauche DATE NOT NULL,
    salaire DECIMAL(10,2),
    status ENUM('Actif', 'Inactif') DEFAULT 'Actif',
    mot_de_passe VARCHAR(255) NOT NULL,
    derniere_connexion TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (role_id) REFERENCES roles(id),
    INDEX idx_email (email),
    INDEX idx_matricule (matricule)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table des clients
CREATE TABLE IF NOT EXISTS clients (
    id INT PRIMARY KEY AUTO_INCREMENT,
    code_client VARCHAR(20) UNIQUE NOT NULL,
    raison_sociale VARCHAR(200) NOT NULL,
    forme_juridique ENUM('SA', 'SARL', 'SARL AU', 'SNC', 'Entreprise Individuelle', 'Auto-Entrepreneur', 'Personne Physique') NOT NULL,
    ice VARCHAR(15) UNIQUE,
    rc VARCHAR(20),
    patente VARCHAR(20),
    cnss VARCHAR(20),
    regime_fiscal ENUM('Régime du Résultat Net Réel', 'Régime du Résultat Net Simplifié', 'Régime Forfaitaire', 'Régime Auto-Entrepreneur') NOT NULL,
    telephone_fixe VARCHAR(20),
    telephone_mobile VARCHAR(20),
    email VARCHAR(150),
    adresse_siege TEXT,
    ville_siege VARCHAR(100),
    employe_responsable INT,
    status ENUM('Actif', 'Suspendu', 'Inactif') DEFAULT 'Actif',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (employe_responsable) REFERENCES employes(id),
    INDEX idx_ice (ice),
    INDEX idx_code_client (code_client)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table des paramètres système
CREATE TABLE IF NOT EXISTS parametres_systeme (
    id INT PRIMARY KEY AUTO_INCREMENT,
    cle_parametre VARCHAR(100) UNIQUE NOT NULL,
    valeur TEXT,
    description TEXT,
    categorie VARCHAR(50),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Données initiales
INSERT IGNORE INTO roles (nom, description, permissions) VALUES
('Administrateur', 'Accès complet au système', '["all"]'),
('Expert-Comptable', 'Gestion complète des dossiers et clients', '["clients", "dossiers", "taches", "rapports"]'),
('Comptable', 'Gestion des dossiers et tâches', '["clients_read", "dossiers", "taches"]'),
('Assistant', 'Saisie et assistance', '["clients_read", "dossiers_read", "taches_assigned"]');

INSERT IGNORE INTO parametres_systeme (cle_parametre, valeur, description, categorie) VALUES
('cabinet_nom', 'Cabinet Fidaous Pro', 'Nom du cabinet', 'general'),
('cabinet_adresse', 'Casablanca, Maroc', 'Adresse du cabinet', 'general'),
('cabinet_telephone', '+212 522 000 000', 'Téléphone du cabinet', 'general'),
('cabinet_email', 'contact@fidaouspro.ma', 'Email du cabinet', 'general'),
('app_version', '1.0.0', 'Version de l\'application', 'system'),
('install_date', NOW(), 'Date d\'installation', 'system');

SET FOREIGN_KEY_CHECKS = 1;
EOL

    print_status "Import de la structure en base de données..."
    mysql -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME} < ${INSTALL_DIR}/database/structure.sql
    
    print_success "Structure de base de données importée"
}

# Création de l'utilisateur administrateur
create_admin_user() {
    print_header "CRÉATION DE L'UTILISATEUR ADMINISTRATEUR"
    
    print_status "Création du compte administrateur..."
    
    HASHED_PASSWORD=$(php -r "echo password_hash('${ADMIN_PASSWORD}', PASSWORD_DEFAULT);")
    
    mysql -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME} <<EOF
INSERT IGNORE INTO employes (matricule, nom, prenom, email, role_id, date_embauche, mot_de_passe) 
VALUES ('ADM001', 'Admin', 'Fidaous', '${ADMIN_EMAIL}', 1, CURDATE(), '${HASHED_PASSWORD}');
EOF
    
    print_success "Administrateur créé - Email: ${ADMIN_EMAIL}"
}

# Configuration des services
configure_services() {
    print_header "CONFIGURATION DES SERVICES"
    
    print_status "Redémarrage d'Apache..."
    systemctl restart apache2
    
    print_status "Redémarrage de MariaDB..."
    systemctl restart mariadb
    
    print_status "Activation du site par défaut..."
    a2ensite 000-default
    
    print_status "Test de la configuration Apache..."
    apache2ctl configtest
    
    print_success "Services configurés et redémarrés"
}

# Configuration du firewall
configure_firewall() {
    print_header "CONFIGURATION DU PARE-FEU"
    
    if command -v ufw &> /dev/null; then
        print_status "Configuration d'UFW..."
        ufw --force enable
        ufw allow ssh
        ufw allow 'Apache Full'
        ufw allow 3306  # MariaDB (pour administration distante si nécessaire)
        print_success "Pare-feu configuré"
    else
        print_warning "UFW n'est pas installé, configuration du pare-feu ignorée"
    fi
}

# Création des tâches cron
setup_cron_jobs() {
    print_header "CONFIGURATION DES TÂCHES AUTOMATISÉES"
    
    print_status "Création du script de sauvegarde..."
    cat > ${INSTALL_DIR}/cron/backup.sh << EOL
#!/bin/bash
DATE=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_DIR}"

# Sauvegarde base de données
mysqldump -u ${DB_USER} -p${DB_PASSWORD} ${DB_NAME} > \${BACKUP_DIR}/database/db_\${DATE}.sql

# Sauvegarde fichiers
tar -czf \${BACKUP_DIR}/files/files_\${DATE}.tar.gz ${INSTALL_DIR}/storage

# Nettoyage des anciennes sauvegardes (> 30 jours)
find \${BACKUP_DIR} -name "*.sql" -mtime +30 -delete
find \${BACKUP_DIR} -name "*.tar.gz" -mtime +30 -delete

echo "Sauvegarde terminée: \${DATE}" >> ${INSTALL_DIR}/logs/backup.log
EOL

    chmod +x ${INSTALL_DIR}/cron/backup.sh
    
    print_status "Configuration du crontab..."
    # Sauvegarde quotidienne à 2h00
    (crontab -l 2>/dev/null; echo "0 2 * * * ${INSTALL_DIR}/cron/backup.sh") | crontab -
    
    print_success "Tâches automatisées configurées"
}

# Test de l'installation
test_installation() {
    print_header "TEST DE L'INSTALLATION"
    
    print_status "Vérification des services..."
    
    # Test Apache
    if systemctl is-active --quiet apache2; then
        print_success "Apache2 fonctionne correctement"
    else
        print_error "Problème avec Apache2"
        return 1
    fi
    
    # Test MariaDB
    if systemctl is-active --quiet mariadb; then
        print_success "MariaDB fonctionne correctement"
    else
        print_error "Problème avec MariaDB"
        return 1
    fi
    
    # Test PHP
    if php -v | grep -q "PHP 8.2"; then
        print_success "PHP 8.2 fonctionne correctement"
    else
        print_error "Problème avec PHP"
        return 1
    fi
    
    # Test connexion base de données
    if mysql -u ${DB_USER} -p${DB_PASSWORD} -e "USE ${DB_NAME}; SELECT 1;" &>/dev/null; then
        print_success "Connexion à la base de données OK"
    else
        print_error "Problème de connexion à la base de données"
        return 1
    fi
    
    print_success "Tous les tests sont passés avec succès"
}

# Affichage des informations finales
display_final_info() {
    print_header "INSTALLATION TERMINÉE"
    
    echo -e "${GREEN}"
    echo "🎉 Fidaous Pro a été installé avec succès !"
    echo ""
    echo "📋 INFORMATIONS DE CONNEXION:"
    echo "   URL d'accès: http://$(hostname -I | awk '{print $1}')"
    echo "   Email admin: ${ADMIN_EMAIL}"
    echo "   Mot de passe: ${ADMIN_PASSWORD}"
    echo ""
    echo "🗄️  BASE DE DONNÉES:"
    echo "   Nom: ${DB_NAME}"
    echo "   Utilisateur: ${DB_USER}"
    echo "   Mot de passe: ${DB_PASSWORD}"
    echo ""
    echo "📁 DOSSIERS IMPORTANTS:"
    echo "   Application: ${INSTALL_DIR}"
    echo "   Logs: ${INSTALL_DIR}/logs"
    echo "   Sauvegardes: ${BACKUP_DIR}"
    echo ""
    echo "⚠️  SÉCURITÉ:"
    echo "   Changez immédiatement le mot de passe administrateur"
    echo "   Configurez SSL/HTTPS pour la production"
    echo "   Vérifiez les permissions des fichiers"
    echo ""
    echo "🔧 PROCHAINES ÉTAPES:"
    echo "   1. Configurer votre nom de domaine"
    echo "   2. Installer un certificat SSL"
    echo "   3. Configurer les sauvegardes automatiques"
    echo "   4. Paramétrer les intégrations (Nextcloud, WhatsApp)"
    echo -e "${NC}"
    
    # Sauvegarde des informations dans un fichier
    cat > ${INSTALL_DIR}/INSTALLATION_INFO.txt << EOL
FIDAOUS PRO - INFORMATIONS D'INSTALLATION
==========================================
Date d'installation: $(date)
Serveur: $(hostname)
IP: $(hostname -I | awk '{print $1}')

ACCÈS APPLICATION:
- URL: http://$(hostname -I | awk '{print $1}')
- Email admin: ${ADMIN_EMAIL}
- Mot de passe admin: ${ADMIN_PASSWORD}

BASE DE DONNÉES:
- Nom: ${DB_NAME}
- Utilisateur: ${DB_USER}
- Mot de passe: ${DB_PASSWORD}

DOSSIERS:
- Application: ${INSTALL_DIR}
- Logs: ${INSTALL_DIR}/logs
- Sauvegardes: ${BACKUP_DIR}

SERVICES:
- Apache2: Port 80
- MariaDB: Port 3306
- PHP: Version 8.2

SÉCURITÉ:
Changez immédiatement les mots de passe par défaut !
EOL

    chmod 600 ${INSTALL_DIR}/INSTALLATION_INFO.txt
}

# Fonction principale
main() {
    print_header "INSTALLATION FIDAOUS PRO - DÉMARRAGE"
    
    # Vérifications préliminaires
    check_root
    check_debian_version
    
    # Installation des composants
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
    
    # Configuration finale
    configure_services
    configure_firewall
    setup_cron_jobs
    
    # Tests et finalisation
    test_installation
    display_final_info
    
    print_success "Installation terminée avec succès !"
}

# Point d'entrée du script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi