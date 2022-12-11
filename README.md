# Raspberry-Pi-Backup-Cloud
Raspberry Pi backup script to store parameterizable files in the cloud via rclone

# Installation
- Clonen ins Home von User pi /home/pi
- Ändern der Dateien in .config
- ggf. hinzufügen eines Spezialskripts für weitere Sicherungen
- Hinzufügen eines Jobs in root crontab


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
