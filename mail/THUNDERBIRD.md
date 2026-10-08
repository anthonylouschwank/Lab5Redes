# Configuración de Thunderbird (cliente Windows)

Requisito: la regla NRPT de `infra/windows-dns.ps1` activa, para que `mail.hospital.redes.test`
resuelva desde Windows. La contraseña de cada usuario está en `secrets/credenciales.env`.

## Crear la cuenta

1. *Configuración de cuenta → Añadir cuenta de correo* (o al abrir Thunderbird por primera vez).
2. Nombre: p. ej. `Anthony Lou` · Correo: `anthony@hospital.redes.test` · Contraseña: la del laboratorio.
3. Clic en **Configurar manualmente** y llenar:

| | Servidor entrante | Servidor saliente |
|---|---|---|
| Protocolo | IMAP | SMTP |
| Servidor | `mail.hospital.redes.test` | `mail.hospital.redes.test` |
| Puerto | `143` | `587` |
| Seguridad de la conexión | **STARTTLS** | **STARTTLS** |
| Método de autenticación | Contraseña normal | Contraseña normal |
| Nombre de usuario | `anthony` | `anthony` |

4. **Volver a probar** → **Hecho**.
5. Thunderbird avisará que el certificado de `mail.hospital.redes.test` no es de confianza (es
   autofirmado por el laboratorio). Elegir **Confirmar excepción de seguridad**. Puede pedirlo una
   vez para IMAP y otra al enviar el primer correo (SMTP).

Repetir con un segundo usuario (p. ej. `isabella`) en el mismo Thunderbird para el intercambio de mensajes.

## Capturas para la matriz

| ID | Qué capturar |
|---|---|
| MAIL-02 | Pantalla de configuración manual con los valores de la tabla |
| MAIL-03 | Bandeja de entrada de `anthony` abierta (login aceptado) |
| MAIL-04 | Cambiar la contraseña guardada por una incorrecta (*Herramientas → Configuración → Privacidad y seguridad → Contraseñas guardadas*) y abrir la bandeja: Thunderbird muestra el error de inicio de sesión |
| MAIL-05 | Correo redactado de `isabella` a `anthony` y su copia en *Enviados* |
| MAIL-06 | El mensaje recibido en la bandeja de entrada de `anthony` |
| MAIL-07 | Correo a `noexiste@hospital.redes.test`: Thunderbird muestra el rechazo del servidor (550) |

Logs correspondientes en la VM:

```bash
sudo grep -E 'imap-login|auth failed' /var/log/mail.log | tail      # Dovecot (MAIL-03 / MAIL-04)
sudo grep -E 'postfix/(submission/smtpd|lmtp)' /var/log/mail.log | tail   # Postfix (MAIL-05)
sudo grep 'User unknown' /var/log/mail.log | tail                   # Postfix (MAIL-07)
```
