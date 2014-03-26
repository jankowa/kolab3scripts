#!/bin/bash

###########################################
# Enable Alias-Domains for specific domains
###########################################


primaryDomain="example.com" # the primary domain
aliasEnabledDomains="example.com example2.com" # list of domains 

# generate configs for each domain which should have aliases

serviceBindPw=$(grep ^service_bind_pw /etc/kolab/kolab.conf | cut -d ' ' -f3-)
configPath="/etc/postfix/ldap"


for mydomain in $aliasEnabledDomains; do

	# generate the dn out of domain-name
	OLD_IFS=$IFS
	IFS="."
	domainDnPart=""
	for i in $mydomain; do
		domainDnPart=$domainDnPart'dc='$i","
	done
	# Deleting the  "\" from the last domain Component
	domainDn=$(echo $domainDnPart | sed -e 's/,$//g')
	IFS=$OLD_IFS
	
	# generate the basedn out of domain-name
	OLD_IFS=$IFS
	IFS="."
	domainDnPart=""
	for i in $primaryDomain; do
		domainDnPart=$domainDnPart'dc='$i","
	done
	# Deleting the  "\" from the last domain Component
	baseDn=$(echo $domainDnPart | sed -e 's/,$//g')
	IFS=$OLD_IFS

# make subdirs for domain
test -d $configPath/$mydomain && echo "For $mydomain there is allready a configuration. Please check."
test -d $configPath/$mydomain && continue
mkdir $configPath/$mydomain

# mydestination.cf
cat << EOF >> $configPath/$mydomain/mydestination.cf
server_host = localhost
server_port = 389
version = 3
search_base = cn=kolab,cn=config
scope = sub

bind_dn = uid=kolab-service,ou=Special Users,$baseDn
bind_pw = $serviceBindPw

query_filter = (&(associatedDomain=%s)(associatedDomain=$mydomain))
result_attribute = associateddomain
EOF

# local_recipient_maps.cf
cat << EOF >> $configPath/$mydomain/local_recipient_maps.cf
server_host = localhost
server_port = 389
version = 3
search_base = cn=kolab,cn=config
scope = sub

domain = ldap:$configPath/$mydomain/mydestination.cf

bind_dn = uid=kolab-service,ou=Special Users,$baseDn
bind_pw = $serviceBindPw

query_filter = (&(|(mail=%s)(alias=%s))(|(objectclass=kolabinetorgperson)(|(objectclass=kolabgroupofuniquenames)(objectclass=kolabgroupofurls))(|(|(objectclass=groupofuniquenames)(objectclass=groupofurls))(objectclass=kolabsharedfolder))(objectclass=kolabsharedfolder)))
result_attribute = mail
EOF

# virtual_alias_maps.cf
cat << EOF >> $configPath/$mydomain/virtual_alias_maps.cf
server_host = localhost
server_port = 389
version = 3
search_base = $domainDn
scope = sub

domain = ldap:$configPath/$mydomain/mydestination.cf

bind_dn = uid=kolab-service,ou=Special Users,$baseDn
bind_pw = $serviceBindPw

query_filter = (&(|(mail=%s)(alias=%s))(objectclass=kolabinetorgperson))
result_attribute = mail
EOF


# edit postfix main.cf to enable the above configs
# quick test avoiding adding the configs second time
if ! grep $mydomain /etc/postfix/main.cf > /dev/null 2>&1; then 
	sed -i 	-e 's#^local_recipient_maps = .*#&,'ldap:$configPath/$mydomain'/local_recipient_maps.cf#g'\
		-e 's#^virtual_alias_maps = .*#&,'ldap:$configPath/$mydomain'/virtual_alias_maps.cf#g'\
		/etc/postfix/main.cf
	else
	  echo "Maybe the domain is allready enabled for aliases. Check the main.cf" 
fi

done

service postfix restart
