#!/bin/bash

# Couleurs pour la lisibilité
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==========================================================${NC}"
echo -e "${BLUE}       DIAGNOSTIC COMPLET DU RASPBERRY PI                 ${NC}"
echo -e "${BLUE}==========================================================${NC}"
date
echo ""

# 1. VÉRIFICATION DU MATÉRIEL (Voltage & Température)
echo -e "${YELLOW}[1] SANTÉ MATÉRIELLE (Voltage & Température)${NC}"
TEMP=$(vcgencmd measure_temp)
VOLT=$(vcgencmd get_throttled)
UPTIME=$(uptime -p)

echo -e "Température CPU : ${TEMP}"
echo -e "Uptime          : ${UPTIME}"

# Analyse du code Throttled (Voltage)
if [[ "$VOLT" == "throttled=0x0" ]]; then
    echo -e "Alimentation    : ${GREEN}OK (Pas de sous-tension détectée)${NC}"
else
    echo -e "Alimentation    : ${RED}ATTENTION ! Problème détecté ($VOLT)${NC}"
    echo "                  -> Si != 0x0, change ton alimentation ou ton câble USB."
fi

# 2. SYSTÈME DE FICHIERS & CARTE SD
echo -e "\n${YELLOW}[2] DISQUE & CARTE SD${NC}"
# Vérification si le système est passé en Read-Only
RO_CHECK=$(grep "ro," /proc/mounts | grep "ext4")
if [[ -n "$RO_CHECK" ]]; then
    echo -e "${RED}ALERTE CRITIQUE : Le système est monté en LECTURE SEULE (Read-Only) !${NC}"
    echo "$RO_CHECK"
else
    echo -e "${GREEN}Système de fichiers en écriture (RW) : OK${NC}"
fi

# Espace disque
df -h / | awk 'NR==2 {print "Espace Disque   : Utilisé "$3" sur "$2" ("$5")"}'

# Recherche d'erreurs I/O récentes (Signe de mort de carte SD)
echo -e "Erreurs I/O (dmesg) :"
dmesg | grep -Ei "I/O error|EXT4-fs error|mmcblk0: error" | tail -n 5 || echo "Aucune erreur récente visible."

# 3. MÉMOIRE & SWAP
echo -e "\n${YELLOW}[3] MÉMOIRE (RAM & SWAP)${NC}"
free -h
# Alerte si le Swap est utilisé
SWAP_USED=$(free | grep Swap | awk '{print $3}')
if [[ "$SWAP_USED" -gt 0 ]]; then
    echo -e "${RED}ATTENTION : Le SWAP est utilisé ! Cela tue ta carte SD.${NC}"
else
    echo -e "${GREEN}Swap non utilisé : OK${NC}"
fi

# 4. SERVICES & PROCESSUS
echo -e "\n${YELLOW}[4] SERVICES CRITIQUES${NC}"
# Vérification des services communs
for service in ssh apache2 nginx mysql mariadb grafana-server php7.3-fpm php8.1-fpm docker; do
    systemctl is-active --quiet $service && echo -e "$service : ${GREEN}ACTIF${NC}" || echo -e "$service : ${RED}INACTIF ou NON INSTALLÉ${NC}"
done

# Services en échec
echo -e "\nServices en erreur (failed) :"
systemctl list-units --state=failed --no-pager || echo "Aucun service en échec."

# 5. CRONTABS (La source de tes problèmes)
echo -e "\n${YELLOW}[5] TÂCHES PLANIFIÉES (CRON)${NC}"
echo -e "${BLUE}--- Crontab de l'utilisateur courant ($(whoami)) ---${NC}"
crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" || echo "Vide"

echo -e "${BLUE}--- Crontab ROOT (Attention aux reboots cachés) ---${NC}"
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Il faut lancer ce script avec SUDO pour voir le cron root !${NC}"
else
    crontab -u root -l 2>/dev/null | grep -v "^#" | grep -v "^$" || echo "Vide"
fi

# 6. RÉSEAU & PORTS
echo -e "\n${YELLOW}[6] RÉSEAU${NC}"
# IP locale
hostname -I | awk '{print "IP Locale       : " $1}'
# Ports en écoute
echo "Ports en écoute (Services accessibles) :"
if [ "$EUID" -ne 0 ]; then
    echo "Requis sudo pour voir les processus liés aux ports."
    ss -tln
else
    ss -tlnp | grep LISTEN | awk '{print $4, $6}' | head -n 10
fi

# 7. LOGS SYSTÈME RÉCENTS
echo -e "\n${YELLOW}[7] DERNIERS LOGS CRITIQUES (Journalctl)${NC}"
# Cherche les erreurs graves des dernières 24h
if [ "$EUID" -ne 0 ]; then
    echo "Requis sudo pour lire les logs système."
else
    journalctl -p 3 -xb --no-pager | tail -n 10 || echo "Pas d'erreurs critiques trouvées dans ce boot."
fi

echo -e "\n${BLUE}==========================================================${NC}"
echo -e "${BLUE}                  FIN DU DIAGNOSTIC                       ${NC}"
echo -e "${BLUE}==========================================================${NC}"
