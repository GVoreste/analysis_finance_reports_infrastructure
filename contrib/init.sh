#!/bin/bash

show_help() {
  echo "Use: $0 [options]"
  echo
  echo "Options:"
  echo "  -u,  --update          Update talosctl, kubectl, helm, flux and sops"
  echo "  -c,  --clean           Remove all generated artifacts"
  echo "  -MC, --magic-cleaner   Sometimes podman just needs a bit of magic..."
  echo "  -h,  --help            Show this help message"
}

start_detach_venv_context(){
  podman run  --detach \
  --device /dev/dri \
  --env DISPLAY \
  --env DBUS_SESSION_BUS_ADDRESS \
  --mount "type=tmpfs,tmpfs-mode=777,destination=/tmp" \
  -v "${FREEPORTS_REPO}:/home/developer" \
  -v "/tmp/.X11-unix:/tmp/.X11-unix" \
  -v "/run/user:/run/user" \
  -v "/run/dbus:/run/dbus" \
  -v "${FREEPORTS_BIND_FILES_DIR}/bashrc:/home/developer/.bashrc" \
  -v "${HOME}/.ssh:/home/developer/.ssh" \
  --network "host" \
  --hostname "freeports-venv" \
  --read-only \
  --user 1000:1000 \
  --workdir /home/developer \
  --userns=keep-id \
  --name "${FREEPORTS_VENV_CONTAINER_NAME}_DETACHED" \
  --entrypoint '["tail", "-f", "/dev/null"]' \
  "${FREEPORTS_VENV_IMG_NAME}:${FREEPORTS_VENV_TAG}"

  export exec_inside_venv="podman exec ${FREEPORTS_VENV_CONTAINER_NAME}_DETACHED"
}

end_detach_venv_context(){
  unset exec_inside_venv
  podman container rm -f "${FREEPORTS_VENV_CONTAINER_NAME}_DETACHED"
}

update_function() {
  start_detach_venv_context
  $exec_inside_venv pacman -Syu --no-confirm
  end_detach_venv_context
  exit 0
}

magic_cleaner(){
    pkill podman -9
}

clean(){
  rm -rvf ${FREEPORTS_IMG}
  podman container rm -f "${FREEPORTS_VENV_CONTAINER_NAME}" &> /dev/null
  podman container rm -f "${FREEPORTS_VENV_CONTAINER_NAME}_DETACHED" &> /dev/null
  podman image rm "${FREEPORTS_VENV_IMG_NAME}:${FREEPORTS_VENV_TAG}" &> /dev/null
  rm -rf "${dotenv}"
}

set -e
FREEPORTS_REPO=$(git rev-parse --show-toplevel)
FREEPORTS_VENV_IMG_NAME="freeports-venv"
FREEPORTS_VENV_CONTAINER_NAME="freeports-venv-linux"
FREEPORTS_VENV_SRC="${FREEPORTS_REPO}/contrib"
FREEPORTS_IMG="${FREEPORTS_VENV_SRC}/.oci-freeports-venv-image"
FREEPORTS_VENV_TAG="latest"
FREEPORTS_BIND_FILES_DIR="${FREEPORTS_VENV_SRC}/bind-files"
dotenv="${FREEPORTS_VENV_SRC}/.env"
rm -rf "${dotenv}"
touch ${dotenv}
echo "FREEPORTS_REPO=${FREEPORTS_REPO}" >> ${dotenv}
echo "FREEPORTS_VENV_IMG_NAME=${FREEPORTS_VENV_IMG_NAME}" >> ${dotenv}
echo "FREEPORTS_VENV_CONTAINER_NAME=${FREEPORTS_VENV_CONTAINER_NAME}" >> ${dotenv}
echo "FREEPORTS_VENV_SRC=${FREEPORTS_VENV_SRC}" >> ${dotenv}
echo "FREEPORTS_VENV_TAG=${FREEPORTS_VENV_TAG}" >> ${dotenv}
echo "FREEPORTS_BIND_FILES_DIR=${FREEPORTS_BIND_FILES_DIR}" >> ${dotenv}

