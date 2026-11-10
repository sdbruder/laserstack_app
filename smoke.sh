#!/bin/bash
set -euo pipefail

# Smoke test of one image of this repository, before the image is published.
#
#   ./smoke.sh laserstack/app:8.5 8.5
#
# It starts the container the way a user starts it, and then asks the container
# about itself. A failure means the image must not be pushed: buildx.sh runs
# this before its push, and the build check of a pull request runs it for every
# directory that the pull request changes.
#
# What it proves:
#
#   - supervisord starts and keeps nginx and php-fpm running
#   - nginx answers on the published port and reaches php-fpm: the request goes
#     through the vhost of the image, so the php version in the answer comes
#     from the container and not from this machine
#   - the php series of the image is the series of the directory it came from
#   - the extensions the README promises are loaded
#   - xdebug is loaded in profile mode, as php.ini of the image asks
#   - the inventory of the image exists and is consistent with the php version
#   - composer and phpunit run
#
# The memcached extension is required everywhere except 8.6: Alpine packages no
# memcached for that series, see 8.6/Dockerfile.

if [ "$#" -ne 2 ]; then
  echo "usage: $(basename "$0") <image> <php series>, for example: $(basename "$0") laserstack/app:8.5 8.5" >&2
  exit 2
fi

image="$1"
series="$2"
name="laserstack-smoke-$$-$RANDOM"

# buildx.sh calls this from the directory of the image, so the Dockerfile is
# found next to this script and not next to the caller.
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dockerfile="$repo_dir/$series/Dockerfile"

cleanup() { docker rm --force "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail() { echo "smoke: $image: $*" >&2; exit 1; }
ok() { printf '  ok  %s\n' "$*"; }

echo "smoke: $image (php $series)"

docker run --detach --name "$name" --publish 127.0.0.1::80 "$image" >/dev/null \
  || fail "the container does not start"

# supervisord needs a moment to start nginx and php-fpm. 7.4 and 8.0 name the
# fpm program php-fpm, the other series name it php.
status=""
php_program=""
for _ in $(seq 1 30); do
  sleep 1
  status="$(docker exec "$name" supervisorctl status 2>/dev/null || true)"
  php_program="$(printf '%s\n' "$status" | sed -E -n 's/^(php-fpm|php)  *RUNNING.*/\1/p' | head -n1)"
  if printf '%s\n' "$status" | grep -q '^nginx  *RUNNING' && [ -n "$php_program" ]; then
    break
  fi
  if printf '%s\n' "$status" | grep -qE 'FATAL|EXITED|BACKOFF'; then
    fail "a program of the image does not stay up, supervisorctl says: $(printf '%s' "$status" | tr '\n' ' ')"
  fi
  if [ "$(docker inspect --format '{{.State.Running}}' "$name" 2>/dev/null || echo true)" != "true" ]; then
    fail "the container exited, its log ends with: $(docker logs --tail 5 "$name" 2>&1 | tr '\n' ' ')"
  fi
done
printf '%s\n' "$status" | grep -q '^nginx  *RUNNING' || fail "nginx is not running, supervisorctl says: ${status:-nothing}"
[ -n "$php_program" ] || fail "php-fpm is not running, supervisorctl says: ${status:-nothing}"
ok "supervisord runs nginx and $php_program"

# The vhost serves ${PROJECTS_DIRECTORY}/<project>/public for <project>.test, so
# one small application is enough to walk the whole path: nginx, the vhost, the
# fastcgi socket, php-fpm.
docker exec "$name" sh -c \
  'mkdir -p /var/www/smoke/public && printf "%s\n" "<?php echo \"smoke \", PHP_VERSION;" > /var/www/smoke/public/index.php' \
  || fail "cannot write the test application into the container"

port=""
for _ in $(seq 1 30); do
  port="$(docker port "$name" 80/tcp 2>/dev/null | head -n1 | sed 's/.*://')" || true
  [ -n "$port" ] || { sleep 1; continue; }
  code="$(curl --silent --output /tmp/smoke-body.$$ --write-out '%{http_code}' --max-time 5 -H 'Host: smoke.test' "http://127.0.0.1:$port/" || true)"
  # an empty code means nothing listens yet; any code means the chain answered,
  # and a wrong answer is not worth another thirty seconds
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    break
  fi
  sleep 1
done
body="$(cat /tmp/smoke-body.$$ 2>/dev/null || true)"
rm -f /tmp/smoke-body.$$
[ "${code:-}" = "200" ] || fail "the vhost does not answer with 200 (it answered ${code:-nothing}) on port ${port:-unknown}"
case "$body" in
  "smoke $series."*) ok "nginx reaches php-fpm and answers '$body'" ;;
  *) fail "the vhost answered '$body', expected 'smoke $series.<something>'" ;;
