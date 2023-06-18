#!/bin/bash

# Hestia Control Panel upgrade script for target version 1.7.8

#######################################################################################
#######                      Place additional commands below.                   #######
#######################################################################################
####### upgrade_config_set_value only accepts true or false.                    #######
#######                                                                         #######
####### Pass through information to the end user in case of a issue or problem  #######
#######                                                                         #######
####### Use add_upgrade_message "My message here" to include a message          #######
####### in the upgrade notification email. Example:                             #######
#######                                                                         #######
####### add_upgrade_message "My message here"                                   #######
#######                                                                         #######
####### You can use \n within the string to create new lines.                   #######
#######################################################################################

upgrade_config_set_value 'UPGRADE_UPDATE_WEB_TEMPLATES' 'false'
upgrade_config_set_value 'UPGRADE_UPDATE_DNS_TEMPLATES' 'false'
upgrade_config_set_value 'UPGRADE_UPDATE_MAIL_TEMPLATES' 'false'
upgrade_config_set_value 'UPGRADE_REBUILD_USERS' 'false'
upgrade_config_set_value 'UPGRADE_UPDATE_FILEMANAGER_CONFIG' 'false'

# Hotfix for NGINX http2 directive issue
cat << "EOF" > "$BIN"/v-hotfix-nginx-http2-directive-issue
#!/bin/bash
# info: hotfix nginx http2 directive issue

# Includes
# shellcheck source=/etc/hestiacp/hestia.conf
source /etc/hestiacp/hestia.conf
# shellcheck source=/usr/local/hestia/func/main.sh
source "$HESTIA"/func/main.sh
# load config file
source_conf "$HESTIA/conf/hestia.conf"

update_nginx() {
	export DEBIAN_FRONTEND="noninteractive" DEBCONF_NONINTERACTIVE_SEEN="true"
	apt-get -qq update > /dev/null 2>&1 || exit
	apt-get -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install nginx > /dev/null 2>&1 || exit
	"$BIN"/v-log-action "system" "Info" "Hotfix" "Upgraded NGINX to the latest version."
}

update_conf() {
	echo "http2 on; # Temporary implementation" > /etc/nginx/conf.d/http2-directive.conf

	while IFS= read -r IPCONF; do
		grep -qw "ssl http2 default;" "$IPCONF" 2> /dev/null && sed -i "s/ssl http2 default;/ssl default;/g" "$IPCONF"
		grep -qw "ssl http2;" "$IPCONF" 2> /dev/null && sed -i "s/ssl http2;/ssl;/g" "$IPCONF"
		sed -i "/http2[ ]*on;/d" "$IPCONF"
	done < <(find /etc/nginx/conf.d -regex ".*/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.conf" -type f)

	while IFS= read -r STPL; do
		grep -qw "ssl http2;" "$STPL" 2> /dev/null && sed -i "s/ssl http2;/ssl;/g" "$STPL"
		sed -i "/http2[ ]*on;/d" "$STPL"
	done < <(find "$HESTIA"/data/templates/*/nginx -name "*.stpl" -type f)

	"$BIN"/v-rebuild-web-domains admin no
	"$BIN"/v-rebuild-mail-domains admin
	"$BIN"/v-restart-service nginx reload && "$BIN"/v-log-action "system" "Info" "Hotfix" "NGINX http2 directive issue has been fixed."
}

remove_job() {
	job_id="$("$BIN"/v-list-cron-jobs admin | grep v-hotfix-nginx-http2-directive-issue | awk '{print $1}')"
	[ -n "$job_id" ] && "$BIN"v-delete-cron-job admin "$job_id" "yes"
}

if ! dpkg -l | grep -q "^ii[ ]*nginx[ ]*"; then
	remove_job
	exit 0
fi

if version_ge "$(nginx -v 2>&1 | cut -d'/' -f2)" "1.25.1"; then
	update_conf
	remove_job
else
	update_nginx
	update_conf
	remove_job
fi
EOF

chmod +x "$BIN"/v-hotfix-nginx-http2-directive-issue

"$BIN"/v-add-cron-job admin "51" "*" "*" "*" "*" "sudo $BIN/v-hotfix-nginx-http2-directive-issue" "" "yes"
