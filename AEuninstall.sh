sudo systemctl stop 1001_AECored.service
sudo systemctl disable 1001_AECored.service
sudo rm -f /etc/systemd/system/1001_AECored.service
sudo systemctl daemon-reload
sudo systemctl reset-failed
systemctl status 1001_AECored.service
