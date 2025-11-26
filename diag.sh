#!/bin/bash

# ==========================================================
# DIAGNOSTIC SYSTÈME UNIVERSEL (RPI & LINUX) - V4.1
# ==========================================================

# 0. VÉRIFICATION ROOT
if [ "$EUID" -ne 0 ]; then
    if [ -f "$0" ]; then
        echo "Besoin des droits administrateur..."
        exec sudo /bin/bash "$0" "$@"
        exit
    fi
    echo -e "\033[0;31mERREUR: Ce script doit être lancé avec sudo !\033[0m"
    echo "Usage: curl -s URL | sudo bash"
    exit 1
fi

# DÉTECTION TYPE MACHINE
if command -v vcgencmd &> /dev/null; then
    IS_RPI=true
    MACHINE_TYPE="Raspberry Pi"
else
    IS_RPI=false
    MACHINE_TYPE="Linux Générique (x86/x64)"
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
echo -e "${BLUE}       DIAGNOSTIC SYSTÈME - $MACHINE_TYPE                 ${NC}"
echo -e "${BLUE}==========================================================${NC}"
date
echo ""

# 1. INFO SYSTÈME
echo -e "${YELLOW}[1] SYSTÈME & HORLOGE${NC}"

if [ "$IS_RPI" = true ]; then
    # Correction du bug "octet nul" avec tr -d '\0'
    MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
else
    MODEL=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || hostnamectl | grep "Chassis" | awk '{print $2}')
    [ -z "$MODEL" ] && MODEL="PC / Serveur Inconnu"
fi

KERNEL=$(uname -r)
UPTIME=$(uptime -p)

echo -e "Modèle          : ${CYAN}$MODEL${NC}"
echo -e "Kernel          : $KERNEL"
echo -e "Uptime          : $UPTIME"

NTP_STATUS=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
if [[ "$NTP_STATUS" == "yes" ]]; then
    echo -e "Synchro Heure   : ${GREEN}OK (NTP Actif)${NC}"
else
    echo -e "Synchro Heure   : ${YELLOW}Inactif ou Non géré par systemd${NC}"
fi

# 2. SANTÉ MATÉRIELLE
echo -e "\n${YELLOW}[2] SANTÉ MATÉRIELLE${NC}"

if [ "$IS_RPI" = true ]; then
    TEMP=$(vcgencmd measure_temp | egrep -o '[0-9]*\.[0-9]*')
    STATUS=$(vcgencmd get_throttled | awk -F= '{print $2}')
    STATUS_DEC=$((STATUS))
    
    if (( $(echo "$TEMP > 75.0" | bc -l) )); then C=$RED; elif (( $(echo "$TEMP > 60.0" | bc -l) )); then C=$YELLOW; else C=$GREEN; fi
    echo -e "Température CPU : ${C}${TEMP}°C${NC}"

    echo -n "Alimentation    : "
    if [[ "$STATUS" == "0x0" ]]; then
        echo -e "${GREEN}Parfaite (0x0)${NC}"
    else
        echo -e "${RED}PROBLÈME ($STATUS)${NC}"
        if (( (STATUS_DEC & 0x1) != 0 )); then echo -e "   -> ${RED}ACTUELLEMENT en sous-tension !${NC}"; fi
        if (( (STATUS_DEC & 0x10000) != 0 )); then echo -e "   -> ${YELLOW}Sous-tension historique${NC}"; fi
    fi
else
    # Mode PC
    TEMP_FILE=$(find /sys/class/thermal/thermal_zone*/temp | head -n 1)
    if [ -f "$TEMP_FILE" ]; then
        TEMP_RAW=$(cat "$TEMP_FILE")
        TEMP=$(echo "$TEMP_RAW / 1000" | bc)
        echo -e "Température CPU : ${GREEN}${TEMP}°C${NC}"
    else
        echo -e "Température CPU : Non disponible (VM ou capteur absent)"
    fi
fi

# 3. STOCKAGE
echo -e "\n${YELLOW}[3] STOCKAGE${NC}"
if grep -q "ro," /proc/mounts | grep -w "/" | grep -q "ext4"; then
    echo -e "${RED}ALERTE : Système en READ-ONLY !${NC}"
else
    echo -e "Mode Écriture   : ${GREEN}RW (OK)${NC}"
fi

