dockremapUIDRangeStart=${1:-165536}
dockremapGIDRangeStart=${2:-165536}
ContainerUID=${3:-5000}
ContainerGID=${4:-5000}

mkdir -p cloudflared

cat <<EOF > ./cloudflared/vault-tunnel-cred.json
EOF

cat <<EOF > ./cloudflared/config.yml
tunnel: vault
credentials-file: /etc/cloudflared/vault-tunnel-cred.json
EOF

### COMMON VARIABLES, used while creating .env files and to update fail2ban jail  ########
GCPTimeZone=
InteractiveDockerUser=

#DOMAIN - used by vaultwarden, caddy, and fail2ban
DOMAIN=
APP_PATH=
INSTANCE_2_DOMAIN=
INSTANCE_2_APP_PATH=securesafe

SMTP_HOST=smtp.gmail.com
SMTP_VAULTWARDEN_FROM_ID=
SMTP_FROM_DOMAIN=
SMTP_PORT=587
SMTP_SECURITY=starttls
SMTP_USERNAME=
SMTP_PASSWORD=

# Timezone - used by some containers for logs / cron
# Find your location on this list and use the value in TZ Database Name, e.g Europe/Rome:
#   https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TZ=

fail2ban_email_recipient=
fail2ban_email_sender=
fail2ban_email_sendername=

cf_account_identifier=
cf_list_id=
cftoken=

cat <<EOF > .env
# vim: syntax=ini
# variables directly used in docker-compose file should be defined here
# variables used within containers can be defined in the env_file

ContainerUID=${ContainerUID}
ContainerGID=${ContainerGID}

EOF

cat <<EOF > .env.egress-proxy
# vim: syntax=ini

SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}

EOF

cat <<EOF > .env.vaultwarden
# vim: syntax=ini

## Vaultwarden Configuration File
##
## Be aware that most of these settings will be overridden if they were changed
## in the admin interface. Those overrides are stored within DATA_FOLDER/config.json .

## Client IP Header, used to identify the IP of the client, defaults to "X-Real-IP"
## Set to the string "none" (without quotes), to disable any headers and just use the remote IP
IP_HEADER=X-Forwarded-For

## Enables websocket notifications
WEBSOCKET_ENABLED=true            # required for websockets

## Log level
## Change the verbosity of the log output
## Valid values are "trace", "debug", "info", "warn", "error" and "off"
## Setting it to "trace" or "debug" would also show logs for mounted
## routes and static file, websocket and alive requests
# LOG_LEVEL=Info

## Disable icon downloading
## Set to true to disable icon downloading, this would still serve icons from $ICON_CACHE_FOLDER,
## but it won't produce any external network request. Needs to set $ICON_CACHE_TTL to 0,
## otherwise it will delete them and they won't be downloaded again.
DISABLE_ICON_DOWNLOAD=true

## Controls if new users can register
SIGNUPS_ALLOWED=false

## Controls if new users need to verify their email address upon registration
## Note that setting this option to true prevents logins until the email address has been verified!
## The welcome email will include a verification link, and login attempts will periodically
## trigger another verification email to be sent.
SIGNUPS_VERIFY=true

## Controls if new users from a list of comma-separated domains can register
## even if SIGNUPS_ALLOWED is set to false
SIGNUPS_DOMAINS_WHITELIST=

## Controls whether a password hint should be shown directly in the web page if
## SMTP service is not configured. Not recommended for publicly-accessible instances
## as this provides unauthenticated access to potentially sensitive data.
SHOW_PASSWORD_HINT=false

## Domain settings
## The domain must match the address from where you access the server
## It's recommended to configure this value, otherwise certain functionality might not work,
## like attachment downloads, email links and U2F.
## For U2F to work, the server must use HTTPS, you can use Let's Encrypt for free certs
DOMAIN=https://${DOMAIN}/${APP_PATH}

## Yubico (Yubikey) Settings
## Set your Client ID and Secret Key for Yubikey OTP
## You can generate it here: https://upgrade.yubico.com/getapikey/
## You can optionally specify a custom OTP server
# YUBICO_CLIENT_ID=11111
# YUBICO_SECRET_KEY=AAAAAAAAAAAAAAAAAAAAAAAA
# YUBICO_SERVER=http://yourdomain.com/wsapi/2.0/verify

## Duo Settings
## You need to configure all options to enable global Duo support, otherwise users would need to configure it themselves
## Create an account and protect an application as mentioned in this link (only the first step, not the rest):
## https://help.bitwarden.com/article/setup-two-step-login-duo/#create-a-duo-security-account
## Then set the following options, based on the values obtained from the last step:
# DUO_IKEY=<Integration Key>
# DUO_SKEY=<Secret Key>
# DUO_HOST=<API Hostname>
## After that, you should be able to follow the rest of the guide linked above,
## ignoring the fields that ask for the values that you already configured beforehand.

