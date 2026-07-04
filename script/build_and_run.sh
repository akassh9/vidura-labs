#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Vidura Labs"
PROJECT_NAME="Vidura Labs.xcodeproj"
SCHEME_NAME="Vidura Labs"
CONFIGURATION="Debug"
BUNDLE_ID="Lorenzo-Pulcini.Physics-Companion"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.codex/DerivedData"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"

usage() {
  echo "usage: $0 [run|build|--debug|--logs|--telemetry|--verify]" >&2
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

load_local_env() {
  export VIDURA_REPO_ROOT="$ROOT_DIR"

  local env_file line value
  for env_file in "$ROOT_DIR/.env.local" "$ROOT_DIR/.env"; do
    [[ -f "$env_file" ]] || continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="$(trim "$line")"
      line="${line#export }"
      [[ -z "$line" || "$line" == \#* ]] && continue
      case "$line" in
        OPENAI_API_KEY=*)
          value="${line#OPENAI_API_KEY=}"
          value="$(trim "${value%$'\r'}")"
          if [[ "$value" == \"*\" && "$value" == *\" ]]; then
            value="${value:1:${#value}-2}"
          elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
            value="${value:1:${#value}-2}"
          fi
          [[ -n "$value" ]] && export OPENAI_API_KEY="$value"
          ;;
      esac
    done < "$env_file"
  done
}

build_app() {
  export VIDURA_REPO_ROOT="$ROOT_DIR"
  mkdir -p "$DERIVED_DATA_DIR"

  xcodebuild \
    -project "$ROOT_DIR/$PROJECT_NAME" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    build
}

open_app() {
  load_local_env
  /usr/bin/open -n --env "VIDURA_REPO_ROOT=$ROOT_DIR" "$APP_BUNDLE"
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

case "$MODE" in
  build|--build)
    build_app
    ;;
  run)
    build_app
    open_app
    ;;
  --debug|debug)
    build_app
    load_local_env
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    build_app
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    usage
    exit 2
    ;;
esac
