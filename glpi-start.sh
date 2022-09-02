#!/bin/bash

#Controle du choix de version ou prise de la latest
[[ ! "$VERSION_GLPI" ]] \
	&& VERSION_GLPI=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | grep tag_name | cut -d '"' -f 4)

if [[ -z "${TIMEZONE}" ]]; then echo "TIMEZONE is unset"; 
else 
echo "date.timezone = \"$TIMEZONE\"" > /etc/php/7.4/apache2/conf.d/timezone.ini;
echo "date.timezone = \"$TIMEZONE\"" > /etc/php/7.4/cli/conf.d/timezone.ini;
fi

SRC_GLPI=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/tags/${VERSION_GLPI} | jq .assets[0].browser_download_url | tr -d \")
TAR_GLPI=$(basename ${SRC_GLPI})
FOLDER_GLPI=glpi/
FOLDER_WEB=/var/www/html/

#check if TLS_REQCERT is present
if !(grep -q "TLS_REQCERT" /etc/ldap/ldap.conf)
then
	echo "TLS_REQCERT isn't present"
    echo -e "TLS_REQCERT\tnever" >> /etc/ldap/ldap.conf
fi

#Téléchargement et extraction des sources de GLPI
if [ "$(ls ${FOLDER_WEB}${FOLDER_GLPI})" ];
then
	echo "GLPI is already installed"
else
	wget -P ${FOLDER_WEB} ${SRC_GLPI}
	tar -xzf ${FOLDER_WEB}${TAR_GLPI} -C ${FOLDER_WEB}
	rm -Rf ${FOLDER_WEB}${TAR_GLPI}
	chown -R www-data:www-data ${FOLDER_WEB}${FOLDER_GLPI}
fi

#Modification du vhost par défaut
echo -e '<VirtualHost *:80>\n\tDocumentRoot /var/www/html/glpi/\n\tServerName glpi-test.omniphar.com\n\tServerAlias assistance.omniphar.com\n\tRedirect / https://glpi.omniphar.com/\n\t###\n\tErrorLog ${APACHE_LOG_DIR}/error.log\n\tCustomLog ${APACHE_LOG_DIR}/access.log combined\n</VirtualHost>\n<VirtualHost *:80>\n\tDocumentRoot /var/www/html/glpi/\n\tServerName agent.omniphar.com\n\t#Redirect / https://agent.omniphar.com\n\t###\n\tErrorLog ${APACHE_LOG_DIR}/error.log\n\tCustomLog ${APACHE_LOG_DIR}/access.log combined\n</VirtualHost>' > /etc/apache2/sites-available/000-default.conf
echo -e "[libdefaults]\n\tdefault_realm = OMNIPHAR.LAN\n\tdns_lookup_realm = true\n\tdns_lookup_kdc = false\n\tdefault_keytab_name = FILE:/etc/kerberos.keytab\n\tkdc_timesync = 1\n\tccache_type = 4\n\tforwardable = true\n\tproxiable = true\n\tfcc-mit-ticketflags = true\n\n[realms]\n\tOMNIPHAR.LAN = {\n\t\tkdc = SRV-AD2016.OMNIPHAR.LAN\n\t\tkdc = OMNI-AD-001.OMNIPHAR.LAN\n\t\tadmin_server = SRV-AD2016.OMNIPHAR.LAN\n\t}\n[domain_realm]\n\t.omniphar.com = OMNIPHAR.LAN\n\tomniphar.com = OMNIPHAR.LAN\n\n\t.omniphar.lan = OMNIPHAR.LAN\n\tomniphar.lan = OMNIPHAR.LAN" > /etc/krb5.conf

#Add scheduled task by cron and enable
echo "*/2 * * * * www-data /usr/bin/php /var/www/html/glpi/front/cron.php &>/dev/null" >> /etc/cron.d/glpi
#Start cron service
service cron start

#Activation du module rewrite d'apache
a2enmod rewrite && service apache2 restart && service apache2 stop

#Lancement du service apache au premier plan
/usr/sbin/apache2ctl -D FOREGROUND
