#!/bin/bash
# --------------------------------------------------
# Backup Skript fuer Raspberrys mit Config Dateien
# (c) Josef Spitzlberger, 03.12.2022
# (c) Josef Spitzlberger, 30.12.2023 erweitert um die Moeglichkeit, in der config Datei auch Verzeichnisse anzugeben
# --------------------------------------------------

# ---------------------------------------------------------------------
# Funktion zum rekursiven Sichern der logrotate Konfigurationsdateien
# ---------------------------------------------------------------------

# Funktion zum Sichern und Durchsuchen von logrotate Konfigurationsdateien und Verzeichnissen
sichern_und_durchsuchen_logrotate_conf() {
    local conf_datei_or_dir=$1
    local backup_pfad=$2

    # Überprüfen, ob es sich um ein Verzeichnis handelt
    if [ -d "$conf_datei_or_dir" ]; then
        # Pfad im Backup-Verzeichnis erstellen und Verzeichnis sichern
        echo "   ... sichern Verzeichnis $conf_datei_or_dir"
        local dir_path=$(dirname "$conf_datei_or_dir")
        mkdir -p "$backup_pfad/$dir_path"
        cp -r "$conf_datei_or_dir" "$backup_pfad/$dir_path"
        
        # Alle Dateien im Verzeichnis durchgehen
        for file in "$conf_datei_or_dir"/*; do
            [ -f "$file" ] && sichern_und_durchsuchen_logrotate_conf "$file" "$backup_pfad"
        done
    elif [ -f "$conf_datei_or_dir" ]; then
        # Pfad im Backup-Verzeichnis erstellen und Datei sichern
        echo "   ... sichern Konfigurationsdatei $conf_datei_or_dir"
        local dir_path=$(dirname "$conf_datei_or_dir")
        mkdir -p "$backup_pfad/$dir_path"
        cp "$conf_datei_or_dir" "$backup_pfad/$dir_path"

        # Durchsuchen der Datei nach weiteren Konfigurationsdateien
        grep -Eo 'include\s+/[^ ]+' "$conf_datei_or_dir" | while IFS= read -r line
        do
            local new_conf_file=$(echo $line | awk '{print $2}')
            if [ -f "$new_conf_file" ] || [ -d "$new_conf_file" ]; then
                sichern_und_durchsuchen_logrotate_conf "$new_conf_file" "$backup_pfad"
            fi
        done
    fi
}


# --------------------------------------------------
# Variable
# --------------------------------------------------

BACKUP_PFAD_LOKAL="/home/pi/backup"

CONFIG_NAME="${BACKUP_PFAD_LOKAL}/.config/backup_name.txt"
CONFIG_DIRS="${BACKUP_PFAD_LOKAL}/.config/backup_dirs.txt"
CONFIG_RCLONE="${BACKUP_PFAD_LOKAL}/.config/rclone.conf"
CONFIG_2ND_SCRIPT="${BACKUP_PFAD_LOKAL}/.config/backup2ndScript.sh"

# initialisieren
BACKUP_DIR_HEAD="default-geraet"
BACKUP_DIR=${BACKUP_PFAD_LOKAL}/backups/${BACKUP_DIR_HEAD}-$(date +%Y%m%d-%H%M%S)
BACKUP_ANZAHL="30"
RCLONE_NAME="clouddrive"
RCLONE_PATH="backup"

# --------------------------------------------------
# Konfiguration einlesen
# --------------------------------------------------
echo "Configuration einlesen ..."

echo "... sicherstellen, Windows CRLF --> LF"
echo "$(tr -d '\r' < ${CONFIG_NAME})" > ${CONFIG_NAME}
echo "$(tr -d '\r' < ${CONFIG_DIRS})" > ${CONFIG_DIRS}

# Geraetename und Anzahl aufzubewahrende Sicherungen lesen, setzen 
# erste Zeile Geraetename, zweite Zeile Anzahl Tage
# um sicherzugehen, wird Windows CRLF durch LF ersetzt
echo "... Geraetename, Anzahl Sicherungen und rclone name einlesen"
{
    read -r readline_name
    read -r readline_anzahl
    read -r readline_rlonename
    read -r readline_rlonepath
} < ${CONFIG_NAME}
BACKUP_DIR_HEAD=${readline_name}
BACKUP_DIR=${BACKUP_PFAD_LOKAL}/backups/${BACKUP_DIR_HEAD}_$(date +%Y%m%d-%H%M%S)
BACKUP_ANZAHL=$((${readline_anzahl}))
RCLONE_NAME=${readline_rlonename}
RCLONE_PATH=${readline_rlonepath}

echo "... Backup Directory: $BACKUP_DIR"
echo "... Backup Versionen: $BACKUP_ANZAHL"
echo "... rclone Name: $RCLONE_NAME"
echo "... Cloud Pfad: $RCLONE_PATH"

echo "... Backup Directory anlegen"
mkdir ${BACKUP_DIR}

# --------------------------------------------------
# Allg. Dateien sichern
# --------------------------------------------------

# dieses Skript und die Konfiguration
printf "\nBackup Skript, Backup Config und rclone config sichern ...\n"
mkdir ${BACKUP_DIR}/backup
cp ${BACKUP_PFAD_LOKAL}/backup.sh ${BACKUP_DIR}/backup
cp ${CONFIG_NAME} ${BACKUP_DIR}/backup
cp ${CONFIG_DIRS} ${BACKUP_DIR}/backup
cp ${CONFIG_RCLONE} ${BACKUP_DIR}/backup

# raspi-config
printf "\nraspi-config, etc. sichern ...\n"
mkdir ${BACKUP_DIR}/boot ${BACKUP_DIR}/proc ${BACKUP_DIR}/etc
cp /boot/config.txt ${BACKUP_DIR}/boot
cp /boot/cmdline.txt ${BACKUP_DIR}/boot
cp /proc/cpuinfo ${BACKUP_DIR}/proc
cp /etc/hostname ${BACKUP_DIR}/etc
cp /etc/fstab ${BACKUP_DIR}/etc

# logrotate
# cp /etc/logrotate.conf ${BACKUP_DIR}/etc
sichern_und_durchsuchen_logrotate_conf "/etc/logrotate.conf" "${BACKUP_DIR}"

# Crontabs
printf "\nCrontabs sichern ...\n"
mkdir ${BACKUP_DIR}/crontab
crontab -u pi -l > ${BACKUP_DIR}/crontab/crontab-pi.txt
crontab -u root -l > ${BACKUP_DIR}/crontab/crontab-root.txt

# Systemdienste, Software
printf "\nSystemdienste sichern ...\n"
mkdir ${BACKUP_DIR}/dienste_software
systemctl list-units --type=service > ${BACKUP_DIR}/dienste_software/systemctl_list_units_service.txt
dpkg --get-selections > ${BACKUP_DIR}/dienste_software/dpkg_installierte_packete.txt
lsblk > ${BACKUP_DIR}/dienste_software/lsblk.txt
df -h > ${BACKUP_DIR}/dienste_software/df_h.txt

# rclone
printf "\nrclone config sichern ...\n"
mkdir ${BACKUP_DIR}/rclone ${BACKUP_DIR}/rclone/root ${BACKUP_DIR}/rclone/pi ${BACKUP_DIR}/rclone/backup_sh
cp /root/.config/rclone/rclone.conf ${BACKUP_DIR}/rclone/root
cp /home/pi/.config/rclone/rclone.conf ${BACKUP_DIR}/rclone/pi
cp ${CONFIG_RCLONE} ${BACKUP_DIR}/rclone/backup_sh

# Sichern Prozessliste
printf "\nProzessliste sichern ...\n\n"
mkdir ${BACKUP_DIR}/processes
ps -ax > ${BACKUP_DIR}/processes/ps-ax.txt

# zu sichernde Dateien und Verzeichnisse einlesen und kopieren
echo "Dateien und Verzeichnisse sichern ..."
while IFS= read -r LINE
do
    echo "... ${LINE}"

    # Pfad im Backup-Verzeichnis erstellen
    echo "   ... ... anlegen Sub-Directory"
    cd ${BACKUP_DIR}
    copypath=$(pwd)

    IFS='/'; pathelements=(${LINE:1})
    for ((i = 0 ; i <= $(( ${#pathelements[@]} - 2 )) ; i++)); do
        [ ! -d ${pathelements[$i]} ] && mkdir ${pathelements[$i]}
        cd ${pathelements[$i]}
        copypath=$(pwd)
    done
    unset IFS

    # Ueberpruefen, ob der Pfad ein Verzeichnis ist
    if [ -d "$LINE" ]; then
        # Rekursives Kopieren des Verzeichnisses
        echo "   ... kopieren Verzeichnis"
        cp -r "$LINE" "${copypath}/"
    else
        # Datei kopieren
        echo "   ... kopieren Datei"
        cp ${LINE} ${copypath}/
    fi
done < ${CONFIG_DIRS}

# starten des zusaetzlichen Backup Skripts fuer Sonderfaelle und sichern desselben
if [ -f "$CONFIG_2ND_SCRIPT" ]; then
    echo "... 2. Skript aufrufen"
    ${CONFIG_2ND_SCRIPT} ${BACKUP_DIR}
    cp ${CONFIG_2ND_SCRIPT} ${BACKUP_DIR}/backup
fi

# Alte Sicherungen die nach X neuen Sicherungen entfernen
echo "alte Sicherungen loeschen ....."
pushd ${BACKUP_PFAD_LOKAL}/backups; ls -drt1 ${BACKUP_PFAD_LOKAL}/backups/${BACKUP_DIR_HEAD}* | head -n -${BACKUP_ANZAHL} | xargs rm -r; popd

# Synchronisieren in die Cloud
echo "rclone sync starten ..." 
rclone sync local:${BACKUP_PFAD_LOKAL}/backups ${RCLONE_NAME}:${RCLONE_PATH}/${BACKUP_DIR_HEAD} --config ${CONFIG_RCLONE}

echo "Backup abgeschlossen!" 