df -h / | awk 'NR==2 {
    usage=$5; sub("%", "", usage);
    if (usage > 90) c="\033[0;31m"; else if (usage > 75) c="\033[1;33m"; else c="\033[0;32m";
    print "Espace Utilisé  : "c$5"\033[0m ("$3" / "$2")"
}'

# 4. MÉMOIRE & PROCESSUS
echo -e "\n${YELLOW}[4] MÉMOIRE & PROCESSUS${NC}"
free -h | awk 'NR==2{printf "RAM             : %s / %s (Libre: %s)\n", $3,$2,$4}'

# Formatage propre des colonnes (PID, CPU, MEM, NOM)
echo -e "${PURPLE}--- Top 3 CPU ---${NC}"
echo "PID    %CPU  %MEM  PROCESSUS"
ps -eo pid,%cpu,%mem,comm --sort=-%cpu | head -n 4 | tail -n 3 | awk '{printf "%-6s %-5s %-5s %s\n", $1, $2"%", $3"%", $4}'

echo -e "${PURPLE}--- Top 3 RAM ---${NC}"
echo "PID    %CPU  %MEM  PROCESSUS"
ps -eo pid,%cpu,%mem,comm --sort=-%mem | head -n 4 | tail -n 3 | awk '{printf "%-6s %-5s %-5s %s\n", $1, $2"%", $3"%", $4}'

# 5. RÉSEAU
echo -e "\n${YELLOW}[5] RÉSEAU${NC}"
hostname -I | awk '{print "IP Locale       : " $1}'

if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    echo -e "Internet        : ${GREEN}Connecté${NC}"
else
    echo -e "Internet        : ${RED}DÉCONNECTÉ${NC}"
fi

if command -v iwconfig &> /dev/null; then
    # On vérifie si une interface sans fil a une connexion active
    WIFI_INTERFACE=$(iwconfig 2>/dev/null | grep -v "no wireless" | grep "IEEE" | awk '{print $1}')
    
    if [ ! -z "$WIFI_INTERFACE" ]; then
        WIFI_QUAL=$(iwconfig $WIFI_INTERFACE | grep "Link Quality" | awk -F'=' '{print $2}' | awk '{print $1}')
        ESSID=$(iwgetid -r)
        NUM=$(echo $WIFI_QUAL | cut -d/ -f1)
        
        if [[ "$NUM" =~ ^[0-9]+$ ]]; then
             if [ "$NUM" -ge 50 ]; then C=$GREEN; elif [ "$NUM" -ge 30 ]; then C=$YELLOW; else C=$RED; fi
             echo -e "Signal Wi-Fi    : ${C}$WIFI_QUAL${NC} (ESSID: $ESSID)"
        else
             echo -e "Wi-Fi           : Activé mais pas de Link Quality"
        fi
    else
        echo -e "Wi-Fi           : Non connecté ou Ethernet utilisé"
    fi
else
    echo -e "Wi-Fi           : Outil non installé"
fi

# 6. LOGS & SÉCURITÉ
echo -e "\n${YELLOW}[6] LOGS & SÉCURITÉ${NC}"
if [ -f /var/log/auth.log ]; then
    FAIL_COUNT=$(grep "Failed password" /var/log/auth.log | wc -l)
    echo -e "Intrusions SSH  : $FAIL_COUNT tentatives échouées"
else
    echo -e "Intrusions SSH  : (Fichier log non standard)"
fi

echo -e "${PURPLE}--- Dernières erreurs (Journalctl) ---${NC}"
# Filtre le bruit habituel (PulseAudio, etc) pour voir les vrais problèmes
journalctl -p 3 -xb --no-pager | grep -v "pulseaudio" | grep -v "GetManagedObjects" | tail -n 3 | while read line; do
    echo -e "${RED}> $line${NC}"
done || echo "Rien à signaler."

# 7. SERVICES
echo -e "\n${YELLOW}[7] SERVICES CLÉS${NC}"
# J'ai ajouté vncserver et lightdm car présents dans tes logs
SERVICES="ssh sshd apache2 nginx mariadb docker cron smbd vncserver-x11-serviced lightdm"
for service in $SERVICES; do
    if systemctl list-unit-files "$service.service" &>/dev/null; then
        if systemctl is-active --quiet $service; then
            echo -e "$service : ${GREEN}OK${NC}"
        else
            echo -e "$service : ${RED}KO (Arrêté)${NC}"
        fi
    fi
done

echo -e "\n${BLUE}==========================================================${NC}"