_ENABLE_DUO=
DUO_IKEY=
DUO_SKEY=
DUO_HOST=

HTTP_REQUEST_BLOCK_NON_GLOBAL_IPS=false

## Authenticator Settings
## Disable authenticator time drifted codes to be valid.
## TOTP codes of the previous and next 30 seconds will be invalid
##
## According to the RFC6238 (https://tools.ietf.org/html/rfc6238),
## we allow by default the TOTP code which was valid one step back and one in the future.
## This can however allow attackers to be a bit more lucky with there attempts because there are 3 valid codes.
## You can disable this, so that only the current TOTP Code is allowed.
## Keep in mind that when a sever drifts out of time, valid codes could be marked as invalid.
## In any case, if a code has been used it can not be used again, also codes which predates it will be invalid.
# AUTHENTICATOR_DISABLE_TIME_DRIFT=false

## Mail specific settings, set SMTP_HOST and SMTP_FROM to enable the mail service.
## To make sure the email links are pointing to the correct host, set the DOMAIN variable.
## Note: if SMTP_USERNAME is specified, SMTP_PASSWORD is mandatory

SMTP_FROM=${SMTP_VAULTWARDEN_FROM_ID}@${SMTP_FROM_DOMAIN}
SMTP_FROM_NAME=Vaultwarden (${DOMAIN})

# SMTP_PORT=587          # Ports 587 (submission) and 25 (smtp) are standard without encryption and with encryption via STARTTLS (Explicit TLS). Port 465 is outdated and used with Implicit TLS.
# SMTP_SSL=true          # (Explicit) - This variable by default configures Explicit STARTTLS, it will upgrade an insecure connection to a secure one. Unless SMTP_EXPLICIT_TLS is set to true. Either port 587 or 25 are default.
# SMTP_EXPLICIT_TLS=true # (Implicit) - N.B. This variable configures Implicit TLS. It's currently mislabelled (see bug #851) - SMTP_SSL Needs to be set to true for this option to work. Usually port 465 is used here.

SMTP_HOST=${SMTP_HOST}
SMTP_VAULTWARDEN_FROM_ID=${SMTP_VAULTWARDEN_FROM_ID}
SMTP_FROM_DOMAIN=${SMTP_FROM_DOMAIN}
SMTP_PORT=${SMTP_PORT}
SMTP_SECURITY=${SMTP_SECURITY}
SMTP_USERNAME=${SMTP_USERNAME}
SMTP_PASSWORD=${SMTP_PASSWORD}

## Defaults for SSL is "Plain" and "Login" and nothing for Non-SSL connections.
## Possible values: ["Plain", "Login", "Xoauth2"].
## Multiple options need to be separated by a comma ','.
# SMTP_AUTH_MECHANISM="Plain"

## Server name sent during the SMTP HELO
## By default this value should be is on the machine's hostname,
## but might need to be changed in case it trips some anti-spam filters
# HELO_NAME=

## SMTP debugging
## When set to true this will output very detailed SMTP messages.
## WARNING: This could contain sensitive information like passwords and usernames! Only enable this during troubleshooting!
# SMTP_DEBUG=false

## Accept Invalid Hostnames
## DANGEROUS: This option introduces significant vulnerabilities to man-in-the-middle attacks!
## Only use this as a last resort if you are not able to use a valid certificate.
# SMTP_ACCEPT_INVALID_HOSTNAMES=false

## Accept Invalid Certificates
## DANGEROUS: This option introduces significant vulnerabilities to man-in-the-middle attacks!
## Only use this as a last resort if you are not able to use a valid certificate.
## If the Certificate is valid but the hostname doesn't match, please use SMTP_ACCEPT_INVALID_HOSTNAMES instead.
# SMTP_ACCEPT_INVALID_CERTS=false

## Require new device emails. When a user logs in an email is required to be sent.
## If sending the email fails the login attempt will fail!!
# REQUIRE_DEVICE_EMAIL=false

## HIBP Api Key
## HaveIBeenPwned API Key, request it here: https://haveibeenpwned.com/API/Key
HIBP_API_KEY=

#using cloudflare rules to redirect icon requests (actually using google icon service there), we do not need to use ICON_SERVICE here
#ICON_SERVICE=google

TZ=${TZ}

EOF

cat <<EOF > .env.vaultwarden-instance_2
# vim: syntax=ini

## Vaultwarden Configuration File
##
## Be aware that most of these settings will be overridden if they were changed
## in the admin interface. Those overrides are stored within DATA_FOLDER/config.json .

## Client IP Header, used to identify the IP of the client, defaults to "X-Real-IP"
## Set to the string "none" (without quotes), to disable any headers and just use the remote IP
IP_HEADER=X-Forwarded-For

