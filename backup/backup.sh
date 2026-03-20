#!/bin/bash
# --------------------------------------------------
# Backup Skript fuer Raspberry Pi / Linux-Systeme
# Basis: (c) Josef Spitzlberger, 03.12.2022 / 30.12.2023
# Ueberarbeitet: robuste Pfadbehandlung, Wildcards in backup_dirs.txt,
# sichere Behandlung von Leerzeichen, Kommentare in Konfigurationsdateien
# --------------------------------------------------

set -u
set -o pipefail
shopt -s nullglob globstar

# --------------------------------------------------
# Hilfsfunktionen
# --------------------------------------------------

log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'WARNUNG: %s\n' "$*" >&2
}

fail() {
    printf 'FEHLER: %s\n' "$*" >&2
    exit 1
}

require_file() {
    local file_path="$1"
    [[ -f "$file_path" ]] || fail "Datei nicht gefunden: $file_path"
}

normalize_crlf() {
    local file_path="$1"
    [[ -f "$file_path" ]] || return 0
    sed -i 's/\r$//' "$file_path"
}

is_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

expand_leading_tilde() {
    local input="$1"
    if [[ "$input" == "~" ]]; then
        printf '%s\n' "$HOME"
    elif [[ "$input" == ~/* ]]; then
        printf '%s/%s\n' "$HOME" "${input#~/}"
    else
        printf '%s\n' "$input"
    fi
}

contains_glob() {
    [[ "$1" == *[\*\?\[]* ]]
}

copy_item_preserve_path() {
    local source_path="$1"
    local backup_root="$2"
    local parent_dir

    parent_dir="$(dirname "$source_path")"
    mkdir -p "$backup_root$parent_dir"
    cp -a "$source_path" "$backup_root$parent_dir/"
}

copy_if_exists_preserve_path() {
    local source_path="$1"
    local backup_root="$2"

    if [[ -e "$source_path" ]]; then
        copy_item_preserve_path "$source_path" "$backup_root"
    else
        warn "Nicht gefunden, uebersprungen: $source_path"
    fi
}

create_text_file() {
    local target_file="$1"
    shift
    mkdir -p "$(dirname "$target_file")"
    printf '%s\n' "$@" > "$target_file"
}

# --------------------------------------------------
# logrotate rekursiv sichern
# --------------------------------------------------

declare -A LOGROTATE_SEEN=()

sichern_und_durchsuchen_logrotate_conf() {
    local conf_path="$1"
    local backup_root="$2"
    local include_path=""

    [[ -e "$conf_path" ]] || {
        warn "logrotate include nicht gefunden: $conf_path"
        return 0
    }

    if [[ -n "${LOGROTATE_SEEN[$conf_path]:-}" ]]; then
        return 0
    fi
    LOGROTATE_SEEN["$conf_path"]=1

    if [[ -d "$conf_path" ]]; then
        log "   ... sichern logrotate-Verzeichnis $conf_path"
        copy_item_preserve_path "$conf_path" "$backup_root"

        local file
        for file in "$conf_path"/*; do
            [[ -f "$file" ]] || continue
            sichern_und_durchsuchen_logrotate_conf "$file" "$backup_root"
        done
        return 0
    fi

    if [[ -f "$conf_path" ]]; then
        log "   ... sichern logrotate-Konfigurationsdatei $conf_path"
        copy_item_preserve_path "$conf_path" "$backup_root"

        while IFS= read -r include_path; do
            include_path="$(expand_leading_tilde "$include_path")"
            [[ -n "$include_path" ]] || continue
            if [[ -e "$include_path" ]]; then
                sichern_und_durchsuchen_logrotate_conf "$include_path" "$backup_root"
            else
                warn "logrotate include existiert nicht: $include_path"
            fi
        done < <(
            awk '
                /^[[:space:]]*#/ { next }
                /^[[:space:]]*include[[:space:]]+/ {
                    sub(/^[[:space:]]*include[[:space:]]+/, "", $0)
                    sub(/[[:space:]]+#.*$/, "", $0)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
                    print $0
                }
            ' "$conf_path"
        )
    fi
}

# --------------------------------------------------
# Eintraege aus backup_dirs.txt verarbeiten
# --------------------------------------------------

process_backup_entry() {
    local raw_entry="$1"
    local entry="$raw_entry"
    local path=""
    local -a matches=()

    entry="${entry%$'\r'}"
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"

    [[ -n "$entry" ]] || return 0
    [[ "$entry" == \#* ]] && return 0

    entry="$(expand_leading_tilde "$entry")"
    log "... $entry"

    if contains_glob "$entry"; then
        mapfile -t matches < <(compgen -G "$entry" || true)

        if (( ${#matches[@]} == 0 )); then
            warn "Kein Treffer fuer Wildcard: $entry"
            return 0
        fi

        for path in "${matches[@]}"; do
            [[ -e "$path" ]] || continue
            if [[ -d "$path" ]]; then
                log "   ... kopieren Verzeichnis $path"
            else
                log "   ... kopieren Datei $path"
            fi
            copy_item_preserve_path "$path" "$BACKUP_DIR"
        done
        return 0
    fi

    if [[ -d "$entry" ]]; then
        log "   ... kopieren Verzeichnis $entry"
        copy_item_preserve_path "$entry" "$BACKUP_DIR"
    elif [[ -f "$entry" ]]; then
        log "   ... kopieren Datei $entry"
        copy_item_preserve_path "$entry" "$BACKUP_DIR"
    elif [[ -e "$entry" ]]; then
        log "   ... kopieren Sonderdatei $entry"
        copy_item_preserve_path "$entry" "$BACKUP_DIR"
    else
        warn "Pfad nicht gefunden, uebersprungen: $entry"
    fi
}

# --------------------------------------------------
# Variablen
# --------------------------------------------------

BACKUP_PFAD_LOKAL="/home/pi/backup"

CONFIG_NAME="${BACKUP_PFAD_LOKAL}/.config/backup_name.txt"
CONFIG_DIRS="${BACKUP_PFAD_LOKAL}/.config/backup_dirs.txt"
CONFIG_RCLONE="${BACKUP_PFAD_LOKAL}/.config/rclone.conf"
CONFIG_2ND_SCRIPT="${BACKUP_PFAD_LOKAL}/.config/backup2ndScript.sh"

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

# Initialisieren
BACKUP_DIR_HEAD="default-geraet"
BACKUP_ANZAHL="30"
RCLONE_NAME="clouddrive"
RCLONE_PATH="backup"

BACKUP_BASE="${BACKUP_PFAD_LOKAL}/backups"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_BASE}/${BACKUP_DIR_HEAD}_${TIMESTAMP}"

# --------------------------------------------------
# Konfiguration einlesen
# --------------------------------------------------

echo "Konfiguration einlesen ..."

require_file "$CONFIG_NAME"
require_file "$CONFIG_DIRS"
require_file "$CONFIG_RCLONE"

echo "... sicherstellen, Windows CRLF --> LF"
normalize_crlf "$CONFIG_NAME"
normalize_crlf "$CONFIG_DIRS"
normalize_crlf "$CONFIG_RCLONE"
[[ -f "$CONFIG_2ND_SCRIPT" ]] && normalize_crlf "$CONFIG_2ND_SCRIPT"

echo "... Geraetename, Anzahl Sicherungen und rclone name einlesen"
mapfile -t CONFIG_LINES < <(sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$CONFIG_NAME")

[[ ${#CONFIG_LINES[@]} -ge 1 ]] && BACKUP_DIR_HEAD="${CONFIG_LINES[0]}"
[[ ${#CONFIG_LINES[@]} -ge 2 ]] && BACKUP_ANZAHL="${CONFIG_LINES[1]}"
[[ ${#CONFIG_LINES[@]} -ge 3 ]] && RCLONE_NAME="${CONFIG_LINES[2]}"
[[ ${#CONFIG_LINES[@]} -ge 4 ]] && RCLONE_PATH="${CONFIG_LINES[3]}"

is_integer "$BACKUP_ANZAHL" || fail "Ungueltiger Wert fuer BACKUP_ANZAHL: $BACKUP_ANZAHL"
(( BACKUP_ANZAHL >= 1 )) || fail "BACKUP_ANZAHL muss mindestens 1 sein"

BACKUP_DIR="${BACKUP_BASE}/${BACKUP_DIR_HEAD}_$(date +%Y%m%d-%H%M%S)"

echo "... Backup Directory: $BACKUP_DIR"
echo "... Backup Versionen: $BACKUP_ANZAHL"
echo "... rclone Name: $RCLONE_NAME"
echo "... Cloud Pfad: $RCLONE_PATH"

echo "... Backup Directory anlegen"
mkdir -p "$BACKUP_DIR"

# --------------------------------------------------
# Allgemeine Dateien sichern
# --------------------------------------------------

printf "\nBackup Skript, Backup Config und rclone config sichern ...\n"
mkdir -p "${BACKUP_DIR}/backup"
cp -a "$SCRIPT_PATH" "${BACKUP_DIR}/backup/"
cp -a "$CONFIG_NAME" "${BACKUP_DIR}/backup/"
cp -a "$CONFIG_DIRS" "${BACKUP_DIR}/backup/"
cp -a "$CONFIG_RCLONE" "${BACKUP_DIR}/backup/"
[[ -f "$CONFIG_2ND_SCRIPT" ]] && cp -a "$CONFIG_2ND_SCRIPT" "${BACKUP_DIR}/backup/"

printf "\nraspi-config, etc. sichern ...\n"
copy_if_exists_preserve_path "/boot/config.txt" "$BACKUP_DIR"
copy_if_exists_preserve_path "/boot/cmdline.txt" "$BACKUP_DIR"
copy_if_exists_preserve_path "/boot/firmware/config.txt" "$BACKUP_DIR"
copy_if_exists_preserve_path "/boot/firmware/cmdline.txt" "$BACKUP_DIR"
copy_if_exists_preserve_path "/proc/cpuinfo" "$BACKUP_DIR"
copy_if_exists_preserve_path "/etc/hostname" "$BACKUP_DIR"
copy_if_exists_preserve_path "/etc/fstab" "$BACKUP_DIR"

printf "\nlogrotate sichern ...\n"
sichern_und_durchsuchen_logrotate_conf "/etc/logrotate.conf" "$BACKUP_DIR"

printf "\nCrontabs sichern ...\n"
mkdir -p "${BACKUP_DIR}/crontab"
if ! crontab -u pi -l > "${BACKUP_DIR}/crontab/crontab-pi.txt" 2>/dev/null; then
    create_text_file "${BACKUP_DIR}/crontab/crontab-pi.txt" "Kein Crontab fuer Benutzer pi vorhanden oder nicht lesbar."
fi
if ! crontab -u root -l > "${BACKUP_DIR}/crontab/crontab-root.txt" 2>/dev/null; then
    create_text_file "${BACKUP_DIR}/crontab/crontab-root.txt" "Kein Crontab fuer Benutzer root vorhanden oder nicht lesbar."
fi

printf "\nSystemdienste sichern ...\n"
mkdir -p "${BACKUP_DIR}/dienste_software"
systemctl list-units --type=service --all > "${BACKUP_DIR}/dienste_software/systemctl_list_units_service.txt" 2>/dev/null || true
systemctl list-unit-files --type=service > "${BACKUP_DIR}/dienste_software/systemctl_list_unit_files_service.txt" 2>/dev/null || true
dpkg --get-selections > "${BACKUP_DIR}/dienste_software/dpkg_installierte_packete.txt" 2>/dev/null || true
lsblk > "${BACKUP_DIR}/dienste_software/lsblk.txt" 2>/dev/null || true
df -h > "${BACKUP_DIR}/dienste_software/df_h.txt" 2>/dev/null || true

printf "\nrclone config sichern ...\n"
mkdir -p "${BACKUP_DIR}/rclone/root" "${BACKUP_DIR}/rclone/pi" "${BACKUP_DIR}/rclone/backup_sh"
[[ -f "/root/.config/rclone/rclone.conf" ]] && cp -a "/root/.config/rclone/rclone.conf" "${BACKUP_DIR}/rclone/root/"
[[ -f "/home/pi/.config/rclone/rclone.conf" ]] && cp -a "/home/pi/.config/rclone/rclone.conf" "${BACKUP_DIR}/rclone/pi/"
cp -a "$CONFIG_RCLONE" "${BACKUP_DIR}/rclone/backup_sh/"

printf "\nProzessliste sichern ...\n\n"
mkdir -p "${BACKUP_DIR}/processes"
ps -ax > "${BACKUP_DIR}/processes/ps-ax.txt" 2>/dev/null || true

# --------------------------------------------------
# Dateien und Verzeichnisse aus backup_dirs.txt sichern
# --------------------------------------------------

echo "Dateien und Verzeichnisse sichern ..."
while IFS= read -r line || [[ -n "$line" ]]; do
    process_backup_entry "$line"
done < "$CONFIG_DIRS"

# --------------------------------------------------
# Zusatzskript fuer Sonderfaelle
# --------------------------------------------------

if [[ -f "$CONFIG_2ND_SCRIPT" ]]; then
    echo "... 2. Skript aufrufen"
    bash "$CONFIG_2ND_SCRIPT" "$BACKUP_DIR"
fi

# --------------------------------------------------
# Alte Sicherungen loeschen
# --------------------------------------------------

echo "alte Sicherungen loeschen ....."
mkdir -p "$BACKUP_BASE"

mapfile -t EXISTING_BACKUPS < <(
    find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -name "${BACKUP_DIR_HEAD}_*" -printf '%f\n' | sort
)

if (( ${#EXISTING_BACKUPS[@]} > BACKUP_ANZAHL )); then
    DELETE_COUNT=$(( ${#EXISTING_BACKUPS[@]} - BACKUP_ANZAHL ))
    for ((i=0; i<DELETE_COUNT; i++)); do
        echo "... loesche ${EXISTING_BACKUPS[$i]}"
        rm -rf -- "${BACKUP_BASE}/${EXISTING_BACKUPS[$i]}"
    done
else
    echo "... keine alten Sicherungen zu loeschen"
fi

# --------------------------------------------------
# Synchronisieren in die Cloud
# --------------------------------------------------

echo "rclone sync starten ..."
rclone sync "$BACKUP_BASE" "${RCLONE_NAME}:${RCLONE_PATH}/${BACKUP_DIR_HEAD}" --config "$CONFIG_RCLONE"
RCLONE_RC=$?

if (( RCLONE_RC != 0 )); then
    fail "rclone sync fehlgeschlagen (Exit-Code $RCLONE_RC)"
fi

echo "Backup abgeschlossen!"