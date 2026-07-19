#!/bin/sh
set -eu

IMAGE="docker-laravel:test"
APP_DIRECTORY=""
REPEAT=1
PARALLEL=1

usage() {
    cat <<'EOF'
Usage: ./run-tests.sh [options]

Options:
  --image <name>      Local base image tag (default: docker-laravel:test)
  --app <path>        Laravel project used for a derived-image integration test
  --repeat <count>    Number of derived-image builds (default: 1)
  --parallel <count>  Number of concurrent derived-image builds (default: 1)
  -h, --help          Show this help
EOF
}

require_positive_integer() {
    case "$2" in
        ''|*[!0-9]*|0)
            echo "$1 must be a positive integer." >&2
            exit 2
            ;;
    esac
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --image)
            [ "$#" -ge 2 ] || { echo "Missing value for --image." >&2; exit 2; }
            IMAGE=$2
            shift 2
            ;;
        --app)
            [ "$#" -ge 2 ] || { echo "Missing value for --app." >&2; exit 2; }
            APP_DIRECTORY=$2
            shift 2
            ;;
        --repeat)
            [ "$#" -ge 2 ] || { echo "Missing value for --repeat." >&2; exit 2; }
            REPEAT=$2
            require_positive_integer "--repeat" "$REPEAT"
            shift 2
            ;;
        --parallel)
            [ "$#" -ge 2 ] || { echo "Missing value for --parallel." >&2; exit 2; }
            PARALLEL=$2
            require_positive_integer "--parallel" "$PARALLEL"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$APP_DIRECTORY" ] && { [ "$REPEAT" -ne 1 ] || [ "$PARALLEL" -ne 1 ]; }; then
    echo "--repeat and --parallel require --app." >&2
    exit 2
fi

echo "Building base image: $IMAGE"
docker build --pull --tag "$IMAGE" .

echo "Running entrypoint and runtime tests ..."
./tests/entrypoint.sh "$IMAGE"

if [ -z "$APP_DIRECTORY" ]; then
    echo "Local image tests passed."
    exit 0
fi

if [ ! -d "$APP_DIRECTORY" ]; then
    echo "Laravel application directory does not exist: $APP_DIRECTORY" >&2
    exit 2
fi

echo "Running $REPEAT derived-image build(s), parallelism: $PARALLEL"
if [ "$REPEAT" -eq 1 ]; then
    ./tests/integration.sh "$IMAGE" "$APP_DIRECTORY" 1
else
    seq 1 "$REPEAT" | xargs -P "$PARALLEL" -I {} \
        ./tests/integration.sh "$IMAGE" "$APP_DIRECTORY" {}
fi

echo "All local tests passed."
