#!/busybox/sh
set -euo pipefail

args=$(mktemp)
labels=$(mktemp)
tags=$(mktemp)

REGISTRY=${PLUGIN_REGISTRY:-index.docker.io}
REPO=${PLUGIN_REPO:-$(echo $DRONE_REPO | tr '[:upper:]' '[:lower:]')}
VERBOSITY=${PLUGIN_VERBOSITY:-info}
CONTEXT=${PLUGIN_CONTEXT:-$PWD}
DOCKERFILE=${PLUGIN_DOCKERFILE:-Dockerfile}

if [ -n "${PLUGIN_USERNAME:-}" ] && [ -n "${PLUGIN_PASSWORD:-}" ]; then
	DOCKER_AUTH=$(echo -n "$PLUGIN_USERNAME:$PLUGIN_PASSWORD" | base64 | tr -d "\n")
	cat > /kaniko/.docker/config.json <<EOF
{
	"auths": {
		"${REGISTRY}": {
			"auth": "${DOCKER_AUTH}"
		}
	}
}
EOF
fi

if [ "${PLUGIN_JSON_KEY:-}" ];then
	echo "$PLUGIN_JSON_KEY" > /kaniko/gcr.json
	export GOOGLE_APPLICATION_CREDENTIALS=/kaniko/gcr.json
fi

if ! cat .kaniko.args 1> $args 2> /dev/null; then
	if [ -n "${PLUGIN_BUILD_ARGS:-}" ]; then
		echo "$PLUGIN_BUILD_ARGS" | tr ',' '\n' >> $args
	fi
	if [ -n "${PLUGIN_BUILD_ARGS_FROM_ENV:-}" ]; then
		echo "$PLUGIN_BUILD_ARGS_FROM_ENV" | tr ',' '\n' | while read arg; do echo "$arg=$(eval "echo \$$arg")"; done >> $args
	fi
fi

if ! cat .kaniko.labels 1> $labels 2> /dev/null; then
	echo "org.label-schema.schema-version=1.0" >> $labels
	echo "org.label-schema.build-date=$(date -I'seconds')" >> $labels
	echo "org.label-schema.name=$REPO" >> $labels
	echo "org.label-schema.url=${DRONE_REPO_LINK:-}" >> $labels
	echo "org.label-schema.vcs-url=${DRONE_REMOTE_URL:-}" >> $labels
	echo "org.label-schema.vcs-ref=${DRONE_COMMIT_SHA:-}" >> $labels
	echo "org.label-schema.version=${DRONE_TAG:-${DRONE_COMMIT_SHA:-}}" >> $labels
	if [ -n "${PLUGIN_ADDITIONAL_LABELS:-}" ]; then
		echo "$PLUGIN_ADDITIONAL_LABELS" | tr ',' '\n' >> $labels
	fi
fi

if ! cat .kaniko.tags 1> $tags 2> /dev/null; then
	if [ "${DRONE_BRANCH:-}" = "${DRONE_REPO_BRANCH:-}" ]; then
		echo "latest" >> $tags
	fi
	if [ -n "${DRONE_BRANCH:-}" ]; then
		echo "${DRONE_BRANCH/\//-}" >> $tags
	fi
	if [ -n "${DRONE_COMMIT_SHA:-}" ]; then
		echo "${DRONE_COMMIT_SHA:0:${PLUGIN_COMMIT_SHA_LENGTH:-8}}" >> $tags
	fi
	if [ -n "${DRONE_SEMVER:-}" ]; then
		echo "$DRONE_SEMVER" >> $tags
		echo "$DRONE_SEMVER_SHORT" >> $tags
		echo "$DRONE_SEMVER_MAJOR" >> $tags
		echo "$DRONE_SEMVER_MAJOR.$DRONE_SEMVER_MINOR" >> $tags
		echo "$DRONE_SEMVER_MAJOR.$DRONE_SEMVER_MINOR.$DRONE_SEMVER_PATCH" >> $tags
	fi
	if [ -n "${PLUGIN_ADDITIONAL_TAGS:-}" ]; then
		echo "$PLUGIN_ADDITIONAL_TAGS" | tr ',' '\n' >> $tags
	fi
fi

if [ -n "${PLUGIN_CACHE_IMAGES:-}" ]; then
	CACHE_IMAGES=$(echo "$PLUGIN_CACHE_IMAGES" | tr ',' '\n' | while read img; do echo "--image=$img "; done)
else
	CACHE_IMAGES=$(grep -i "^from" $CONTEXT/$DOCKERFILE | tr -s ' ' | cut -d ' ' -f2 | while read img; do echo "--image=$img "; done)
fi
BUILD_ARGS=$(cat $args | while read arg; do echo "--build-arg $arg "; done)
IMAGE_LABELS=$(cat $labels | while read label; do echo "--label $label "; done)
IMAGE_TAGS=$(cat $tags | while read tag; do echo "--destination=$REGISTRY/$REPO:$tag "; done)
RESULT_TAGS=$(cat $tags | while read tag; do echo "- $REGISTRY/$REPO:$tag"; done)

CACHE_DIR="${PLUGIN_CACHE_DIR:-/cache}/kaniko"
if [ -d "${PLUGIN_CACHE_DIR:-/cache}" ]; then
	echo "Prewarm image caches at $CACHE_DIR"
	set -x
	warmer \
		--verbosity=$VERBOSITY \
		--cache-dir=$CACHE_DIR \
		${PLUGIN_CACHE_TTL+--cache-ttl=$PLUGIN_CACHE_TTL} \
		$CACHE_IMAGES || true
	{ set +x; } 2> /dev/null
fi

set -x
executor \
	--verbosity=$VERBOSITY \
	--context=$CONTEXT \
	--dockerfile=$DOCKERFILE \
	$BUILD_ARGS \
	$IMAGE_TAGS \
	$IMAGE_LABELS \
	--no-push=${PLUGIN_NO_PUSH:-false} \
	--cache=${PLUGIN_CACHE:-true} \
	--cache-dir=$CACHE_DIR \
	${PLUGIN_CACHE_REPO+--cache-repo=$REGISTRY/$PLUGIN_CACHE_REPO} \
	${PLUGIN_CACHE_TTL+--cache-ttl=$PLUGIN_CACHE_TTL} \
	${PLUGIN_REGISTRY_MIRROR+--registry-mirror=$PLUGIN_REGISTRY_MIRROR} \
	${PLUGIN_TARGET+--target=$PLUGIN_TARGET} \
	${PLUGIN_EXTRA_OPTS:-}
{ set +x; } 2> /dev/null

echo "Images published:"
echo $RESULT_TAGS
