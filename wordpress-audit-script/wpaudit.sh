#!/bin/bash
#======================================================
#   WORDPRESS SECURITY & COMPLIANCE AUDIT (DOCKER)   
#   Enhanced Version with Advanced Features
#======================================================
# Author: Abdullah Siraj
# Date: 2026-02-10
# Version: 2.0
# Standards: CIS Linux, CIS Apache/Nginx, OWASP WP Top 10
#======================================================

# ---------------- COLORS ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'
# ----------------------------------------

set -o pipefail

# ---------------- CONFIG -----------------
# Default container names
WP_CONTAINER="wordpress_csro"
DB_CONTAINER="mysql_csro"

# WordPress paths inside container
WP_PATH="/var/www/html"
WP_CONFIG="$WP_PATH/wp-config.php"
WEB_USER="www-data"
WEB_GROUP="www-data"

# Counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
INFO_COUNT=0

# Output options
GENERATE_REPORT=0
REPORT_FORMAT="txt"  # txt, html, json
REPORT_DIR="/tmp/wp-audit-$(date +%Y%m%d-%H%M%S)"
VERBOSE=0
AUTO_FIX=0
SEND_EMAIL=0
EMAIL_TO=""

# Malware scanning
SCAN_FOR_MALWARE=0
SUSPICIOUS_FILES=()
# ----------------------------------------

# ---------------- HELP -------------------
show_help() {
    cat << EOF
${BOLD}WordPress Security & Compliance Audit Script (Docker Enhanced)${NC}

${BOLD}USAGE:${NC}
    $0 [OPTIONS]

${BOLD}OPTIONS:${NC}
    -w, --wp-container NAME  WordPress container name (default: wordpress_csro)
    -d, --db-container NAME  Database container name (default: mysql_csro)
    -p, --path PATH          WordPress path inside container (default: /var/www/html)
    -r, --report FORMAT      Generate report (txt|html|json)
    -v, --verbose            Verbose output
    -f, --auto-fix           Attempt automatic fixes (USE WITH CAUTION)
    -m, --malware-scan       Perform malware pattern scanning
    -e, --email EMAIL        Send report to email address
    -u, --user USER          Web server user (default: www-data)
    -g, --group GROUP        Web server group (default: www-data)
    -h, --help               Show this help message

${BOLD}EXAMPLES:${NC}
    $0                                          # Basic audit with default containers
    $0 -w my_wp -d my_db                       # Audit with custom container names
    $0 -r html                                  # Audit with HTML report
    $0 -m -r json                               # Audit with malware scan and JSON report
    $0 -v -r html -e admin@example.com         # Verbose with HTML report via email

${BOLD}SECURITY WARNING:${NC}
    Auto-fix (-f) will modify your WordPress installation.
    Always backup before using this option!

${BOLD}DOCKER REQUIREMENTS:${NC}
    - Docker daemon must be running
    - WP-CLI should be installed in WordPress container for enhanced checks
    - Script must have permissions to execute docker commands

EOF
    exit 0
}
# ----------------------------------------

# ---------------- PARSE ARGS -------------
while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--wp-container)
            WP_CONTAINER="$2"
            shift 2
            ;;
        -d|--db-container)
            DB_CONTAINER="$2"
            shift 2
            ;;
        -p|--path)
            WP_PATH="$2"
            WP_CONFIG="$WP_PATH/wp-config.php"
            shift 2
            ;;
        -r|--report)
            GENERATE_REPORT=1
            REPORT_FORMAT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -f|--auto-fix)
            AUTO_FIX=1
            shift
            ;;
        -m|--malware-scan)
            SCAN_FOR_MALWARE=1
            shift
            ;;
        -e|--email)
            SEND_EMAIL=1
            EMAIL_TO="$2"
            shift 2
            ;;
        -u|--user)
            WEB_USER="$2"
            shift 2
            ;;
        -g|--group)
            WEB_GROUP="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done
# ----------------------------------------

# ---------------- INIT REPORT ------------
if [[ $GENERATE_REPORT -eq 1 ]]; then
    mkdir -p "$REPORT_DIR"
    REPORT_FILE="$REPORT_DIR/wp-security-audit.$REPORT_FORMAT"
fi
# ----------------------------------------

#======================
# Check Docker container exists and is running
#======================
check_container() {
    local CONTAINER="$1"
    if [[ -z "$CONTAINER" ]]; then
        return 1
    fi
    if ! docker ps --format '{{.Names}}' | grep -qw "$CONTAINER"; then
        return 1
    fi
    return 0
}

#======================
# Run command inside WP container
#======================
run_wp() {
    if ! check_container "$WP_CONTAINER"; then
        return 1
    fi
    docker exec "$WP_CONTAINER" bash -c "$1" 2>/dev/null
}

#======================
# Run command inside DB container
#======================
run_db() {
    if ! check_container "$DB_CONTAINER"; then
        return 1
    fi
    docker exec "$DB_CONTAINER" bash -c "$1" 2>/dev/null
}

# =====================================================
# OUTPUT HANDLER
# =====================================================
log_result() {
    local status=$1
    local ref=$2
    local msg=$3
    local fix=$4

    # Console output
    case "$status" in
        PASS)
            echo -e "[ ${GREEN}PASS${NC} ] [$ref] $msg"
            ((PASS_COUNT++))
            ;;
        WARN)
            echo -e "[ ${YELLOW}WARN${NC} ] [$ref] $msg"
            ((WARN_COUNT++))
            [[ -n "$fix" ]] && echo -e "         ${YELLOW}└──${NC} Fix: $fix"
            ;;
        INFO)
            echo -e "[ ${BLUE}INFO${NC} ] [$ref] $msg"
            ((INFO_COUNT++))
            ;;
        FAIL)
            echo -e "[ ${RED}FAIL${NC} ] [$ref] $msg"
            ((FAIL_COUNT++))
            [[ -n "$fix" ]] && echo -e "         ${RED}└──${NC} Fix: $fix"
            ;;
    esac

    # Append to report if enabled
    if [[ $GENERATE_REPORT -eq 1 ]]; then
        case "$REPORT_FORMAT" in
            json)
                echo "{\"status\":\"$status\",\"ref\":\"$ref\",\"message\":\"$msg\",\"fix\":\"$fix\"}," >> "$REPORT_FILE"
                ;;
            html)
                echo "<tr class='$status'><td>$status</td><td>$ref</td><td>$msg</td><td>$fix</td></tr>" >> "$REPORT_FILE"
                ;;
            *)
                echo "[$status] [$ref] $msg $(if [[ -n "$fix" ]]; then echo "| Fix: $fix"; fi)" >> "$REPORT_FILE"
                ;;
        esac
    fi
}

