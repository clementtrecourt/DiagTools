#!/bin/bash

# ==========================================================
# DIAGNOSTIC SYSTÈME & IMPRIMANTE (V5.0)
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
    MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
else
    MODEL=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || hostnamectl | grep "Chassis" | awk '{print $2}')
    [ -z "$MODEL" ] && MODEL="PC / Serveur Inconnu"
fi
echo -e "Modèle          : ${CYAN}$MODEL${NC}"
echo -e "Uptime          : $(uptime -p)"

NTP_STATUS=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
if [[ "$NTP_STATUS" == "yes" ]]; then
    echo -e "Synchro Heure   : ${GREEN}OK (NTP Actif)${NC}"
else
    echo -e "Synchro Heure   : ${YELLOW}Inactif ou Non géré${NC}"
fi

# 2. SANTÉ MATÉRIELLE
echo -e "\n${YELLOW}[2] SANTÉ MATÉRIELLE${NC}"
if [ "$IS_RPI" = true ]; then
    TEMP=$(vcgencmd measure_temp | egrep -o '[0-9]*\.[0-9]*')
    STATUS=$(vcgencmd get_throttled | awk -F= '{print $2}')
    if (( $(echo "$TEMP > 75.0" | bc -l) )); then C=$RED; elif (( $(echo "$TEMP > 60.0" | bc -l) )); then C=$YELLOW; else C=$GREEN; fi
    echo -e "Température CPU : ${C}${TEMP}°C${NC}"
    echo -n "Alimentation    : "
    if [[ "$STATUS" == "0x0" ]]; then echo -e "${GREEN}Parfaite (0x0)${NC}"; else echo -e "${RED}PROBLÈME ($STATUS)${NC}"; fi
else
    echo -e "Température CPU : (Mode PC - Non affiché)"
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
echo -e "${PURPLE}--- Top 3 CPU ---${NC}"
echo "PID    %CPU  %MEM  PROCESSUS"
ps -eo pid,%cpu,%mem,comm --sort=-%cpu | head -n 4 | tail -n 3 | awk '{printf "%-6s %-5s %-5s %s\n", $1, $2"%", $3"%", $4}'

# 5. RÉSEAU
echo -e "\n${YELLOW}[5] RÉSEAU${NC}"
hostname -I | awk '{print "IP Locale       : " $1}'
if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then echo -e "Internet        : ${GREEN}Connecté${NC}"; else echo -e "Internet        : ${RED}DÉCONNECTÉ${NC}"; fi

# 6. IMPRIMANTE TG2460 (CUSTOM)
echo -e "\n${YELLOW}[6] IMPRIMANTE TG2460${NC}"

# Recherche du binaire ReadStatus dans les dossiers home
TG_BIN=$(find /home -name "ReadStatus" -type f 2>/dev/null | head -n 1)

if [ -z "$TG_BIN" ]; then
    echo -e "Programme       : ${RED}Non trouvé (ReadStatus introuvable)${NC}"
else
    TG_DIR=$(dirname "$TG_BIN")
    echo -e "Chemin          : $TG_DIR"
    
    # Check USB (VID:PID 0DD4:0195)
    if lsusb | grep -qi "0dd4:0195"; then
        echo -e "Connexion USB   : ${GREEN}OK (Périphérique détecté)${NC}"
    else
        echo -e "Connexion USB   : ${RED}NON DÉTECTÉE (Vérifier câble)${NC}"
    fi

    # Config
    if [ -f "$TG_DIR/printer.cfg" ]; then
        API_HOST=$(grep "API_HOST" "$TG_DIR/printer.cfg" | cut -d= -f2 | tr -d '\r')
        echo -e "Cible API       : $API_HOST"
    fi

    # Check Processus
    PID_TG=$(pgrep -f "ReadStatus")
    if [ ! -z "$PID_TG" ]; then
        echo -e "Processus       : ${GREEN}EN COURS (PID $PID_TG)${NC}"
        echo "Note : Impossible de lancer le test manuel car le processus tourne déjà."
    else
        echo -e "Processus       : ${YELLOW}ARRÊTÉ${NC}"
        echo -e "${PURPLE}--- Test de lancement (3 sec) ---${NC}"
        
        # On lance ReadStatus avec un timeout de 3 secondes pour ne pas bloquer le script
        # On redirige la sortie vers un fichier temporaire pour l'analyser
        cd "$TG_DIR"
        timeout 3s ./ReadStatus > /tmp/tg_debug.log 2>&1
        
        # Analyse du log
        if grep -q "CeSmLm.so version" /tmp/tg_debug.log; then
            VER=$(grep "CeSmLm.so version" /tmp/tg_debug.log)
            echo -e "Version Lib     : ${GREEN}$VER${NC}"
        else
            echo -e "Version Lib     : ${RED}Erreur de chargement${NC}"
        fi
        
        if grep -q "HTTP/1.1 200 OK" /tmp/tg_debug.log; then
            echo -e "Test API        : ${GREEN}SUCCÈS (200 OK)${NC}"
        else
            echo -e "Test API        : ${RED}ÉCHEC ou Pas de réponse${NC}"
        fi
        
        # Afficher le dernier statut connu
        STATUS_LINE=$(grep "Changement status" /tmp/tg_debug.log | tail -n 1)
        if [ ! -z "$STATUS_LINE" ]; then
            echo -e "Dernier Statut  : ${CYAN}$STATUS_LINE${NC}"
        fi
        
        rm /tmp/tg_debug.log
    fi
fi

# 7. LOGS ERROR (Filtrés)
echo -e "\n${YELLOW}[7] LOGS ERREURS (Derniers 5)${NC}"
journalctl -p 3 -xb --no-pager | grep -vE "pulseaudio|GetManagedObjects|vncserver" | tail -n 5 | while read line; do
    echo -e "${RED}> $line${NC}"
done || echo "Rien à signaler."

echo -e "\n${BLUE}==========================================================${NC}"
