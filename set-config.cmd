#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

:: Configuring application
den env exec -T php-fpm bin/magento app:config:import

if [ ! -f "${WARDEN_ENV_PATH}/app/etc/config.php" ]; then
    :: Enabling all modules
    den env exec -T php-fpm bin/magento module:enable --all
fi

if [[ "$WARDEN_ELASTICSEARCH" -eq "1" ]] || [[ "$WARDEN_OPENSEARCH" -eq "1" ]]; then
    :: Configuring ElasticSearch
    ELASTICSEARCH_HOSTNAME="elasticsearch"
    if [[ "$WARDEN_OPENSEARCH" ]]; then
        ELASTICSEARCH_HOSTNAME="opensearch"
    fi

    den env exec -T php-fpm bin/magento config:set --lock-env catalog/search/engine elasticsearch7
    den env exec -T php-fpm bin/magento config:set --lock-env catalog/search/elasticsearch7_server_hostname $ELASTICSEARCH_HOSTNAME
    den env exec -T php-fpm bin/magento config:set --lock-env catalog/search/elasticsearch7_server_port 9200
    den env exec -T php-fpm bin/magento config:set --lock-env catalog/search/elasticsearch7_index_prefix magento2
    den env exec -T php-fpm bin/magento config:set --lock-env catalog/search/elasticsearch7_enable_auth 0
    den env exec -T php-fpm bin/magento config:set --lock-env catalog/search/elasticsearch7_server_timeout 15
fi

if [[ "$WARDEN_REDIS" -eq "1" ]]; then
    :: Configuring Redis
    den env exec -T php-fpm bin/magento setup:config:set --cache-backend=redis --cache-backend-redis-server=redis --cache-backend-redis-db=0 --cache-backend-redis-port=6379 --no-interaction
    den env exec -T php-fpm bin/magento setup:config:set --page-cache=redis --page-cache-redis-server=redis --page-cache-redis-db=1 --page-cache-redis-port=6379 --no-interaction
    den env exec -T php-fpm bin/magento setup:config:set --session-save=redis --session-save-redis-host=redis --session-save-redis-max-concurrency=20 --session-save-redis-db=2 --session-save-redis-port=6379 --no-interaction
fi

:: Installing application
den env exec -T php-fpm bin/magento setup:upgrade

den db connect -e "UPDATE core_config_data SET value = 'https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/' WHERE path IN('web/secure/base_url','web/unsecure/base_url','web/unsecure/base_link_url','web/secure/base_link_url')"
den db connect -e "UPDATE core_config_data SET value = 'dev_$((1000 + $RANDOM % 10000))' WHERE path = 'algoliasearch_credentials/credentials/index_prefix'"
den env exec -T php-fpm bin/magento config:set --lock-env web/unsecure/base_url "https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"
den env exec -T php-fpm bin/magento config:set --lock-env web/secure/base_url "https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"

den env exec -T php-fpm bin/magento deploy:mode:set -s developer
#den env exec -T php-fpm bin/magento app:config:dump themes scopes i18n

:: Other configuration
den env exec -T php-fpm bin/magento config:set --lock-env admin/url/use_custom 0 || true
den env exec -T php-fpm bin/magento config:set --lock-env admin/security/password_is_forced 0 || true
den env exec -T php-fpm bin/magento config:set --lock-env admin/security/admin_account_sharing 1 || true
den env exec -T php-fpm bin/magento config:set --lock-env admin/security/session_lifetime 31536000 || true
den env exec -T php-fpm bin/magento config:set --lock-env web/secure/offloader_header X-Forwarded-Proto || true
den env exec -T php-fpm bin/magento config:set payment/checkmo/active 1 || true

if [[ "$WARDEN_VARNISH" -eq "1" ]]; then
    :: Configuring Varnish
    den env exec -T php-fpm bin/magento setup:config:set --http-cache-hosts=varnish
    den env exec -T php-fpm bin/magento config:set --lock-env system/full_page_cache/varnish/backend_host varnish
    den env exec -T php-fpm bin/magento config:set --lock-env system/full_page_cache/varnish/backend_port 80
    den env exec -T php-fpm bin/magento config:set --lock-env system/full_page_cache/caching_application 2
    den env exec -T php-fpm bin/magento config:set --lock-env system/full_page_cache/ttl 604800
else
    den env exec -T php-fpm bin/magento config:set --lock-env system/full_page_cache/caching_application 1
fi

:: Flushing cache
den env exec -T php-fpm bin/magento cache:flush
#den env exec -T php-fpm bin/magento cache:disable block_html full_page

if [[ "$WARDEN_PWA" -eq "1" ]]; then
    :: Configuring PWA theme
    if [ ! -d "${WARDEN_ENV_PATH}/${WARDEN_PWA_PATH}" ]; then
        git clone -b ${WARDEN_PWA_GIT_BRANCH} ${WARDEN_PWA_GIT_REMOTE} ${WARDEN_ENV_PATH}/${WARDEN_PWA_PATH}
    fi

    cat <<EOT > "${WARDEN_ENV_PATH}/${WARDEN_PWA_PATH}/.env"
MAGENTO_BACKEND_URL=https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/
MAGENTO_BACKEND_EDITION=CE
CHECKOUT_BRAINTREE_TOKEN=sandbox_8yrzsvtm_s2bg8fs563crhqzk
EOT

    node /usr/share/yarn/bin/yarn.js --cwd ${WARDEN_ENV_PATH}/${WARDEN_PWA_PATH} --ignore-optional || true
    node /usr/share/yarn/bin/yarn.js --cwd ${WARDEN_ENV_PATH}/${WARDEN_PWA_PATH} build || true

    den env exec -T php-fpm bin/magento config:set web/upward/enabled 1 || true
    den env exec -T php-fpm bin/magento config:set web/upward/path /var/www/html/${WARDEN_PWA_UPWARD_PATH} || true
    den env exec -T php-fpm bin/magento cache:flush
fi
