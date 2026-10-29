echo "######## $(hostname) $(date -Is)"
echo "== ufw"; sudo ufw status verbose
echo "== sshd efectivo"; sudo sshd -T 2>/dev/null | grep -E '^(passwordauthentication|permitrootlogin|x11forwarding|kbdinteractiveauthentication) '
echo "== timer rollback (debe estar inactivo)"; systemctl is-active ufw-rollback.timer 2>/dev/null || true
echo "== servicios"; systemctl is-active chrony; systemctl is-active ModemManager 2>/dev/null || true
if [ "$(hostname)" = "ip-10-0-0-46" ]; then systemctl is-active slapd apache2; curl -s -o /dev/null -w 'portal %{http_code}\n' http://127.0.0.1/; curl -s -o /dev/null -w 'intranet sin cred %{http_code}\n' http://127.0.0.1/intranet/; ldapsearch -x -LLL -H ldap://127.0.0.1 -b "" -s base namingContexts | grep naming; fi
echo "== chrony"; chronyc -n sources | grep '^\^\*'
echo "== evidencias hardening"; ls ~/fase3/evidencias/ | grep -E 'hardening|evidencias-'
echo "== diff puertos"; diff ~/fase3/evidencias/hardening-antes-$(hostname).txt ~/fase3/evidencias/hardening-despues-$(hostname).txt && echo "(sin cambios en puertos en escucha)"
echo "== resultados en evidencia"; grep -E 'RESULTADO|FALLO|AVISO|Acceso confirmado|Deshabilitado' ~/fase3/evidencias/evidencias-$(hostname)-*.txt | tail -n 15
