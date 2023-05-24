#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

START_TIME=$(date +%s)
SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

## configure command defaults
REQUIRED_FILES=("${WARDEN_ENV_PATH}/auth.json")
AUTO_PULL=1
DB_DUMP=
DB_IMPORT=1
MEDIA_SYNC=1
COMPOSER_INSTALL=1
ADMIN_CREATE=1
BASE_ENV=dev

## argument parsing
## parse arguments
while (( "$#" )); do
    case "$1" in
        --no-pull)
            AUTO_PULL=
            shift
            ;;
        --skip-db-import)
            DB_IMPORT=
            shift
            ;;
        --skip-media-sync)
            MEDIA_SYNC=
            shift
            ;;
        --skip-composer-install)
            COMPOSER_INSTALL=
            shift
            ;;
        --skip-admin-create)
            ADMIN_CREATE=
            shift
            ;;
        --db-dump)
            shift
            DB_DUMP="$1"
            shift
            ;;
        -e|--environment)
            shift
            BASE_ENV=$(echo "$1" | tr '[:upper:]' '[:lower:]')
            shift
            ;;
        *)
            error "Unrecognized argument '$1'"
            exit -1
            ;;
    esac
done

if [ ! -f "${WARDEN_ENV_PATH}/app/etc/env.php" ]; then
    cat <<EOT > "${WARDEN_ENV_PATH}/app/etc/env.php"
<?php
return [
    'backend' => [
        'frontName' => 'admin'
    ],
    'crypt' => [
        'key' => '00000000000000000000000000000000'
    ],
    'db' => [
        'table_prefix' => '',
        'connection' => [
            'default' => [
                'host' => 'db',
                'dbname' => 'magento',
                'username' => 'magento',
                'password' => 'magento',
                'active' => '1'
            ]
        ]
    ],
    'resource' => [
        'default_setup' => [
            'connection' => 'default'
        ]
    ],
    'x-frame-options' => 'SAMEORIGIN',
    'MAGE_MODE' => 'developer',
    'session' => [
        'save' => 'files'
    ],
    'cache_types' => [
        'config' => 1,
        'layout' => 1,
        'block_html' => 0,
        'collections' => 1,
        'reflection' => 1,
        'db_ddl' => 1,
        'compiled_config' => 1,
        'eav' => 1,
        'customer_notification' => 1,
        'config_integration' => 1,
        'config_integration_api' => 1,
        'full_page' => 0,
        'config_webservice' => 1,
        'translate' => 1
    ],
    'install' => [
        'date' => 'Mon, 01 May 2023 00:00:00 +0000'
    ]
];

EOT
fi

## include check for DB_DUMP file only when database import is expected
[[ ${DB_IMPORT} ]] && [[ "$DB_DUMP" ]] && REQUIRED_FILES+=("${DB_DUMP}")

:: Verifying configuration
INIT_ERROR=

## attempt to install mutagen if not already present
if [[ $OSTYPE =~ ^darwin ]] && ! which mutagen >/dev/null 2>&1 && which brew >/dev/null 2>&1; then
    warning "Mutagen could not be found; attempting install via brew."
    brew install havoc-io/mutagen/mutagen
fi

## check for presence of host machine dependencies
for DEP_NAME in den mutagen docker-compose pv; do
    if [[ "${DEP_NAME}" = "mutagen" ]] && [[ ! $OSTYPE =~ ^darwin ]]; then
        continue
    fi

    if ! which "${DEP_NAME}" 2>/dev/null >/dev/null; then
        error "Command '${DEP_NAME}' not found. Please install."
        INIT_ERROR=1
    fi
done

## verify mutagen version constraint
MUTAGEN_VERSION=$(mutagen version 2>/dev/null) || true
MUTAGEN_REQUIRE=0.11.4
if [[ $OSTYPE =~ ^darwin ]] && ! test $(version ${MUTAGEN_VERSION}) -ge $(version ${MUTAGEN_REQUIRE}); then
    error "Mutagen ${MUTAGEN_REQUIRE} or greater is required (version ${MUTAGEN_VERSION} is installed)"
    INIT_ERROR=1
fi

## check for presence of local configuration files to ensure they exist
for REQUIRED_FILE in ${REQUIRED_FILES[@]}; do
    if [[ ! -f "${REQUIRED_FILE}" ]]; then
        error "Missing local file: ${REQUIRED_FILE}"
        INIT_ERROR=1
    fi
done

## exit script if there are any missing dependencies or configuration files
[[ ${INIT_ERROR} ]] && exit 1

:: Starting Den
den svc up
if [[ ! -f ~/.den/ssl/certs/${TRAEFIK_DOMAIN}.crt.pem ]]; then
    den sign-certificate ${TRAEFIK_DOMAIN}
fi

:: Initializing environment
if [[ $AUTO_PULL ]]; then
    den env pull --ignore-pull-failures || true
    den env build --pull
else
    den env build
fi
den env up -d

## wait for mariadb to start listening for connections
den shell -c "while ! nc -z db 3306 </dev/null; do sleep 2; done"

if [[ $COMPOSER_INSTALL ]]; then
    :: Installing dependencies
    if [[ ${COMPOSER_VERSION} == 1 ]]; then
        den env exec -T php-fpm bash \
            -c '[[ $(composer -V | cut -d\  -f3 | cut -d. -f1) == 2 ]] || composer global require hirak/prestissimo'
    fi
    den env exec -T php-fpm composer install
fi

## import database only if --skip-db-import is not specified
if [[ ${DB_IMPORT} ]]; then
    if [[ -z "$DB_DUMP" ]]; then
        DB_DUMP="${WARDEN_ENV_NAME}_${BASE_ENV}-`date +%Y%m%dT%H%M%S`.sql.gz"
        :: Get database
        den db-dump --environment ${BASE_ENV} --file "${DB_DUMP}"
    fi

    if [[ "$DB_DUMP" ]]; then
        :: Importing database
        den import-db --file "${DB_DUMP}"
    fi
fi

den set-config

if [[ $MEDIA_SYNC ]]; then
    :: Syncing media from remote server
    den sync-media -e ${BASE_ENV}
fi

if [[ $ADMIN_CREATE -eq "1" ]]; then
    :: Creating admin user
    den env exec -T php-fpm bin/magento admin:user:create \
        --admin-user=admin \
        --admin-password=Admin123$ \
        --admin-firstname=Admin \
        --admin-lastname=User \
        --admin-email="admin@${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}" || true
fi

echo "=========== THE APPLICATION HAS BEEN INSTALLED SUCCESSFULLY ==========="
echo "Frontend: https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"
echo "Admin:    https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/admin"

if [[ $ADMIN_CREATE -eq "1" ]]; then
    echo "Username: admin"
    echo "Password: Admin123$"
fi

END_TIME=$(date +%s)

echo "Total build time: $((END_TIME - START_TIME)) seconds"
