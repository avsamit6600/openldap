#!/bin/bash -e

function fixperm() {
    chown -R openldap /var/lib/ldap /etc/ldap/slapd.d
    chgrp openldap /ssl/private
}

function start() {
    fixperm
    /usr/sbin/slapd -d ${DEBUG} \
    -h "ldap:/// ldapi:///" \
    -g openldap -u openldap \
    -F /etc/ldap/slapd.d
}

function startbg() {
    fixperm
    /usr/sbin/slapd -d 0 \
    -h "ldap:/// ldapi:///" \
    -g openldap -u openldap \
    -F /etc/ldap/slapd.d &
    PID=$!
    sleep 5
    while ! pgrep slapd > /dev/null; do sleep 1; done
}

function stopbg() {
    kill $PID
    while pgrep slapd > /dev/null; do sleep 1; done
}

function checkConfig() {
    if ! ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b cn=config dn 2>/dev/null >/dev/null; then
        echo "Error: cn=config not found" 1>&2
        exit 1
    fi
}

function checkCerts() {
    local certfile=
    local keyfile=
    echo -n "  check certificates ... "
    if test -e /ssl/certs/${DOMAIN}-ca.crt \
         -a -e /ssl/private/${DOMAIN}.key \
         -a -e /ssl/certs/${DOMAIN}.pem; then
        echo "found"
        chmod o= /ssl/private
        chgrp openldap /ssl/private
        ldapmodify -Y external -H ldapi:/// > /dev/null <<EOF
dn: cn=config
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /ssl/certs/${DOMAIN}-ca.crt
-
add: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /ssl/private/${DOMAIN}.key
-
add: olcTLSCertificateFile
olcTLSCertificateFile: /ssl/certs/${DOMAIN}.pem
EOF
    else
        echo "no"
        echo "   to activate TLS/SSL, please install:"
        echo "    - /ssl/certs/${DOMAIN}-ca.crt"
        echo "    - /ssl/private/${DOMAIN}.key"
        echo "    - /ssl/certs/${DOMAIN}.pem"
    fi
}

function setConfigPWD() {
    echo "  set cn=config password"
    ldapmodify -Y external -H ldapi:/// > /dev/null <<EOF
dn: cn=config
changetype: modify

dn: olcDatabase={0}config,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $(slappasswd -s '${PASSWORD}')
EOF
}

function disallowAnonymousBind() {
    echo "  disallow anonymous bind"
    ldapmodify -Y external -H ldapi:/// > /dev/null <<EOF
dn: cn=config
changetype: modify
add: olcDisallows
olcDisallows: bind_anon

dn: olcDatabase={-1}frontend,cn=config
changetype: modify
add: olcRequires
olcRequires: authc
EOF
}

function reconfigure() {
    echo "   reconfigure: ${ORGANIZATION} on ${DOMAIN}"
    debconf-set-selections <<EOF
slapd slapd/internal/generated_adminpw password ${PASSWORD}
slapd slapd/internal/adminpw password ${PASSWORD}
slapd slapd/password1 password ${PASSWORD}
slapd slapd/password2 password ${PASSWORD}
slapd shared/organization string ${ORGANIZATION}
slapd slapd/purge_database boolean false
slapd slapd/backend select HDB
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/domain string ${DOMAIN}
EOF
    dpkg-reconfigure -f noninteractive slapd > /dev/null
}

if test -z "${DOMAIN}"; then
    echo "ERROR: Specifying a domain is mandatory, use -e DOMAIN=example.org" 1>&2
    exit 1
fi
if test -z "${ORGANIZATION}"; then
    echo "ERROR: Specifying an organization is mandatory, use -e ORGANIZATION=\"Example Organization\"" 1>&2
    exit 1
fi
if test -z "${PASSWORD}"; then
    if test -e /etc/ldap/password; then
        export PASSWORD="$(</etc/ldap/password)"
    else
        export PASSWORD=$(pwgen 20 1)
        cat > /etc/ldap/password <<<"$PASSWORD"
    fi
fi
echo "Configuration ..."
reconfigure
startbg
checkConfig
setConfigPWD
checkCerts
stopbg
echo "Configuration done."
echo "**** Administrator Password: $(</etc/ldap/password)"
echo "starting slapd ..."
start
echo "Error: slapd terminated"
