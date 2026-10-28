# Contrato LDAP para la intranet Apache

Estado: **propuesto y preparado para prueba local**. Anthony debe confirmar el dominio/base final antes del despliegue en AWS.

| Dato | Valor predeterminado |
|---|---|
| URI desde la misma EC2 | `ldap://127.0.0.1` |
| URI desde otra instancia | `ldap://10.0.0.46` |
| Base DN | `dc=hospital,dc=redes,dc=test` |
| Usuarios | `ou=People,dc=hospital,dc=redes,dc=test` |
| Grupos | `ou=Groups,dc=hospital,dc=redes,dc=test` |
| Bind DN de Apache | `uid=svc-intranet,ou=People,dc=hospital,dc=redes,dc=test` |
| Filtro de usuario | `(objectClass=inetOrgPerson)` |
| Atributo de login | `uid` |
| Atributo de grupo | `memberUid` (contiene UID, no DN) |

La contraseña de `svc-intranet` se genera en la instancia y se entrega a Isabella por un canal seguro. No se versiona.

Configuración relevante de `mod_authnz_ldap`:

```apache
AuthBasicProvider ldap
AuthLDAPURL "ldap://127.0.0.1/ou=People,dc=hospital,dc=redes,dc=test?uid?one?(objectClass=inetOrgPerson)"
AuthLDAPBindDN "uid=svc-intranet,ou=People,dc=hospital,dc=redes,dc=test"
AuthLDAPBindPassword "SECRETO_INSTALADO_FUERA_DEL_REPOSITORIO"
AuthLDAPGroupAttribute memberUid
AuthLDAPGroupAttributeIsDN off
Require ldap-group cn=medicos,ou=Groups,dc=hospital,dc=redes,dc=test
Require ldap-group cn=ti,ou=Groups,dc=hospital,dc=redes,dc=test
Require ldap-group cn=laboratorio,ou=Groups,dc=hospital,dc=redes,dc=test
```

Si LDAP y Apache terminan en instancias distintas, SG-Servidores debe permitir TCP/389 **solo** desde el SG o la IP privada de Apache. Si comparten la EC2 propuesta `10.0.0.46`, Apache debe usar loopback y no necesita atravesar el SG.

