#!/usr/bin/env bash
set -e

STACK="${1:-}"
CUSTOM_CONTAINER_NAME="${2:-}"

AVAILABLE_STACKS=("astro" "js-ts" "react-django" "react-express" "react-springboot" "java" "python")

usage() {
  echo "Usage: $0 {astro|js-ts|react-django|react-express|react-springboot|java|python|all} [container-name]"
  echo
  echo "Examples:"
  echo "  $0 react-express"
  echo "  $0 react-express my-api"
  echo "  $0 python data-lab"
  echo "  $0 all"
  echo
  echo "Notes:"
  echo "  - If container-name is omitted, the default name is <stack>-dev."
  echo "  - The all option does not accept a custom container name."
}

if [[ -z "$STACK" ]]; then
  usage
  exit 1
fi

if [[ "$STACK" == "all" && -n "$CUSTOM_CONTAINER_NAME" ]]; then
  echo "Error: the 'all' option does not accept a custom container name."
  echo
  usage
  exit 1
fi

if [[ -n "$CUSTOM_CONTAINER_NAME" && ! "$CUSTOM_CONTAINER_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
  echo "Error: invalid container name '$CUSTOM_CONTAINER_NAME'."
  echo "Use letters, numbers, dots, underscores, or hyphens, and start with a letter or number."
  exit 1
fi

IMAGE_VERSION="latest"
IMAGE="registry.fedoraproject.org/fedora-toolbox:$IMAGE_VERSION"

PNPM_VERSION="latest"
PNPM_STORE_DIR="$HOME/.local/share/pnpm/store"

JAVA_VERSION="latest"

COMMON_PACKAGES="git fastfetch zsh neovim gcc-c++ make curl zip unzip"

create_container() {
  local STACK_NAME="$1"
  local CONTAINER_NAME="${2:-$STACK_NAME-dev}"
  local CODE_DIR="$HOME/Documents/Code/$CONTAINER_NAME"
  local PACKAGES=""
  local DISTROBOX_NETWORK_ARGS=()
  local ADDITIONAL_FLAGS_ARGS=()

  local INSTALL_MAVEN="false"
  local INSTALL_GRADLE="false"
  local INSTALL_SPRINGBOOT="false"

  case "$STACK_NAME" in
    astro)
      PACKAGES="$COMMON_PACKAGES nodejs npm"
      ;;

    js-ts)
      PACKAGES="$COMMON_PACKAGES nodejs npm"
      ;;

    react-django)
      PACKAGES="$COMMON_PACKAGES nodejs npm python3 python3-pip python3-virtualenv python3-devel postgresql postgresql-devel"
      DISTROBOX_NETWORK_ARGS=(--unshare-netns)
      ADDITIONAL_FLAGS_ARGS=(--additional-flags "--network dev-net")
      ;;

    react-express)
      PACKAGES="$COMMON_PACKAGES nodejs npm"
      DISTROBOX_NETWORK_ARGS=(--unshare-netns)
      ADDITIONAL_FLAGS_ARGS=(--additional-flags "--network dev-net")
      ;;

    react-springboot)
      PACKAGES="$COMMON_PACKAGES nodejs npm java-$JAVA_VERSION-openjdk-devel.x86_64"
      INSTALL_MAVEN="true"
      INSTALL_GRADLE="true"
      INSTALL_SPRINGBOOT="true"
      DISTROBOX_NETWORK_ARGS=(--unshare-netns)
      ADDITIONAL_FLAGS_ARGS=(--additional-flags "--network dev-net")
      ;;

    java)
      PACKAGES="$COMMON_PACKAGES java-$JAVA_VERSION-openjdk-devel.x86_64"
      INSTALL_MAVEN="true"
      INSTALL_GRADLE="true"
      ;;
    
    python)
      PACKAGES="$COMMON_PACKAGES python3 python3-pip python3-virtualenv python3-devel gcc gcc-c++ make"
      ;;

    *)
      echo "Invalid stack: $STACK_NAME"
      usage
      exit 1
      ;;
  esac

  if distrobox list | awk '{print $3}' | grep -qx "$CONTAINER_NAME"; then
    echo "Container $CONTAINER_NAME already exists."
    read -rp "Do you want to delete it and reinstall everything? [y/N]: " REINSTALL

    if [[ "$REINSTALL" =~ ^[Yy]$ ]]; then
      echo "Deleting $CONTAINER_NAME..."
      distrobox rm --force "$CONTAINER_NAME"
    else
      echo "Skipping $CONTAINER_NAME..."
      return 0
    fi
  fi

  echo "Creating $CONTAINER_NAME container with stack $STACK_NAME..."

  distrobox create \
    --name "$CONTAINER_NAME" \
    --image "$IMAGE" \
    --home "$CODE_DIR" \
    "${DISTROBOX_NETWORK_ARGS[@]}" \
    "${ADDITIONAL_FLAGS_ARGS[@]}" \
    --additional-packages "$PACKAGES"

  echo "Configuring $CONTAINER_NAME container..."

  distrobox enter "$CONTAINER_NAME" -- env \
    PNPM_VERSION="$PNPM_VERSION" \
    PNPM_STORE_DIR="$PNPM_STORE_DIR" \
    CONTAINER_NAME="$CONTAINER_NAME" \
    INSTALL_MAVEN="$INSTALL_MAVEN" \
    INSTALL_GRADLE="$INSTALL_GRADLE" \
    INSTALL_SPRINGBOOT="$INSTALL_SPRINGBOOT" \
    bash -s <<'EOF'
