# Raspberry-Pi-Backup-Cloud
Raspberry Pi backup script to store parameterizable files in the cloud via rclone

# Installation

## Clonen ins Home von User pi /home/pi

Clonen des Repositorys mit diesen Kommando

Der Pfad für das Backup Skript und alle Config-Dateien ist danach ```/home/pi/backup```

## Ändern der Dateien in .config

Im Backup Pfad unter .config finden sich alle Konfigurationen

Die Benennung des Rechners und die Anzahl der aufzubewahrenden Tage finden sich in ```.config/backup_name.txt```

Die die sichernden Dateien finden sich in ```.config/backup_dirs.txt```
Hierbei sind stets vollkommende Pfade anzugeben. Wildcards wie "*" und "?" sind nicht (derzeit) erlaubt

Die Konfiguration für rclone befindet sich in ```.config/rclone.conf```


## ggf. hinzufügen eines Spezialskripts für weitere Sicherungen

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