## Enables websocket notifications
WEBSOCKET_ENABLED=true            # required for websockets

## Log level
## Change the verbosity of the log output
## Valid values are "trace", "debug", "info", "warn", "error" and "off"
## Setting it to "trace" or "debug" would also show logs for mounted
## routes and static file, websocket and alive requests
# LOG_LEVEL=Info

## Disable icon downloading
## Set to true to disable icon downloading, this would still serve icons from $ICON_CACHE_FOLDER,
## but it won't produce any external network request. Needs to set $ICON_CACHE_TTL to 0,
## otherwise it will delete them and they won't be downloaded again.
DISABLE_ICON_DOWNLOAD=true

## Controls if new users can register
SIGNUPS_ALLOWED=false

## Controls if new users need to verify their email address upon registration
## Note that setting this option to true prevents logins until the email address has been verified!
## The welcome email will include a verification link, and login attempts will periodically
## trigger another verification email to be sent.
SIGNUPS_VERIFY=true

## Controls if new users from a list of comma-separated domains can register
## even if SIGNUPS_ALLOWED is set to false
SIGNUPS_DOMAINS_WHITELIST=gmail.com

## Controls whether a password hint should be shown directly in the web page if
## SMTP service is not configured. Not recommended for publicly-accessible instances
## as this provides unauthenticated access to potentially sensitive data.
SHOW_PASSWORD_HINT=false

## Domain settings
## The domain must match the address from where you access the server
## It's recommended to configure this value, otherwise certain functionality might not work,
## like attachment downloads, email links and U2F.
## For U2F to work, the server must use HTTPS, you can use Let's Encrypt for free certs
DOMAIN=https://${INSTANCE_2_DOMAIN}/${INSTANCE_2_APP_PATH}

## Yubico (Yubikey) Settings
## Set your Client ID and Secret Key for Yubikey OTP
## You can generate it here: https://upgrade.yubico.com/getapikey/
## You can optionally specify a custom OTP server
# YUBICO_CLIENT_ID=11111
# YUBICO_SECRET_KEY=AAAAAAAAAAAAAAAAAAAAAAAA
# YUBICO_SERVER=http://yourdomain.com/wsapi/2.0/verify

## Duo Settings
## You need to configure all options to enable global Duo support, otherwise users would need to configure it themselves
## Create an account and protect an application as mentioned in this link (only the first step, not the rest):
## https://help.bitwarden.com/article/setup-two-step-login-duo/#create-a-duo-security-account
## Then set the following options, based on the values obtained from the last step:
# DUO_IKEY=<Integration Key>
# DUO_SKEY=<Secret Key>
# DUO_HOST=<API Hostname>
## After that, you should be able to follow the rest of the guide linked above,
## ignoring the fields that ask for the values that you already configured beforehand.

_ENABLE_DUO=false
DUO_IKEY=
DUO_SKEY=
DUO_HOST=api-f5fbcbd9.duosecurity.com

## Authenticator Settings
## Disable authenticator time drifted codes to be valid.
## TOTP codes of the previous and next 30 seconds will be invalid
##
## According to the RFC6238 (https://tools.ietf.org/html/rfc6238),
## we allow by default the TOTP code which was valid one step back and one in the future.
## This can however allow attackers to be a bit more lucky with there attempts because there are 3 valid codes.
## You can disable this, so that only the current TOTP Code is allowed.
## Keep in mind that when a sever drifts out of time, valid codes could be marked as invalid.
## In any case, if a code has been used it can not be used again, also codes which predates it will be invalid.
# AUTHENTICATOR_DISABLE_TIME_DRIFT=false

## Mail specific settings, set SMTP_HOST and SMTP_FROM to enable the mail service.
## To make sure the email links are pointing to the correct host, set the DOMAIN variable.
## Note: if SMTP_USERNAME is specified, SMTP_PASSWORD is mandatory

SMTP_FROM=${SMTP_VAULTWARDEN_FROM_ID}@${SMTP_FROM_DOMAIN}
SMTP_FROM_NAME=Vaultwarden (${INSTANCE_2_DOMAIN})

# SMTP_PORT=587          # Ports 587 (submission) and 25 (smtp) are standard without encryption and with encryption via STARTTLS (Explicit TLS). Port 465 is outdated and used with Implicit TLS.
# SMTP_SSL=true          # (Explicit) - This variable by default configures Explicit STARTTLS, it will upgrade an insecure connection to a secure one. Unless SMTP_EXPLICIT_TLS is set to true. Either port 587 or 25 are default.
# SMTP_EXPLICIT_TLS=true # (Implicit) - N.B. This variable configures Implicit TLS. It's currently mislabelled (see bug #851) - SMTP_SSL Needs to be set to true for this option to work. Usually port 465 is used here.

