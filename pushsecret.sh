sed -i.bak 's/\r$//' writeconfig.sh
gcloud secrets versions add vault-config-script --data-file=writeconfig.sh
