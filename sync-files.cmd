#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

function dumpCloud () {
    echo -e "\033[1;32mDownloading files from \033[33mAdobe Commerce Cloud \033[1;36m${DUMP_HOST}\033[0m ..."
    eval "dump_path=\${"DUMP_PATH"}"
    magento-cloud mount:download -p "$CLOUD_PROJECT" \
        --environment="$DUMP_HOST" \
        "${exclude_opts[@]}" \
        --mount=$dump_path \
        --target=$dump_path \
        -y \
        || true
}

function dumpPremise () {
    eval "ssh_host=\${"REMOTE_${DUMP_SOURCE_VAR}_HOST"}"
    eval "ssh_user=\${"REMOTE_${DUMP_SOURCE_VAR}_USER"}"
    eval "ssh_port=\${"REMOTE_${DUMP_SOURCE_VAR}_PORT"}"
    eval "remote_dir=\${"REMOTE_${DUMP_SOURCE_VAR}_PATH"}"
    eval "dump_path=\${"DUMP_PATH"}"

    echo -e "⌛ \033[1;32mDownloading files from ${ssh_host}\033[0m ..."
    rsync -azvP -e 'ssh -p '"$ssh_port" \
        "${exclude_opts[@]}" \
        $ssh_user@$ssh_host:$remote_dir/$dump_path $dump_path
}

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/env-variables

DUMP_SOURCE=dev
DUMP_PATH=pub/media/

while (( "$#" )); do
    case "$1" in
        --environment=*|-e=*|--e=*)
            DUMP_SOURCE="${1#*=}"
            shift
            ;;
        --path=*|-p=*|--p=*)
            DUMP_PATH="${1#*=}"
            shift
            ;;
        *)
            error "Unrecognized argument '$1'"
            exit 2
            ;;
    esac
done

DUMP_SOURCE_VAR=$(echo "$DUMP_SOURCE" | tr '[:lower:]' '[:upper:]')
DUMP_ENV="REMOTE_${DUMP_SOURCE_VAR}_HOST"

if [ -z ${!DUMP_ENV+x} ]; then
    echo "Invalid environment '${DUMP_SOURCE}'"
    exit 2
fi

DUMP_HOST=${!DUMP_ENV}

if [[ "${DUMP_HOST}" ]]; then
    if [ -z ${CLOUD_PROJECT+x} ]; then
        dumpPremise
    else
        dumpCloud
    fi
fi