SMTP_HOST=${SMTP_HOST}
SMTP_VAULTWARDEN_FROM_ID=${SMTP_VAULTWARDEN_FROM_ID}
SMTP_FROM_DOMAIN=${SMTP_FROM_DOMAIN}
SMTP_PORT=${SMTP_PORT}
SMTP_SECURITY=${SMTP_SECURITY}
SMTP_USERNAME=${SMTP_USERNAME}
SMTP_PASSWORD=${SMTP_PASSWORD}

## Defaults for SSL is "Plain" and "Login" and nothing for Non-SSL connections.
## Possible values: ["Plain", "Login", "Xoauth2"].
## Multiple options need to be separated by a comma ','.
# SMTP_AUTH_MECHANISM="Plain"

## Server name sent during the SMTP HELO
## By default this value should be is on the machine's hostname,
## but might need to be changed in case it trips some anti-spam filters
# HELO_NAME=

## SMTP debugging
## When set to true this will output very detailed SMTP messages.
## WARNING: This could contain sensitive information like passwords and usernames! Only enable this during troubleshooting!
# SMTP_DEBUG=false

## Accept Invalid Hostnames
## DANGEROUS: This option introduces significant vulnerabilities to man-in-the-middle attacks!
## Only use this as a last resort if you are not able to use a valid certificate.
# SMTP_ACCEPT_INVALID_HOSTNAMES=false

## Accept Invalid Certificates
## DANGEROUS: This option introduces significant vulnerabilities to man-in-the-middle attacks!
## Only use this as a last resort if you are not able to use a valid certificate.
## If the Certificate is valid but the hostname doesn't match, please use SMTP_ACCEPT_INVALID_HOSTNAMES instead.
# SMTP_ACCEPT_INVALID_CERTS=false

## Require new device emails. When a user logs in an email is required to be sent.
## If sending the email fails the login attempt will fail!!
# REQUIRE_DEVICE_EMAIL=false

## HIBP Api Key
## HaveIBeenPwned API Key, request it here: https://haveibeenpwned.com/API/Key
HIBP_API_KEY=

#using cloudflare rules to redirect icon requests (actually using google icon service there), we do not need to use ICON_SERVICE here
#ICON_SERVICE=google

TZ=${TZ}

EOF

cat <<EOF > .env.cloudflared
# vim: syntax=ini
### Cloudflared VARIABLES ###

#uncomment below line and paste online tunnel token here if you want to setup tunnel online,
#there will be some work on cloudflare portal
#TUNNEL_TOKEN=

EOF

cat <<EOF > .env.fail2ban
# vim: syntax=ini
### FAIL2BAN VARIABLES ###

F2B_DB_PURGE_AGE=30d
F2B_LOG_LEVEL=INFO
SSMTP_HOST=${SMTP_HOST}
SSMTP_PORT=${SMTP_PORT}
SSMTP_USER=${SMTP_USERNAME}
SSMTP_PASSWORD=${SMTP_PASSWORD}
SSMTP_HOSTNAME=Vaultwarden (${DOMAIN})
SSMTP_TLS=YES
SSMTP_STARTTLS=YES

TZ=${TZ}

EOF

cat <<EOF > gitconfig.sh
git config --global user.email "$GitHubUserEmailId"
git config --global user.name $GitHubUserFullName"
EOF

#do NOT escape curly braces here
sed -i "s/{dockremapUIDRangeStart}/$dockremapUIDRangeStart/g" cloud-config.yaml
sed -i "s/{dockremapGIDRangeStart}/$dockremapGIDRangeStart/g" cloud-config.yaml
sed -i "s/{GCPTimeZone}/$GCPTimeZone/g" cloud-config.yaml
sed -i "s/{InteractiveDockerUser}/$InteractiveDockerUser/g" cloud-config.yaml

#do escape curly braces here, not sure why
sed -i "s/^#\{0,1\}destemail\s\{0,1\}=.*$/destemail = ${fail2ban_email_recipient}/g" fail2ban/jail.d/jail.local
sed -i "s/^#\{0,1\}sender\s\{0,1\}=.*$/sender = ${fail2ban_email_sender}/g" fail2ban/jail.d/jail.local
sed -i "s/^#\{0,1\}sendername\s\{0,1\}=.*$/sendername = ${fail2ban_email_sendername}/g" fail2ban/jail.d/jail.local

sed -i "s/^#\{0,1\}cf_account_identifier.*$/cf_account_identifier = ${cf_account_identifier}/g" fail2ban/action.d/cloudflare-iplist.conf
sed -i "s/^#\{0,1\}cf_list_id.*$/cf_list_id = ${cf_list_id}/g" fail2ban/action.d/cloudflare-iplist.conf
sed -i "s/^#\{0,1\}cftoken.*$/cftoken = ${cftoken}/g" fail2ban/action.d/cloudflare-iplist.conf