esac

# The image must say who it is, and agree with the directory it came from.
php_version="$(docker exec "$name" php -r 'echo PHP_VERSION;')"
case "$php_version" in
  "$series."*) ok "php $php_version comes from the directory $series" ;;
  *) fail "php is $php_version, but the directory is $series" ;;
esac

modules="$(docker exec "$name" php -m)"

# The extensions the image must load are the php packages its own Dockerfile
# installs, so the expectation cannot drift from the source: a package that is
# installed but not enabled as an extension fails here. Comments do not count —
# 8.6 names php86-pecl-memcached in a comment to say that Alpine has no such
# package — so the packages come from the instructions alone.
expected=""
for package in $(sed -E 's/#.*$//' "$dockerfile" | grep -oE 'php[0-9]+-[a-zA-Z0-9_-]+' | sort -u); do
  extension="${package#php*-}"
  extension="${extension#pecl-}"
  case "$extension" in
    fpm) continue ;;
    opcache) extension="Zend OPcache" ;;
    simplexml) extension="SimpleXML" ;;
    phar) extension="Phar" ;;
  esac
  expected="$expected$extension
"
done
[ -n "$expected" ] || fail "no php package in $dockerfile, the check cannot run"
missing=""
while IFS= read -r extension; do
  [ -n "$extension" ] || continue
  printf '%s\n' "$modules" | grep -qix "$extension" || missing="$missing $extension"
done <<< "$expected"
[ -z "$missing" ] || fail "the image installs these packages but does not load them:$missing"
ok "the $(printf '%s\n' "$expected" | grep -c .) php packages of $dockerfile are loaded"

mode="$(docker exec "$name" php -r 'echo ini_get("xdebug.mode");')"
[ "$mode" = "profile" ] || fail "xdebug.mode is '$mode', the images set profile"
ok "xdebug runs in profile mode"

inventory="$(docker exec "$name" cat /etc/laserstack/versions.txt)"
printf '%s\n' "$inventory" | grep -qx "php $php_version" \
  || fail "the inventory does not name php $php_version, it says: $(printf '%s' "$inventory" | tr '\n' ' ')"
printf '%s\n' "$inventory" | grep -q '^composer ' || fail "the inventory has no composer line"
printf '%s\n' "$inventory" | grep -q '^supervisor ' || fail "the inventory has no supervisor line"
ok "the image carries its own inventory"
printf '%s\n' "$inventory" | sed 's/^/      /'

composer_version="$(docker exec "$name" composer --version 2>/dev/null | sed -n 's/^Composer version \([^ ]*\).*/\1/p' || true)"
[ -n "$composer_version" ] || fail "composer does not run"
printf '%s\n' "$inventory" | grep -qx "composer $composer_version" \
  || fail "composer runs as $composer_version, but the inventory says: $(printf '%s' "$inventory" | grep '^composer ')"

phpunit_version="$(docker exec "$name" phpunit --version 2>/dev/null | awk '/^PHPUnit/ {print $2}' || true)"
[ -n "$phpunit_version" ] || fail "phpunit does not run"
printf '%s\n' "$inventory" | grep -qx "phpunit $phpunit_version" \
  || fail "phpunit runs as $phpunit_version, but the inventory says: $(printf '%s' "$inventory" | grep '^phpunit ')"

ok "composer $composer_version and phpunit $phpunit_version run, and the inventory agrees"

echo "smoke: $image is usable"