# Ciclo per analizzare gli argomenti passati allo script
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -MC|--magic-cleaner)
      # Chiamata alla funzione se l'opzione è -MC o --magic-cleaner
      magic_cleaner
      exit 0  # Sposta al prossimo argomento
      ;;
    -c|--clean)
      # Chiamata alla funzione se l'opzione è -MC o --magic-cleaner
      clean
      exit 0  # Sposta al prossimo argomento
      ;;
    -u|--update)
      # Chiamata alla funzione se l'opzione è -u o --update
      update_function
      shift  # Sposta al prossimo argomento
      ;;
    -h|--help)
      # Mostra il messaggio di help se l'opzione è -h o --help
      show_help
      exit 0
      ;;
    *)
      # Gestisci altre opzioni o parametri, se necessario
      echo "Option not recognized: $1"
      show_help
      exit 1
      ;;
  esac
done





source ${dotenv}

cat ${FREEPORTS_VENV_SRC}/ascii-arts/begin-setup.txt
if [ -f "${FREEPORTS_REPO}/activate-venv" ]; then
  echo "Repository already initialized."
  exit 0
fi

mkdir -p "${FREEPORTS_IMG}"
if podman image exists "${FREEPORTS_VENV_IMG_NAME}:${FREEPORTS_VENV_TAG}" && [ "${FREEPORTS_VENV_TAG}" != "latest" ]; then
  echo "Image ${FREEPORTS_IMG}:${FREEPORTS_VENV_TAG} already exist... skipping build"
else
  podman build -f "${FREEPORTS_VENV_SRC}/Containerfile"  --tag "${FREEPORTS_VENV_IMG_NAME}:${FREEPORTS_VENV_TAG}"
  podman push -f oci "${FREEPORTS_VENV_IMG_NAME}:${FREEPORTS_VENV_TAG}" "dir:${FREEPORTS_IMG}"
fi

mkdir -p "${HOME}/.ssh/"
mkdir -p ${FREEPORTS_REPO}/secrets

start_detach_venv_context
set +e
$exec_inside_venv ls /home/developer/.ssh/config &> /dev/null
if [ "$?" -eq 2 ]; then $exec_inside_venv cp /opt/freeports-venv/ssh-config /home/developer/.ssh/config ; fi
$exec_inside_venv ls /home/developer/.ssh/github &> /dev/null
if [ "$?" -eq 2 ]; then $exec_inside_venv ssh-keygen -t ed25519 -C "github access key" -f "/home/developer/.ssh/github" -N "" ; fi
SSH_GIT_PUBKEY=$(cat "${HOME}/.ssh/github.pub")
$exec_inside_venv ls /home/developer/secrets/age.key &> /dev/null
if [ "$?" -eq 2 ]; then $exec_inside_venv age-keygen -o /home/developer/secrets/age.key; fi
AGE_PUBKEY=$($exec_inside_venv age-keygen -y /home/developer/secrets/age.key)
set -e
end_detach_venv_context

git config --local core.hooksPath "${FREEPORTS_REPO}/.githooks/"

git config --local filter.sops-regex.smudge 'sops --input-type yaml --output-type yaml --decrypt /dev/stdin'
git config --local filter.sops-regex.clean 'sops --input-type yaml --output-type yaml --encrypted-regex "secret" --encrypt /dev/stdin'
git config --local filter.sops-regex.required true

git config --local filter.sops-regex.smudge 'sops --input-type yaml --output-type yaml --encrypt /dev/stdin'
git config --local filter.sops-regex.clean 'sops --input-type yaml --output-type yaml --decrypt /dev/stdin'
git config --local filter.sops-regex.required true

git config --local filter.age.clean 'age --encrypt --armor -r "${SOPS_AGE_RECIPIENTS}" /dev/stdin'
git config --local filter.age.smudge 'age --decrypt --armor -i "${SOPS_AGE_KEY_FILE}" /dev/stdin'
git config --local filter.age.required true


cp "${FREEPORTS_REPO}/contrib/activate-venv" "${FREEPORTS_REPO}/activate-venv"
cat "${FREEPORTS_VENV_SRC}/ascii-arts/trademark.txt"
cat "${FREEPORTS_VENV_SRC}/ascii-arts/end-setup.txt"
echo "Github repository access pubkey: [${SSH_GIT_PUBKEY}]"
echo "AGE encryption pubkey:           [${AGE_PUBKEY}]"