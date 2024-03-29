# Raspberry-Pi-Backup-Cloud
Backup Script zum Sichern einer Raspberry Pi Installation. 
Es werden zunächst eine Reihe von Systemdateien und Zuständen gesichert. Anschließend werden alle Dateien und Verzeichnisse gesichert, die in einer Konfigurationsdatei hinterlegt sind. Schließlich wird ein spezielles Backup Skript aufgerufen (falls vorhanden), in dem z.B. die Backup Anweisung zum Sichern einer Datenbank hinterlegt werden können.

Zum Sichern wird rclone verwendet, so dass die Daten in beliebigen Cloud-Speichern oder auf Netz- oder auf lokalen Laufwerken gesichert werden können.

Die Sicherung wird nach einem konfigurierbaren Gerätenamen benannt. Die Anzahl der aufzubewahrenden täglichen Sicherungen ist ebenfalls konfigurierbar.

## automatisch gesicherte Systemdateien
Diese müssen nicht in der config angegeben sein:  
````
/boot/config.txt
/boot/cmdline.txt
/proc/cpuinfo
/etc/hostname
/etc/logrotate.conf
rclone config
````

## Systemzustände die gesichert werden
Die Ausgabe nachfolgender Befehle werden ebenfalls gesichert  
````
(sudo) crontab -l
ps -ax
systemctl list-units --type=service
dpkg --get-selections
lsblk
df -h
````

# Versionen
Dezember 2022   initiale Version  
Dezember 2023   Erweiterung um die Möglichkeit in der config auch Verzeichnisse anzugeben und diverse Systembefahlausgaben

# Installation

## Clonen ins Home von User pi /home/pi

Clonen des Repositorys mit diesen Kommandos

````
cd ~
git clone https://github.com/spitzlbergerj/Raspberry-Pi-Backup-Cloud
````
Das Repository wird hierbei an diesen Pfad gecloned: ```/home/pi/Raspberry-Pi-Backup-Cloud```
Um die Skripte einfach handhabbar zu machen setzen wir noch einen symbolischen Link
```
ln -s /home/pi/Raspberry-Pi-Backup-Cloud/backup /home/pi/backup
```
Der Pfad für das Backup Skript und alle Config-Dateien ist danach ```/home/pi/backup```

Nun sind alle .config Dateien umzubenennen
```
mv /home/pi/backup/.config/backup2ndScript.sh-muster /home/pi/backup/.config/backup2ndScript.sh
mv /home/pi/backup/.config/backup_dirs.txt-muster /home/pi/backup/.config/backup_dirs.txt
mv /home/pi/backup/.config/backup_name.txt-muster /home/pi/backup/.config/backup_name.txt
mv /home/pi/backup/.config/rclone.conf-muster /home/pi/backup/.config/rclone.conf

```

Schließlich muss das Skript und ein eventuelles 2. Backup Skript noch ausführbar gemacht werden
```
chmod +x /home/pi/backup/backup.sh /home/pi/backup/.config/backup2ndScript.sh

```

## Ändern der Dateien in .config

Im Backup Pfad unter .config finden sich alle Konfigurationen

Die Benennung des Rechners und die Anzahl der aufzubewahrenden Tage finden sich in ```.config/backup_name.txt```

Die die sichernden Dateien finden sich in ```.config/backup_dirs.txt```
Hierbei sind stets vollkommende Pfade anzugeben. Wildcards wie "*" und "?" sind nicht (derzeit) erlaubt

Die Konfiguration für rclone befindet sich in ```.config/rclone.conf```


## ggf. hinzufügen eines Spezialskripts für weitere Sicherungen
Ändern Sie dazu das Skript in
```.config/backup2ndScript.sh```


## Hinzufügen eines Jobs in root crontab

Folgende Zeilen sind in die crontab des Users root einzufügen

```
# crontab root
#
# Output of the crontab jobs (including errors) is sent through
# email to the user the crontab file belongs to (unless redirected).
#
# min  hour  dayofmonth  month  dayofweek(0=Sonntag)   command
#
# Backup Dateien starten
05 01 * * *  /home/pi/backup/backup.sh >>/home/pi/.logs/backup.log 2>&1
```

# rclone installieren

rclone bitte nach Anleitung unter https://rclone.org/install/ installieren  
(in der Regel ausführen des Kommandos ```sudo -v ; curl https://rclone.org/install.sh | sudo bash```)

## neue Konfiguration erstellen
Ein neuer Remote-Speicher kann über nachfolgendes Kommando eingerichtet werden
```
rclone config
```
Falls Sie bereits eine rclone.conf mit korrekten Angaben (aus einer anderen Installation) haben, lesen Sie bitte unten unter "vorhandene Konfiguration verwenden" weiter

Für mein Google Drive mache ich nachfolgende Eingaben. Bitte beachten Sie, dass Sie vor diesem Schritt auf der Google Developer Console einen Account anlegen müssen und Ihre client_id und Ihren client_secret ermitteln müssen. Da Google die Verfahrensschritte hierzu immer wieder ändert, gebe ich hier keine Anleitung. Auf der [rclone Website](https://rclone.org/drive/#making-your-own-client-id) findet sich jedoch der Hinweis wie die Schritte aktuell sind.
```
n/s/q> n
name> MeinGoogleDrive
storage> 18 <Google Drive> (bitte kontrollieren, ändert sich von Version zu Version)
client_id> IhreGeheimeClientID
client_secret> IhrGemeinesPasswort
scope> 1 
root_folder_id> <leer lassen>
service_account_file> <leer lassen>
Edit advanced config? (y/n) n
Remote config, Use auto config? y
```
An dieser Stelle ist eine Sicherheitsüberprüfung erforderlich, die davon abhängt, wie Sie ihr Google Konto gesichert haben. Folgen Sie den Anweisungen, die rclone hier ausgibt. Danach geht es weiter:
```
Configure this as a team drive? n
Yes this is OK y
```

Nach diesen Schritten haben Sie Zugriff auf Ihren Cloudspeicher. Dies können Sie testen mit folgendem Kommando
```
rclone -v lsf MeinGoogleDrive:
```
Nun sollte Ihnen Ihr Google Drive aufgelistet werden.

## vorhandene Konfiguration verwenden
Falls Sie bereits eine funktionierende rclone.conf aus z. B. einer anderen Installation haben, können Sie das Einrichten vereinfachen. Nach der Installation von rclone kopieren Sie einfach die vorhandene Konfiguration an die entsprechenden Stellen und rclone ist damit vollständig konfiguriert.

Kopieren Sie zunächst ihre vorhandene Konfiguration nach /home/pi/backup/.config/rclone.conf

Dann führen Sie folgende Befehle aus  
```
cp /home/pi/backup/.config/rclone.conf /home/pi/.config/rclone/rclone.conf
sudo cp /home/pi/backup/.config/rclone.conf /root/.config/rclone/rclone.conf
```

Falls Sie sichergehen wollen, dass die rclone.conf an die richtigen Stellen kopiert wird, überprüfen Sie die Defaultspeicherorte mit
```
rclone config
```
bzw.
```
sudo rclone config
```
beim erstmaligen Aufruf dieser Befehle ohne vorherige Konfiguration sollte folgende Meldungen erscheinen
```NOTICE: Config file "/root/.config/rclone/rclone.conf" not found - using defaults```  
Diese gibt den Standard-Speicherort an, den Sie oben für die Copy Befehle nutzen

