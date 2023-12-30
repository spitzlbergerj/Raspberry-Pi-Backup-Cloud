#!/bin/bash
# --------------------------------------------------
# Backup Skript fuer Raspberrys mit Config Dateien
# (c) Josef Spitzlberger, 03.12.2022
# (c) Josef Spitzlberger, 30.12.2023 erweitert um die Moeglichkeit, in der config Datei auch Verzeichnisse anzugeben
# --------------------------------------------------

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
echo "... Geraetename und Anzahl Sicherungen"
{
    read -r readline_name
    read -r readline_anzahl
} < ${CONFIG_NAME}
BACKUP_DIR_HEAD=${readline_name}
BACKUP_DIR=${BACKUP_PFAD_LOKAL}/backups/${BACKUP_DIR_HEAD}_$(date +%Y%m%d-%H%M%S)
BACKUP_ANZAHL=$((${readline_anzahl}))

echo "... Backup Directory: $BACKUP_DIR"
echo "... Backup Versionen: $BACKUP_ANZAHL"

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

# logrotate
cp /etc/logrotate.conf ${BACKUP_DIR}/etc

# Crontabs
printf "\nCrontabs sichern ...\n"
mkdir ${BACKUP_DIR}/crontab
crontab -u pi -l > ${BACKUP_DIR}/crontab/crontab-pi.txt
crontab -u root -l > ${BACKUP_DIR}/crontab/crontab-root.txt

# rclone
printf "\nrclone config sichern ...\n"
mkdir ${BACKUP_DIR}/rclone ${BACKUP_DIR}/rclone/root ${BACKUP_DIR}/rclone/pi
cp /root/.config/rclone/rclone.conf ${BACKUP_DIR}/rclone/root
cp /home/pi/.config/rclone/rclone.conf ${BACKUP_DIR}/rclone/pi

# Sichern Prozessliste
printf "\nProzessliste sichern ...\n\n"
mkdir ${BACKUP_DIR}/processes
ps -ax > ${BACKUP_DIR}/processes/ps-ax.txt

# zu sichernde Dateien und Verzeichnisse einlesen und kopieren
echo "Dateien und Verzeichnisse sichern ..."
while IFS= read -r LINE
do
    echo "... ${LINE}"

    # Ueberpruefen, ob der Pfad ein Verzeichnis ist
    if [ -d "$LINE" ]; then
        # Rekursives Kopieren des Verzeichnisses
        echo "   ... kopieren Verzeichnis"
        cp -r "$LINE" "${BACKUP_DIR}/"
    else
        echo "   ... kopieren Datei"
        # Directory Pfad anlegen
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

        # Datei kopieren
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
rclone sync local:${BACKUP_PFAD_LOKAL}/backups LGBsharepoint:Backup/Geraete/Raspberry/${BACKUP_DIR_HEAD} --config ${CONFIG_RCLONE}

echo "Backup abgeschlossen!" 
