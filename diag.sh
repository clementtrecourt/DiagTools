#!/bin/bash

# ==========================================================
# DIAGNOSTIC RASPBERRY PI - V3.0 (Ultimate)
# ==========================================================

# 0. AUTO-ÉLÉVATION SUDO
# Si l'utilisateur n'est pas root, on relance le script avec sudo
if [ "$EUID" -ne 0 ]; then
    echo "Besoin des droits administrateur..."
    exec sudo /bin/bash "$0" "$@"
    exit
fi

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}==========================================================${NC}"
echo -e "${BLUE}       DIAGNOSTIC COMPLET DU RASPBERRY PI (V3.0)          ${NC}"
echo -e "${BLUE}==========================================================${NC}"
date
echo ""

# 1. INFO SYSTÈME & HEURE
echo -e "${YELLOW}[1] SYSTÈME & HORLOGE${NC}"
MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "Modèle inconnu")
KERNEL=$(uname -r)
UPTIME=$(uptime -p)

echo -e "Modèle          : ${CYAN}$MODEL${NC}"
echo -e "Kernel          : $KERNEL"
echo -e "Uptime          : $UPTIME"

# Vérification NTP (Time Sync) - Crucial pour RPi
NTP_STATUS=$(timedatectl show -p NTPSynchronized --value)
if [[ "$NTP_STATUS" == "yes" ]]; then
    echo -e "Synchro Heure   : ${GREEN}OK (NTP Actif)${NC}"
else
    echo -e "Synchro Heure   : ${RED}NON SYNCHRONISÉ ! (Risque d'erreurs APT/SSL)${NC}"
fi

# 2. SANTÉ MATÉRIELLE
echo -e "\n${YELLOW}[2] SANTÉ MATÉRIELLE${NC}"
TEMP=$(vcgencmd measure_temp | egrep -o '[0-9]*\.[0-9]*')
STATUS=$(vcgencmd get_throttled | awk -F= '{print $2}')
STATUS_DEC=$((STATUS))

# Couleur Température
if (( $(echo "$TEMP > 75.0" | bc -l) )); then COLOR_TEMP=$RED
elif (( $(echo "$TEMP > 60.0" | bc -l) )); then COLOR_TEMP=$YELLOW
else COLOR_TEMP=$GREEN; fi
echo -e "Température CPU : ${COLOR_TEMP}${TEMP}°C${NC}"

# Analyse Voltage
echo -n "Alimentation    : "
if [[ "$STATUS" == "0x0" ]]; then
    echo -e "${GREEN}Parfaite (0x0)${NC}"
else
    echo -e "${RED}PROBLÈME ($STATUS)${NC}"
    if (( (STATUS_DEC & 0x1) != 0 )); then echo -e "   -> ${RED}ACTUELLEMENT en sous-tension !${NC}"; fi
    if (( (STATUS_DEC & 0x10000) != 0 )); then echo -e "   -> ${YELLOW}Sous-tension historique (depuis le boot)${NC}"; fi
fi

# 3. DISQUE & I/O
echo -e "\n${YELLOW}[3] STOCKAGE (SD/SSD)${NC}"
# Vérif Read-Only
if grep -q "ro," /proc/mounts | grep -q "ext4"; then
    echo -e "${RED}ALERTE : Système en READ-ONLY !${NC}"
else
    echo -e "Mode Écriture   : ${GREEN}RW (OK)${NC}"
fi

# Espace disque racine
df -h / | awk 'NR==2 {
    usage=$5; sub("%", "", usage);
    if (usage > 90) c="\033[0;31m"; else if (usage > 75) c="\033[1;33m"; else c="\033[0;32m";
    print "Espace Utilisé  : "c$5"\033[0m ("$3" / "$2")"
}'

# 4. MÉMOIRE & PROCESSUS GOURMANDS
echo -e "\n${YELLOW}[4] MÉMOIRE & PROCESSUS${NC}"
free -h | awk 'NR==2{printf "RAM             : %s / %s (Libre: %s)\n", $3,$2,$4}'

# Top 3 CPU
echo -e "${PURPLE}--- Top 3 Consommation CPU ---${NC}"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%cpu | head -n 4 | awk '{printf "%-6s %-6s %-5s %s\n", $1, $5"%", $4"%", $3}' | grep -v PID

# Top 3 RAM
echo -e "${PURPLE}--- Top 3 Consommation RAM ---${NC}"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 4 | awk '{printf "%-6s %-6s %-5s %s\n", $1, $5"%", $4"%", $3}' | grep -v PID

# 5. RÉSEAU & WI-FI
echo -e "\n${YELLOW}[5] RÉSEAU${NC}"
hostname -I | awk '{print "IP Locale       : " $1}'

# Test Internet
if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    echo -e "Internet        : ${GREEN}Connecté${NC}"
else
    echo -e "Internet        : ${RED}DÉCONNECTÉ${NC}"
fi

# Analyse Wi-Fi (si présent)
if iwconfig 2>/dev/null | grep -q "IEEE 802.11"; then
    WIFI_QUAL=$(iwconfig 2>/dev/null | grep "Link Quality" | awk -F'=' '{print $2}' | awk '{print $1}')
    # Extraction numérateur/dénominateur
    NUM=$(echo $WIFI_QUAL | cut -d/ -f1)
    
    if [ "$NUM" -ge 50 ]; then WIFI_COLOR=$GREEN
    elif [ "$NUM" -ge 30 ]; then WIFI_COLOR=$YELLOW
    else WIFI_COLOR=$RED; fi
    
    echo -e "Signal Wi-Fi    : ${WIFI_COLOR}$WIFI_QUAL${NC} (ESSID: $(iwgetid -r))"
else
    echo -e "Wi-Fi           : Non détecté ou Ethernet uniquement"
fi

# 6. SÉCURITÉ & LOGS
echo -e "\n${YELLOW}[6] SÉCURITÉ & LOGS${NC}"

# Tentatives SSH échouées
if [ -f /var/log/auth.log ]; then
    FAIL_COUNT=$(grep "Failed password" /var/log/auth.log | wc -l)
    if [ "$FAIL_COUNT" -gt 50 ]; then
        echo -e "Intrusions SSH  : ${RED}$FAIL_COUNT tentatives échouées ! (Check tes ports)${NC}"
    else
        echo -e "Intrusions SSH  : ${GREEN}$FAIL_COUNT (Normal)${NC}"
    fi
fi

echo -e "${PURPLE}--- Dernières erreurs critiques ---${NC}"
journalctl -p 3 -xb --no-pager | tail -n 3 | while read line; do
    echo -e "${RED}> $line${NC}"
done || echo "Rien à signaler."

# 7. SERVICES
echo -e "\n${YELLOW}[7] SERVICES CLÉS${NC}"
# Liste simplifiée et dynamique
SERVICES="ssh apache2 mariadb docker homeassistant nodered cron"
for service in $SERVICES; do
    if systemctl list-units --full -all | grep -Fq "$service.service"; then
        systemctl is-active --quiet $service && echo -e "$service : ${GREEN}OK${NC}" || echo -e "$service : ${RED}KO${NC}"
    fi
done

echo -e "\n${BLUE}==========================================================${NC}"