# =====================================================
# AUTO-FIX FUNCTIONS
# =====================================================
auto_fix_permissions() {
    local path=$1
    local perms=$2
    
    if [[ $AUTO_FIX -eq 1 ]]; then
        run_wp "chmod $perms $path" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_result INFO "AUTO-FIX" "Fixed permissions on $path to $perms"
            return 0
        else
            log_result WARN "AUTO-FIX" "Failed to fix permissions on $path"
            return 1
        fi
    fi
    return 1
}

auto_fix_ownership() {
    local path=$1
    local owner=$2
    local group=$3
    
    if [[ $AUTO_FIX -eq 1 ]]; then
        run_wp "chown $owner:$group $path" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_result INFO "AUTO-FIX" "Fixed ownership on $path to $owner:$group"
            return 0
        else
            log_result WARN "AUTO-FIX" "Failed to fix ownership on $path"
            return 1
        fi
    fi
    return 1
}

# =====================================================
# FILE PERMISSIONS CHECK
# =====================================================
check_perms() {
    local path=$1
    local expected=$2
    local ref=$3

    local actual=$(run_wp "stat -c '%a' $path 2>/dev/null")
    if [[ -n "$actual" ]]; then
        if [[ "$actual" -le "$expected" ]]; then
            log_result PASS "$ref" "$path perms $actual"
        else
            log_result FAIL "$ref" "$path perms $actual (expected $expected)" "chmod $expected $path"
            auto_fix_permissions "$path" "$expected"
        fi
    else
        log_result INFO "$ref" "$path not found"
    fi
}

#======================
# Print header
#======================
clear
echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}   WORDPRESS SECURITY & COMPLIANCE AUDIT (DOCKER)   ${NC}"
echo -e "${CYAN}                    Enhanced Version                  ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo "Host: $(hostname)"
echo "Date: $(date)"
echo "WP Container: ${WP_CONTAINER}"
echo "DB Container: ${DB_CONTAINER}"
echo "WP Path (in container): $WP_PATH"
echo "Web User: $WEB_USER:$WEB_GROUP"
[[ $AUTO_FIX -eq 1 ]] && echo -e "${YELLOW}Auto-fix: ENABLED${NC}"
[[ $SCAN_FOR_MALWARE -eq 1 ]] && echo -e "${BLUE}Malware Scan: ENABLED${NC}"
echo "------------------------------------------------------"

# Verify Docker is running
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Docker not found or not in PATH${NC}"
    exit 1
fi

# Verify containers exist
if ! check_container "$WP_CONTAINER"; then
    echo -e "${RED}ERROR: WordPress container '$WP_CONTAINER' not running${NC}"
    echo "Available containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    exit 1
fi

if ! check_container "$DB_CONTAINER"; then
    echo -e "${YELLOW}WARNING: Database container '$DB_CONTAINER' not running${NC}"
    echo "Some database checks will be skipped."
fi

echo ""

#======================
# SYSTEM INFORMATION
#======================
echo -e "${CYAN}== SYSTEM INFORMATION (WP Container) ==${NC}"