set -e

fastfetch

if command -v npm >/dev/null 2>&1; then
  echo '= Install pnpm'
  sudo npm install -g pnpm@$PNPM_VERSION

  echo '= Setting pnpm store dir'
  pnpm config set store-dir "$PNPM_STORE_DIR"

  echo
  echo '= Node and PNPM version'
  node -v
  pnpm -v
fi

if command -v python3 >/dev/null 2>&1; then
  echo
  echo '= Python version'
  python3 --version
fi

if command -v java >/dev/null 2>&1; then
  echo
  echo '= Java version'
  java --version

  JAVA_BIN=$(command -v java)
  JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$JAVA_BIN")")")

  echo
  echo '= JAVA_HOME'
  echo "$JAVA_HOME"

  if command -v javac >/dev/null 2>&1; then
    echo
    echo '= Javac version'
    javac --version
  fi

  echo
  echo '= Installing SDKMAN'
  curl -s "https://get.sdkman.io" | bash

  export SDKMAN_DIR="$HOME/.sdkman"
  source "$SDKMAN_DIR/bin/sdkman-init.sh"

  if [[ "$INSTALL_MAVEN" == "true" ]]; then
    echo
    echo '= Installing Maven'
    sdk install maven || true
  fi

  if [[ "$INSTALL_GRADLE" == "true" ]]; then
    echo
    echo '= Installing Gradle'
    sdk install gradle || true
  fi

  if [[ "$INSTALL_SPRINGBOOT" == "true" ]]; then
    echo
    echo '= Installing Spring Boot CLI'
    sdk install springboot || true
  fi

  echo
  echo '= SDKMAN tools versions'

  if command -v mvn >/dev/null 2>&1; then
    mvn -v
  fi

  if command -v gradle >/dev/null 2>&1; then
    gradle -v
  fi

  if command -v spring >/dev/null 2>&1; then
    spring --version
  fi
fi

echo
echo "The $CONTAINER_NAME container is ready..."
EOF
}

if [[ "$STACK" == "all" ]]; then
  for STACK_NAME in "${AVAILABLE_STACKS[@]}"; do
    create_container "$STACK_NAME"
  done

  echo
  echo "All containers are ready."
else
  CONTAINER_NAME="${CUSTOM_CONTAINER_NAME:-$STACK-dev}"
  create_container "$STACK" "$CONTAINER_NAME"
  distrobox enter --no-workdir "$CONTAINER_NAME"
fi