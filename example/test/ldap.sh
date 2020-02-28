ldapsearch -H ldap://0.0.0.0:3890 -b "dc=my-company,dc=com" -D "cn=admin,dc=my-company,dc=com" -w 1234567890 "(objectClass=*)"
