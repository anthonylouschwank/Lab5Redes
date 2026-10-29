set -e
cd ~/fase3/leonardo
sed -i 's/\r$//' *.sh fase3.env fase3.env.example
mkdir -p ~/fase3/evidencias
export FASE3_EVID_DIR=~/fase3/evidencias
echo "######## chrony-servidor.sh"
sudo FASE3_EVID_DIR=$FASE3_EVID_DIR bash chrony-servidor.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
echo
echo "######## slapd: escuchar en todas las interfaces (Anthony Paso 2b)"
echo "Antes: $(grep '^SLAPD_SERVICES' /etc/default/slapd)"
sudo cp -a /etc/default/slapd /etc/default/slapd.bak.fase3
sudo sed -i 's|^SLAPD_SERVICES=.*|SLAPD_SERVICES="ldap:/// ldapi:///"|' /etc/default/slapd
sudo systemctl restart slapd
sleep 1
echo "Después: $(grep '^SLAPD_SERVICES' /etc/default/slapd)"
systemctl is-active slapd
sudo ss -tlnH 'sport = :389'
echo "Consulta anónima local (namingContexts):"
ldapsearch -x -LLL -H ldap://10.0.0.46 -b "" -s base namingContexts
echo "Apache (portal / intranet sin credenciales):"
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/intranet/