# OS
if check_container "$WP_CONTAINER"; then
    OS_INFO=$(run_wp "cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"'")
    log_result INFO "SYS-01" "OS: $OS_INFO"
else
    log_result FAIL "SYS-01" "WordPress container not available"
fi

# PHP Version
if check_container "$WP_CONTAINER"; then
    PHP_VERSION=$(run_wp "php -r 'echo PHP_VERSION;'")
    log_result INFO "SYS-02" "PHP Version: $PHP_VERSION"
    
    # Check if PHP is supported
    PHP_MAJOR=$(echo "$PHP_VERSION" | cut -d. -f1)
    if [[ "$PHP_MAJOR" -lt 8 ]]; then
        log_result WARN "SYS-02a" "PHP version < 8.0 (EOL risk)" "Update to PHP 8.2+"
    fi
else
    log_result FAIL "SYS-02" "WordPress container not available"
fi

# Web server
if check_container "$WP_CONTAINER"; then
    WEBSERVER=$(run_wp "ps aux | grep -E 'apache2|nginx' | grep -v grep | head -n1 | awk '{print \$11}'")
    if [[ -n "$WEBSERVER" ]]; then
        log_result INFO "SYS-03" "Web Server: ${WEBSERVER}"
        
        # Get version
        if [[ "$WEBSERVER" == *"apache"* ]]; then
            APACHE_VERSION=$(run_wp "apache2 -v 2>/dev/null | grep 'Server version' | awk '{print \$3}'")
            [[ -n "$APACHE_VERSION" ]] && log_result INFO "SYS-03a" "Version: $APACHE_VERSION"
        elif [[ "$WEBSERVER" == *"nginx"* ]]; then
            NGINX_VERSION=$(run_wp "nginx -v 2>&1 | awk -F'/' '{print \$2}'")
            [[ -n "$NGINX_VERSION" ]] && log_result INFO "SYS-03a" "Version: nginx/$NGINX_VERSION"
        fi
    else
        log_result WARN "SYS-03" "Web Server: Not detected"
    fi
else
    log_result FAIL "SYS-03" "WordPress container not available"
fi

# Container disk usage
if check_container "$WP_CONTAINER"; then
    DISK_USAGE=$(run_wp "df -h $WP_PATH | tail -1 | awk '{print \$5}' | sed 's/%//'")
    if [[ $DISK_USAGE -gt 90 ]]; then
        log_result WARN "SYS-04" "Container disk usage: ${DISK_USAGE}%" "Free up disk space"
    elif [[ $DISK_USAGE -gt 80 ]]; then
        log_result INFO "SYS-04" "Container disk usage: ${DISK_USAGE}% (monitor)"
    else
        log_result PASS "SYS-04" "Container disk usage: ${DISK_USAGE}%"
    fi
fi

echo
#======================
# DATABASE INFORMATION
#======================
echo -e "${CYAN}== DATABASE INFORMATION (DB Container) ==${NC}"

if check_container "$DB_CONTAINER"; then
    MYSQL_VERSION=$(run_db "mysql -V 2>/dev/null | awk '{print \$5}' | tr -d ','")
    log_result INFO "DB-01" "MySQL Version: $MYSQL_VERSION"
else
    log_result WARN "DB-01" "Database container not available - skipping DB checks"
fi

echo
#======================
# WORDPRESS VERSION & CORE
#======================
echo -e "${CYAN}== WORDPRESS VERSION & INTEGRITY ==${NC}"

# Check if WP-CLI is available
WP_CLI_AVAILABLE=0
if run_wp "command -v wp >/dev/null 2>&1"; then
    WP_CLI_AVAILABLE=1
    log_result INFO "WP-CLI-00" "WP-CLI available in container"
else
    log_result WARN "WP-CLI-00" "WP-CLI not available" "Install WP-CLI for enhanced checks"
fi

if check_container "$WP_CONTAINER"; then
    if [[ $WP_CLI_AVAILABLE -eq 1 ]]; then
        WP_VERSION=$(run_wp "wp core version --path=$WP_PATH --allow-root 2>/dev/null")
        if [[ -n "$WP_VERSION" ]]; then
            log_result INFO "WP-VER-01" "WordPress Version: $WP_VERSION"
        else
            log_result FAIL "WP-VER-01" "WordPress not installed or WP-CLI error"
        fi
        
        # Core updates
        run_wp "wp core check-update --path=$WP_PATH --allow-root 2>/dev/null | grep -q 'Success: WordPress is at the latest version'"
        if [[ $? -eq 0 ]]; then
            log_result PASS "WP-VER-02" "WordPress core up-to-date"
        else
            log_result WARN "WP-VER-02" "WordPress core update available" "wp core update"
        fi
        
        # Core integrity check
        if run_wp "wp core verify-checksums --path=$WP_PATH --allow-root >/dev/null 2>&1"; then
            log_result PASS "WP-VER-03" "Core files intact"
        else
            log_result FAIL "WP-VER-03" "Core file integrity compromised" "wp core download --skip-content --force"
        fi
    else
        # Fallback: try to read version from version.php
        WP_VERSION=$(run_wp "grep \"wp_version = \" $WP_PATH/wp-includes/version.php | cut -d\"'\" -f2")
        if [[ -n "$WP_VERSION" ]]; then
            log_result INFO "WP-VER-01" "WordPress Version: $WP_VERSION (from version.php)"
        else
            log_result WARN "WP-VER-01" "Cannot determine WordPress version"
        fi
    fi
fi

echo
#======================
# FILESYSTEM & CONFIG
#======================
echo -e "${CYAN}== FILESYSTEM SECURITY ==${NC}"

# wp-config.php exists
if check_container "$WP_CONTAINER"; then
    if run_wp "[ -f $WP_CONFIG ]"; then
        log_result PASS "WP-FS-01" "wp-config.php exists"
    else
        log_result FAIL "WP-FS-01" "wp-config.php not found in container"
    fi
fi

# File permissions
check_perms "$WP_CONFIG" 640 "WP-FS-02"
check_perms "$WP_PATH" 755 "WP-FS-03"
check_perms "$WP_PATH/wp-content" 755 "WP-FS-04"
check_perms "$WP_PATH/wp-content/uploads" 755 "WP-FS-05"
check_perms "$WP_PATH/wp-content/plugins" 755 "WP-FS-06"
check_perms "$WP_PATH/wp-content/themes" 755 "WP-FS-07"

# wp-config.php ownership
if check_container "$WP_CONTAINER"; then
    owner=$(run_wp "stat -c '%U:%G' $WP_CONFIG 2>/dev/null")
    if [[ -n "$owner" ]]; then
        if [[ "$owner" == "root:$WEB_GROUP" ]] || [[ "$owner" == "$WEB_USER:$WEB_GROUP" ]]; then
            log_result PASS "WP-FS-08" "wp-config.php owned by $owner"
        else
            log_result FAIL "WP-FS-08" "wp-config.php owned by $owner" "chown root:$WEB_GROUP $WP_CONFIG"
            auto_fix_ownership "$WP_CONFIG" "root" "$WEB_GROUP"
        fi
    fi
fi

# Check for .git directories
if run_wp "[ -d $WP_PATH/.git ]"; then
    log_result FAIL "WP-FS-09" ".git directory exposed" "rm -rf $WP_PATH/.git or block via .htaccess"
else
    log_result PASS "WP-FS-09" "No .git directory found"
fi

# Check for backup files
BACKUP_FILES=$(run_wp "find $WP_PATH -maxdepth 2 -type f \( -name '*.sql' -o -name '*.tar.gz' -o -name '*.zip' -o -name '*.bak' \) 2>/dev/null | wc -l")
if [[ $BACKUP_FILES -gt 0 ]]; then
    log_result WARN "WP-FS-10" "Found $BACKUP_FILES backup/archive files in web root" "Move backups outside web root"
    [[ $VERBOSE -eq 1 ]] && run_wp "find $WP_PATH -maxdepth 2 -type f \( -name '*.sql' -o -name '*.tar.gz' -o -name '*.zip' -o -name '*.bak' \)"
else
    log_result PASS "WP-FS-10" "No backup files in web root"
fi

# Check directory listing
if run_wp "[ -f $WP_PATH/.htaccess ]"; then
    if run_wp "grep -q 'Options -Indexes' $WP_PATH/.htaccess"; then
        log_result PASS "WP-FS-11" "Directory listing disabled"
    else
        log_result WARN "WP-FS-11" "Directory listing not explicitly disabled" "Add 'Options -Indexes' to .htaccess"
    fi
fi

echo
#======================
# WORDPRESS HARDENING
#======================
echo -e "${CYAN}== WORDPRESS HARDENING ==${NC}"

if run_wp "[ -f $WP_CONFIG ]"; then
    # File editor
    if run_wp "grep -q 'DISALLOW_FILE_EDIT' $WP_CONFIG"; then
        log_result PASS "WP-H-01" "File editor disabled"
    else
        log_result FAIL "WP-H-01" "File editor enabled" "define('DISALLOW_FILE_EDIT', true);"
    fi

    # File mods
    if run_wp "grep -q 'DISALLOW_FILE_MODS' $WP_CONFIG"; then
        log_result PASS "WP-H-02" "Plugin/theme installs restricted"
    else
        log_result WARN "WP-H-02" "Plugin/theme installs allowed" "define('DISALLOW_FILE_MODS', true);"
    fi

    # Debug mode
    if run_wp "grep -q 'WP_DEBUG.*false' $WP_CONFIG"; then
        log_result PASS "WP-H-03" "WP_DEBUG disabled"
    else
        log_result FAIL "WP-H-03" "WP_DEBUG enabled in production" "Set WP_DEBUG to false"
    fi

    # Force SSL
    if run_wp "grep -q 'FORCE_SSL_ADMIN.*true' $WP_CONFIG"; then
        log_result PASS "WP-H-04" "Force SSL for admin enabled"
    else
        log_result WARN "WP-H-04" "Force SSL not enforced" "define('FORCE_SSL_ADMIN', true);"
    fi

    # Security keys
    if run_wp "grep -q 'put your unique phrase here' $WP_CONFIG"; then
        log_result FAIL "WP-H-05" "Default security keys in use" "Generate new keys at https://api.wordpress.org/secret-key/1.1/salt/"
    else
        log_result PASS "WP-H-05" "Custom security keys configured"
    fi

    # Database prefix
    DB_PREFIX=$(run_wp "grep 'table_prefix' $WP_CONFIG | cut -d\"'\" -f2")
    if [[ "$DB_PREFIX" == "wp_" ]]; then
        log_result WARN "WP-H-06" "Default database prefix 'wp_' in use" "Change to custom prefix"
    else
        log_result PASS "WP-H-06" "Custom database prefix: $DB_PREFIX"
    fi

    # Automatic updates
    if run_wp "grep -q 'AUTOMATIC_UPDATER_DISABLED.*true' $WP_CONFIG"; then
        log_result WARN "WP-H-07" "Automatic updates disabled" "Enable for security patches"
    else
        log_result PASS "WP-H-07" "Automatic updates enabled"
    fi
else
    log_result FAIL "WP-H-00" "wp-config.php not found"
fi

echo
#======================
# DATABASE SECURITY
#======================
echo -e "${CYAN}== DATABASE SECURITY ==${NC}"

if run_wp "[ -f $WP_CONFIG ]"; then
    # Get DB credentials from wp-config.php
    DB_USER=$(run_wp "grep \"define('DB_USER'\" $WP_CONFIG | cut -d\"'\" -f4")
    DB_PASS=$(run_wp "grep \"define('DB_PASSWORD'\" $WP_CONFIG | cut -d\"'\" -f4")
    
    # Root user check
    if [[ "$DB_USER" == "root" ]]; then
        log_result FAIL "WP-DB-01" "Database using root user" "Create dedicated DB user"
    elif [[ -n "$DB_USER" ]]; then
        log_result PASS "WP-DB-01" "Database user not root: $DB_USER"
    else
        log_result WARN "WP-DB-01" "Could not determine DB user"
    fi

    # Empty password check
    if [[ -z "$DB_PASS" ]]; then
        log_result FAIL "WP-DB-02" "Empty DB password" "Set strong password"
    else
        log_result PASS "WP-DB-02" "DB password set"
    fi

    # Localhost check
    DB_HOST=$(run_wp "grep \"define('DB_HOST'\" $WP_CONFIG | cut -d\"'\" -f4")
    if [[ "$DB_HOST" == "localhost" ]] || [[ "$DB_HOST" == "127.0.0.1" ]]; then
        log_result PASS "WP-DB-03" "Database host: $DB_HOST (local)"
    else
        log_result INFO "WP-DB-03" "Database host: $DB_HOST (remote)"
    fi
fi

echo
#======================
# PLUGINS SECURITY
#======================
echo -e "${CYAN}== PLUGINS SECURITY ==${NC}"

if [[ $WP_CLI_AVAILABLE -eq 1 ]]; then
    # Check for inactive plugins
    INACTIVE_PLUGINS=$(run_wp "wp plugin list --status=inactive --path=$WP_PATH --allow-root --format=count 2>/dev/null")
    if [[ $INACTIVE_PLUGINS -gt 0 ]]; then
        log_result WARN "WP-PL-01" "$INACTIVE_PLUGINS inactive plugins found" "Delete unused plugins"
        [[ $VERBOSE -eq 1 ]] && run_wp "wp plugin list --status=inactive --path=$WP_PATH --allow-root --fields=name,version"
    else
        log_result PASS "WP-PL-01" "No inactive plugins"
    fi

    # Check for plugin updates
    PLUGIN_UPDATES=$(run_wp "wp plugin list --update=available --path=$WP_PATH --allow-root --format=count 2>/dev/null")
    if [[ $PLUGIN_UPDATES -gt 0 ]]; then
        log_result WARN "WP-PL-02" "$PLUGIN_UPDATES plugins with updates available" "wp plugin update --all"
        [[ $VERBOSE -eq 1 ]] && run_wp "wp plugin list --update=available --path=$WP_PATH --allow-root --fields=name,version,update_version"
    else
        log_result PASS "WP-PL-02" "All plugins up to date"
    fi

    # Check for abandoned plugins
    log_result INFO "WP-PL-03" "Checking for potentially abandoned plugins..."
    CURRENT_YEAR=$(date +%Y)
    ABANDONED=0
    
    # Get active plugins list
    ACTIVE_PLUGINS=$(run_wp "wp plugin list --status=active --path=$WP_PATH --allow-root --field=name 2>/dev/null")
    
    while IFS= read -r plugin; do
        if [[ -n "$plugin" ]]; then
            LAST_UPDATED=$(run_wp "wp plugin get $plugin --path=$WP_PATH --allow-root --field=last_updated 2>/dev/null | cut -d'-' -f1")
            if [[ -n "$LAST_UPDATED" ]] && [[ $((CURRENT_YEAR - LAST_UPDATED)) -gt 2 ]]; then
                ((ABANDONED++))
                [[ $VERBOSE -eq 1 ]] && echo "  └── $plugin (last updated: $LAST_UPDATED)"
            fi
        fi
    done <<< "$ACTIVE_PLUGINS"
    
    if [[ $ABANDONED -gt 0 ]]; then
        log_result WARN "WP-PL-04" "$ABANDONED potentially abandoned plugins" "Review and replace if possible"
    else
        log_result PASS "WP-PL-04" "No abandoned plugins detected"
    fi
else
    log_result INFO "WP-PL-00" "WP-CLI not available - skipping plugin checks"
fi

echo
#======================
# THEMES SECURITY
#======================
echo -e "${CYAN}== THEMES SECURITY ==${NC}"

if [[ $WP_CLI_AVAILABLE -eq 1 ]]; then
    # Check for inactive themes
    INACTIVE_THEMES=$(run_wp "wp theme list --status=inactive --path=$WP_PATH --allow-root --format=count 2>/dev/null")
    ACTIVE_THEME=$(run_wp "wp theme list --status=active --path=$WP_PATH --allow-root --field=name 2>/dev/null")
    
    # Allow one default theme as backup
    if [[ $INACTIVE_THEMES -gt 1 ]]; then
        log_result WARN "WP-TH-01" "$INACTIVE_THEMES inactive themes" "Keep only active + 1 default backup theme"
    else
        log_result PASS "WP-TH-01" "Minimal theme count"
    fi

    # Check for theme updates
    THEME_UPDATES=$(run_wp "wp theme list --update=available --path=$WP_PATH --allow-root --format=count 2>/dev/null")
    if [[ $THEME_UPDATES -gt 0 ]]; then
        log_result WARN "WP-TH-02" "$THEME_UPDATES themes with updates" "wp theme update --all"
    else
        log_result PASS "WP-TH-02" "All themes up to date"
    fi

    log_result INFO "WP-TH-03" "Active theme: $ACTIVE_THEME"
else
    log_result INFO "WP-TH-00" "WP-CLI not available - skipping theme checks"
fi

echo
#======================
# USER ACCOUNTS
#======================
echo -e "${CYAN}== USER ACCOUNTS ==${NC}"

if [[ $WP_CLI_AVAILABLE -eq 1 ]]; then
    # Count admin users
    ADMIN_COUNT=$(run_wp "wp user list --role=administrator --path=$WP_PATH --allow-root --format=count 2>/dev/null")
    log_result INFO "WP-USR-01" "Administrator accounts: $ADMIN_COUNT"
    
    if [[ $ADMIN_COUNT -gt 3 ]]; then
        log_result WARN "WP-USR-01a" "High number of admin accounts" "Review and reduce admin privileges"
    fi

    # Check for default 'admin' username
    if run_wp "wp user get admin --path=$WP_PATH --allow-root >/dev/null 2>&1"; then
        log_result FAIL "WP-USR-02" "Default 'admin' username exists" "Rename or delete admin user"
    else
        log_result PASS "WP-USR-02" "No default 'admin' username"
    fi

    # List all users if verbose
    if [[ $VERBOSE -eq 1 ]]; then
        echo "  User list:"
        run_wp "wp user list --path=$WP_PATH --allow-root --fields=ID,user_login,user_email,roles" | while read line; do
            echo "    $line"
        done
    fi
else
    log_result INFO "WP-USR-00" "WP-CLI not available - skipping user checks"
fi

echo
#======================
# WEB SERVER EXPOSURE
#======================
echo -e "${CYAN}== WEB SERVER EXPOSURE ==${NC}"

# xmlrpc
if run_wp "[ -f $WP_PATH/xmlrpc.php ]"; then
    log_result WARN "WP-WEB-01" "xmlrpc.php present" "Disable via plugin or web server if unused"
else
    log_result PASS "WP-WEB-01" "xmlrpc.php not present"
fi

# readme.html
if run_wp "[ -f $WP_PATH/readme.html ]"; then
    log_result FAIL "WP-WEB-02" "readme.html exposed" "rm readme.html"
    if [[ $AUTO_FIX -eq 1 ]]; then
        run_wp "rm -f $WP_PATH/readme.html" && log_result INFO "AUTO-FIX" "Removed readme.html"
    fi
else
    log_result PASS "WP-WEB-02" "readme.html removed"
fi

# license.txt
if run_wp "[ -f $WP_PATH/license.txt ]"; then
    log_result WARN "WP-WEB-03" "license.txt exposed" "rm license.txt"
    if [[ $AUTO_FIX -eq 1 ]]; then
        run_wp "rm -f $WP_PATH/license.txt" && log_result INFO "AUTO-FIX" "Removed license.txt"
    fi
else
    log_result PASS "WP-WEB-03" "license.txt removed"
fi

# Check for exposed wp-config backups
WP_CONFIG_BACKUPS=$(run_wp "find $WP_PATH -maxdepth 1 -name 'wp-config*.php*' -not -name 'wp-config.php' 2>/dev/null | wc -l")
if [[ $WP_CONFIG_BACKUPS -gt 0 ]]; then
    log_result FAIL "WP-WEB-04" "Found $WP_CONFIG_BACKUPS wp-config backup files" "Remove or move outside web root"
else
    log_result PASS "WP-WEB-04" "No wp-config backup files"
fi

echo
#======================
# SSL/TLS CONFIGURATION
#======================
echo -e "${CYAN}== SSL/TLS CONFIGURATION ==${NC}"

if [[ $WP_CLI_AVAILABLE -eq 1 ]]; then
    SITE_URL=$(run_wp "wp option get siteurl --path=$WP_PATH --allow-root 2>/dev/null")
    
    if [[ "$SITE_URL" == https://* ]]; then
        log_result PASS "WP-SSL-01" "Site URL uses HTTPS"
    else
        log_result FAIL "WP-SSL-01" "Site URL uses HTTP" "Update to HTTPS: wp option update siteurl 'https://...'"
    fi
    
    HOME_URL=$(run_wp "wp option get home --path=$WP_PATH --allow-root 2>/dev/null")
    if [[ "$HOME_URL" == https://* ]]; then
        log_result PASS "WP-SSL-02" "Home URL uses HTTPS"
    else
        log_result FAIL "WP-SSL-02" "Home URL uses HTTP" "Update to HTTPS: wp option update home 'https://...'"
    fi
fi

# Check .htaccess for HTTPS redirect
if run_wp "[ -f $WP_PATH/.htaccess ]"; then
    if run_wp "grep -q 'RewriteCond %{HTTPS} off' $WP_PATH/.htaccess || grep -q 'RewriteCond %{HTTP:X-Forwarded-Proto} !https' $WP_PATH/.htaccess"; then
        log_result PASS "WP-SSL-03" "HTTPS redirect configured in .htaccess"
    else
        log_result WARN "WP-SSL-03" "No HTTPS redirect in .htaccess" "Add HTTPS redirect rules"
    fi
fi

echo
#======================
# PHP HARDENING
#======================
echo -e "${CYAN}== PHP HARDENING (Container) ==${NC}"

# expose_php
if run_wp "php -i 2>/dev/null | grep -q 'expose_php => Off'"; then
    log_result PASS "WP-PHP-01" "expose_php disabled"
else
    log_result WARN "WP-PHP-01" "expose_php enabled" "Set expose_php=Off in php.ini"
fi

# display_errors
if run_wp "php -i 2>/dev/null | grep -q 'display_errors => Off'"; then
    log_result PASS "WP-PHP-02" "display_errors disabled"
else
    log_result FAIL "WP-PHP-02" "display_errors enabled" "Set display_errors=Off in php.ini"
fi

# file_uploads
if run_wp "php -i 2>/dev/null | grep -q 'file_uploads => On'"; then
    log_result PASS "WP-PHP-03" "file_uploads enabled"
else
    log_result WARN "WP-PHP-03" "file_uploads disabled" "May break media uploads"
fi

# upload_max_filesize
MAX_UPLOAD=$(run_wp "php -i 2>/dev/null | grep 'upload_max_filesize' | head -1 | awk '{print \$3}'")
log_result INFO "WP-PHP-04" "Max upload size: $MAX_UPLOAD"

# memory_limit
MEMORY_LIMIT=$(run_wp "php -i 2>/dev/null | grep 'memory_limit' | head -1 | awk '{print \$3}'")
log_result INFO "WP-PHP-05" "PHP memory limit: $MEMORY_LIMIT"

# Dangerous functions
DISABLED_FUNCS=$(run_wp "php -i 2>/dev/null | grep 'disable_functions' | cut -d'>' -f2 | xargs")
if [[ -n "$DISABLED_FUNCS" ]]; then
    log_result PASS "WP-PHP-06" "Dangerous functions disabled"
    [[ $VERBOSE -eq 1 ]] && echo "  └── Disabled: $DISABLED_FUNCS"
else
    log_result WARN "WP-PHP-06" "No dangerous functions disabled" "Consider disabling: eval,exec,passthru,shell_exec,system"
fi

echo
#======================
# MALWARE SCANNING
#======================
if [[ $SCAN_FOR_MALWARE -eq 1 ]]; then
    echo -e "${CYAN}== MALWARE PATTERN SCANNING ==${NC}"
    
    log_result INFO "MAL-00" "Starting malware pattern scan (this may take a while)..."
    
    # base64_decode
    SUSPICIOUS=$(run_wp "grep -r 'base64_decode' $WP_PATH --include='*.php' 2>/dev/null | grep -v 'wp-includes' | wc -l")
    if [[ $SUSPICIOUS -gt 0 ]]; then
        log_result WARN "MAL-01" "Found $SUSPICIOUS files with base64_decode" "Review files for malicious code"
        [[ $VERBOSE -eq 1 ]] && run_wp "grep -r 'base64_decode' $WP_PATH --include='*.php' 2>/dev/null | grep -v 'wp-includes' | head -5"
    fi
    
    # eval
    SUSPICIOUS=$(run_wp "grep -r 'eval(' $WP_PATH --include='*.php' 2>/dev/null | grep -v 'wp-includes' | wc -l")
    if [[ $SUSPICIOUS -gt 0 ]]; then
        log_result WARN "MAL-02" "Found $SUSPICIOUS files with eval()" "Review for malicious code"
    fi
    
    # gzinflate
    SUSPICIOUS=$(run_wp "grep -r 'gzinflate' $WP_PATH --include='*.php' 2>/dev/null | wc -l")
    if [[ $SUSPICIOUS -gt 0 ]]; then
        log_result WARN "MAL-03" "Found $SUSPICIOUS files with gzinflate" "Common obfuscation technique"
    fi
    
    # str_rot13
    SUSPICIOUS=$(run_wp "grep -r 'str_rot13' $WP_PATH --include='*.php' 2>/dev/null | wc -l")
    if [[ $SUSPICIOUS -gt 0 ]]; then
        log_result WARN "MAL-04" "Found $SUSPICIOUS files with str_rot13" "Common obfuscation technique"
    fi
    
    # Check for PHP files in uploads
    PHP_IN_UPLOADS=$(run_wp "find $WP_PATH/wp-content/uploads -name '*.php' 2>/dev/null | wc -l")
    if [[ $PHP_IN_UPLOADS -gt 0 ]]; then
        log_result FAIL "MAL-05" "Found $PHP_IN_UPLOADS PHP files in uploads directory" "Remove all PHP files from uploads"
        [[ $VERBOSE -eq 1 ]] && run_wp "find $WP_PATH/wp-content/uploads -name '*.php' 2>/dev/null"
    else
        log_result PASS "MAL-05" "No PHP files in uploads directory"
    fi
    
    # Check for recently modified core files
    log_result INFO "MAL-06" "Checking for recently modified core files..."
    MODIFIED_CORE=$(run_wp "find $WP_PATH/wp-admin $WP_PATH/wp-includes -type f -mtime -7 2>/dev/null | wc -l")
    if [[ $MODIFIED_CORE -gt 0 ]]; then
        log_result WARN "MAL-06" "$MODIFIED_CORE core files modified in last 7 days" "Verify legitimacy"
        [[ $VERBOSE -eq 1 ]] && run_wp "find $WP_PATH/wp-admin $WP_PATH/wp-includes -type f -mtime -7 2>/dev/null | head -10"
    fi
    
    # Check for suspicious filenames
    SUSPICIOUS_FILES=$(run_wp "find $WP_PATH -type f \( -name '*.suspected' -o -name '*.bak.php' -o -name '*.php.bak' -o -name '404.php' \) 2>/dev/null | wc -l")
    if [[ $SUSPICIOUS_FILES -gt 0 ]]; then
        log_result WARN "MAL-07" "Found $SUSPICIOUS_FILES suspicious filenames" "Review and remove if malicious"
    fi
    
    log_result INFO "MAL-99" "Malware scan complete"
fi

echo
#======================
# BACKUP VERIFICATION
#======================
echo -e "${CYAN}== BACKUP VERIFICATION ==${NC}"

# Check common backup plugin directories
BACKUP_PLUGINS=("updraftplus" "backwpup" "duplicator" "all-in-one-wp-migration")
BACKUP_FOUND=0

for plugin in "${BACKUP_PLUGINS[@]}"; do
    if run_wp "[ -d $WP_PATH/wp-content/plugins/$plugin ]"; then
        BACKUP_FOUND=1
        log_result INFO "WP-BKP-01" "Backup plugin detected: $plugin"
    fi
done

if [[ $BACKUP_FOUND -eq 0 ]]; then
    log_result WARN "WP-BKP-01" "No common backup plugin detected" "Install backup solution"
fi

# Check for recent backups in common locations
if run_wp "[ -d $WP_PATH/wp-content/updraft ]"; then
    RECENT_BACKUPS=$(run_wp "find $WP_PATH/wp-content/updraft -type f -mtime -7 2>/dev/null | wc -l")
    if [[ $RECENT_BACKUPS -gt 0 ]]; then
        log_result PASS "WP-BKP-02" "Recent backups found (UpdraftPlus)"
    else
        log_result WARN "WP-BKP-02" "No recent backups in last 7 days"
    fi
fi

echo
#======================
# SECURITY HEADERS CHECK
#======================
echo -e "${CYAN}== SECURITY HEADERS CHECK ==${NC}"

if [[ $WP_CLI_AVAILABLE -eq 1 ]]; then
    SITE_URL=$(run_wp "wp option get siteurl --path=$WP_PATH --allow-root 2>/dev/null")
    
    if command -v curl >/dev/null 2>&1 && [[ -n "$SITE_URL" ]]; then
        log_result INFO "SEC-HDR-00" "Checking security headers for $SITE_URL..."
        
        # X-Frame-Options
        curl -sI "$SITE_URL" 2>/dev/null | grep -qi "X-Frame-Options" \
            && log_result PASS "SEC-HDR-01" "X-Frame-Options header present" \
            || log_result WARN "SEC-HDR-01" "X-Frame-Options header missing" "Add clickjacking protection"
        
        # X-Content-Type-Options
        curl -sI "$SITE_URL" 2>/dev/null | grep -qi "X-Content-Type-Options" \
            && log_result PASS "SEC-HDR-02" "X-Content-Type-Options header present" \
            || log_result WARN "SEC-HDR-02" "X-Content-Type-Options header missing" "Add MIME-sniffing protection"
        
        # Strict-Transport-Security
        curl -sI "$SITE_URL" 2>/dev/null | grep -qi "Strict-Transport-Security" \
            && log_result PASS "SEC-HDR-03" "HSTS header present" \
            || log_result WARN "SEC-HDR-03" "HSTS header missing" "Add HSTS for HTTPS enforcement"
        
        # Content-Security-Policy
        curl -sI "$SITE_URL" 2>/dev/null | grep -qi "Content-Security-Policy" \
            && log_result PASS "SEC-HDR-04" "CSP header present" \
            || log_result INFO "SEC-HDR-04" "CSP header not configured" "Consider adding CSP"
    else
        log_result INFO "SEC-HDR-00" "curl not available or no site URL - skipping header checks"
    fi
fi

echo
#======================
# SUMMARY & RISK ASSESSMENT
#======================
echo -e "${CYAN}==================== SUMMARY ====================${NC}"
echo -e "PASS: ${GREEN}$PASS_COUNT${NC}"
echo -e "WARN: ${YELLOW}$WARN_COUNT${NC}"
echo -e "FAIL: ${RED}$FAIL_COUNT${NC}"
echo -e "INFO: ${BLUE}$INFO_COUNT${NC}"

TOTAL_ISSUES=$((FAIL_COUNT + WARN_COUNT))

echo ""
echo -e "${CYAN}== RISK ASSESSMENT ==${NC}"
if [[ $FAIL_COUNT -eq 0 ]] && [[ $WARN_COUNT -le 2 ]]; then
    echo -e "${GREEN}✓ Security Status: GOOD${NC}"
    echo "  Your WordPress installation has strong security posture."
elif [[ $FAIL_COUNT -le 2 ]] && [[ $WARN_COUNT -le 5 ]]; then
    echo -e "${YELLOW}⚠ Security Status: MODERATE${NC}"
    echo "  Address critical issues within 24-48 hours."
else
    echo -e "${RED}✗ Security Status: HIGH RISK${NC}"
    echo "  Immediate action required. Multiple critical issues detected."
    echo "  Consider assuming compromise and performing full security audit."
fi

echo -e "${CYAN}=================================================${NC}"

# =====================================================
# GENERATE REPORTS
# =====================================================
if [[ $GENERATE_REPORT -eq 1 ]]; then
    echo ""
    echo -e "${CYAN}== GENERATING REPORT ==${NC}"
    
    case "$REPORT_FORMAT" in
        html)
            # Generate HTML report
            cat > "$REPORT_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>WordPress Security Audit Report (Docker) - $(date)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #0073aa; padding-bottom: 10px; }
        .summary { display: flex; justify-content: space-around; margin: 20px 0; }
        .summary-box { padding: 15px; border-radius: 5px; text-align: center; min-width: 100px; }
        .pass { background: #d4edda; color: #155724; }
        .warn { background: #fff3cd; color: #856404; }
        .fail { background: #f8d7da; color: #721c24; }
        .info { background: #d1ecf1; color: #0c5460; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #0073aa; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f9f9f9; }
        tr.PASS { border-left: 4px solid #28a745; }
        tr.WARN { border-left: 4px solid #ffc107; }
        tr.FAIL { border-left: 4px solid #dc3545; }
        tr.INFO { border-left: 4px solid #17a2b8; }
        .meta { color: #666; font-size: 14px; }
        .risk-good { color: #28a745; font-weight: bold; }
        .risk-moderate { color: #ffc107; font-weight: bold; }
        .risk-high { color: #dc3545; font-weight: bold; }
    </style>
</head>
<body>
<div class="container">
    <h1>WordPress Security Audit Report (Docker)</h1>
    <div class="meta">
        <p><strong>Host:</strong> $(hostname)</p>
        <p><strong>Date:</strong> $(date)</p>
        <p><strong>WP Container:</strong> $WP_CONTAINER</p>
        <p><strong>DB Container:</strong> $DB_CONTAINER</p>
        <p><strong>WordPress Path:</strong> $WP_PATH</p>
    </div>
    
    <div class="summary">
        <div class="summary-box pass">
            <h2>$PASS_COUNT</h2>
            <p>Passed</p>
        </div>
        <div class="summary-box warn">
            <h2>$WARN_COUNT</h2>
            <p>Warnings</p>
        </div>
        <div class="summary-box fail">
            <h2>$FAIL_COUNT</h2>
            <p>Failed</p>
        </div>
        <div class="summary-box info">
            <h2>$INFO_COUNT</h2>
            <p>Info</p>
        </div>
    </div>
    
    <table>
        <thead>
            <tr>
                <th>Status</th>
                <th>Reference</th>
                <th>Message</th>
                <th>Remediation</th>
            </tr>
        </thead>
        <tbody>
EOF
            # Report body was written during checks
            cat >> "$REPORT_FILE" << EOF
        </tbody>
    </table>
</div>
</body>
</html>
EOF
            log_result INFO "REPORT" "HTML report saved to: $REPORT_FILE"
            ;;
            
        json)
            # Finalize JSON
            echo "]" >> "$REPORT_FILE"
            sed -i '$ s/,$//' "$REPORT_FILE" 2>/dev/null  # Remove trailing comma
            sed -i '1s/^/[\n/' "$REPORT_FILE" 2>/dev/null  # Add opening bracket
            log_result INFO "REPORT" "JSON report saved to: $REPORT_FILE"
            ;;
            
        *)
            # TXT format (default)
            log_result INFO "REPORT" "Text report saved to: $REPORT_FILE"
            ;;
    esac
    
    # Send email if requested
    if [[ $SEND_EMAIL -eq 1 ]] && [[ -n "$EMAIL_TO" ]]; then
        if command -v mail >/dev/null 2>&1; then
            SUBJECT="WordPress Docker Security Audit - $(hostname) - $(date +%Y-%m-%d)"
            
            if [[ "$REPORT_FORMAT" == "html" ]]; then
                cat "$REPORT_FILE" | mail -s "$(echo -e "$SUBJECT\nContent-Type: text/html")" "$EMAIL_TO"
            else
                mail -s "$SUBJECT" "$EMAIL_TO" < "$REPORT_FILE"
            fi
            
            log_result INFO "EMAIL" "Report sent to $EMAIL_TO"
        else
            log_result WARN "EMAIL" "mail command not found, cannot send email"
        fi
    fi
fi

echo ""
echo -e "${GREEN}Audit complete!${NC}"
[[ -n "$REPORT_FILE" ]] && echo -e "Report location: ${CYAN}$REPORT_FILE${NC}"

exit 0
