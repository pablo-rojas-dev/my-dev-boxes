#!/usr/bin/env bash
set -euo pipefail

AVAILABLE_STACKS=(astro js-ts react-django react-express react-springboot java python)
IMAGE_VERSION="latest"
IMAGE="registry.fedoraproject.org/fedora-toolbox:$IMAGE_VERSION"
PNPM_VERSION="latest"
PNPM_STORE_DIR="$HOME/.local/share/pnpm/store"
JAVA_VERSION="latest"
COMMON_PACKAGES="git fastfetch zsh neovim gcc-c++ make curl zip unzip"

usage() {
  cat <<'USAGE'
Usage: create.sh STACK [container-name] [--network host|NETWORK_NAME]
       create.sh all [--network host|NETWORK_NAME]

Examples:
  ./create.sh react-django
  ./create.sh react-django --network dev-net
  ./create.sh react-express my-api --network dev-net
  ./create.sh python data-lab
  ./create.sh all --network dev-net

Default: host networking (shared with Fedora Kinoite).
For a Podman network, the network must already exist.
USAGE
}

[[ $# -gt 0 ]] || { usage; exit 1; }
STACK="$1"; shift
CUSTOM_CONTAINER_NAME=""
NETWORK="host"
NETWORK_SPECIFIED=false
while (($#)); do
  case "$1" in
    --network)
      [[ $# -ge 2 && -n "$2" ]] || { echo 'Error: --network needs a value.' >&2; exit 1; }
      [[ "$NETWORK_SPECIFIED" == false ]] || { echo 'Error: --network specified more than once.' >&2; exit 1; }
      NETWORK="$2"; NETWORK_SPECIFIED=true; shift 2 ;;
    --network=*)
      [[ "$NETWORK_SPECIFIED" == false ]] || { echo 'Error: --network specified more than once.' >&2; exit 1; }
      NETWORK="${1#--network=}"; NETWORK_SPECIFIED=true; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "Error: unknown option $1" >&2; usage; exit 1 ;;
    *)
      [[ -z "$CUSTOM_CONTAINER_NAME" ]] || { echo 'Error: too many positional arguments.' >&2; exit 1; }
      CUSTOM_CONTAINER_NAME="$1"; shift ;;
  esac
done

if [[ "$STACK" != all ]]; then
  valid=false
  for item in "${AVAILABLE_STACKS[@]}"; do
    [[ "$STACK" == "$item" ]] && valid=true
  done
  [[ "$valid" == true ]] || { echo "Error: invalid stack '$STACK'." >&2; usage; exit 1; }
fi
if [[ "$STACK" == all && -n "$CUSTOM_CONTAINER_NAME" ]]; then
  echo 'Error: all does not accept a custom container name.' >&2; exit 1
fi
if [[ -n "$CUSTOM_CONTAINER_NAME" && ! "$CUSTOM_CONTAINER_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
  echo "Error: invalid container name '$CUSTOM_CONTAINER_NAME'." >&2; exit 1
fi
if [[ -z "$NETWORK" || ! "$NETWORK" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
  echo "Error: invalid network name '$NETWORK'." >&2; exit 1
fi
for command in distrobox podman; do
  command -v "$command" >/dev/null 2>&1 || { echo "Error: $command is required." >&2; exit 1; }
done
if [[ "$NETWORK" != host ]] && ! podman network exists "$NETWORK"; then
  echo "Error: Podman network '$NETWORK' does not exist." >&2
  echo "Create it with: podman network create '$NETWORK'" >&2
  exit 1
fi

create_container() {
  local STACK_NAME="$1"
  local CONTAINER_NAME="${2:-$STACK_NAME-dev}"
  local CODE_DIR="$HOME/Code/$CONTAINER_NAME"
  local PACKAGES=""
  local INSTALL_MAVEN=false INSTALL_GRADLE=false INSTALL_SPRINGBOOT=false
  local DISTROBOX_NETWORK_ARGS=() ADDITIONAL_FLAGS_ARGS=()

  case "$STACK_NAME" in
    astro|js-ts|react-express)
      PACKAGES="$COMMON_PACKAGES nodejs npm" ;;
    react-django)
      PACKAGES="$COMMON_PACKAGES nodejs npm python3 python3-pip python3-virtualenv python3-devel postgresql postgresql-devel" ;;
    react-springboot)
      PACKAGES="$COMMON_PACKAGES nodejs npm java-$JAVA_VERSION-openjdk-devel.x86_64"
      INSTALL_MAVEN=true; INSTALL_GRADLE=true; INSTALL_SPRINGBOOT=true ;;
    java)
      PACKAGES="$COMMON_PACKAGES java-$JAVA_VERSION-openjdk-devel.x86_64"
      INSTALL_MAVEN=true; INSTALL_GRADLE=true ;;
    python)
      PACKAGES="$COMMON_PACKAGES python3 python3-pip python3-virtualenv python3-devel gcc gcc-c++ make" ;;
  esac

  if [[ "$NETWORK" != host ]]; then
    DISTROBOX_NETWORK_ARGS=(--unshare-netns)
    ADDITIONAL_FLAGS_ARGS=(--additional-flags "--network=$NETWORK")
  fi

  if podman container exists "$CONTAINER_NAME"; then
    echo "Container $CONTAINER_NAME already exists."
    read -rp 'Delete it and reinstall everything? [y/N]: ' REINSTALL
    if [[ "$REINSTALL" =~ ^[Yy]$ ]]; then
      echo "Deleting $CONTAINER_NAME..."
      distrobox rm --force "$CONTAINER_NAME"
    else
      echo "Skipping $CONTAINER_NAME..."
      return 0
    fi
  fi

  mkdir -p "$CODE_DIR"
  echo "Creating $CONTAINER_NAME (stack: $STACK_NAME, network: $NETWORK)..."
  distrobox create \
    --name "$CONTAINER_NAME" \
    --image "$IMAGE" \
    --home "$CODE_DIR" \
    "${DISTROBOX_NETWORK_ARGS[@]}" \
    "${ADDITIONAL_FLAGS_ARGS[@]}" \
    --additional-packages "$PACKAGES"

  echo "Configuring $CONTAINER_NAME..."
  distrobox enter "$CONTAINER_NAME" -- env \
    PNPM_VERSION="$PNPM_VERSION" \
    PNPM_STORE_DIR="$PNPM_STORE_DIR" \
    CONTAINER_NAME="$CONTAINER_NAME" \
    INSTALL_MAVEN="$INSTALL_MAVEN" \
    INSTALL_GRADLE="$INSTALL_GRADLE" \
    INSTALL_SPRINGBOOT="$INSTALL_SPRINGBOOT" \
    bash -s <<'INNER'
set -e
fastfetch
if command -v npm >/dev/null 2>&1; then
  echo '= Installing pnpm'
  sudo npm install -g "pnpm@$PNPM_VERSION"
  pnpm config set store-dir "$PNPM_STORE_DIR"
  node -v
  pnpm -v
fi
if command -v python3 >/dev/null 2>&1; then
  python3 --version
fi
if command -v java >/dev/null 2>&1; then
  java --version
  JAVA_BIN=$(command -v java)
  JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$JAVA_BIN")")")
  echo "JAVA_HOME=$JAVA_HOME"
  if command -v javac >/dev/null 2>&1; then javac --version; fi
  echo '= Installing SDKMAN'
  curl -s https://get.sdkman.io | bash
  export SDKMAN_DIR="$HOME/.sdkman"
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
  if [[ "$INSTALL_MAVEN" == true ]]; then sdk install maven || true; fi
  if [[ "$INSTALL_GRADLE" == true ]]; then sdk install gradle || true; fi
  if [[ "$INSTALL_SPRINGBOOT" == true ]]; then sdk install springboot || true; fi
  if command -v mvn >/dev/null 2>&1; then mvn -v; fi
  if command -v gradle >/dev/null 2>&1; then gradle -v; fi
  if command -v spring >/dev/null 2>&1; then spring --version; fi
fi
echo "The $CONTAINER_NAME container is ready."
INNER
}

if [[ "$STACK" == all ]]; then
  for STACK_NAME in "${AVAILABLE_STACKS[@]}"; do
    create_container "$STACK_NAME"
  done
  echo 'All containers are ready.'
else
  CONTAINER_NAME="${CUSTOM_CONTAINER_NAME:-$STACK-dev}"
  create_container "$STACK" "$CONTAINER_NAME"
  distrobox enter --no-workdir "$CONTAINER_NAME"
fi
