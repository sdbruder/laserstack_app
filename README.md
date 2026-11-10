# Laser Stack

This is the app container image for [Laserstack](https://github.com/sdbruder/laserstack).

## Images

Each directory builds one image. An image carries the newest PHP patch of its
series and runs on the newest Alpine release that still packages that series;
a series that no released branch carries yet runs on `edge`, and takes its
package from the repository that has it.

| Directory | Alpine | PHP    | Series status                     |
| --------- | ------ | ------ | --------------------------------- |
| `7.4`     | 3.15   | 7.4.33 | end of life, final release        |
| `8.0`     | 3.16   | 8.0.30 | end of life, final release        |
| `8.1`     | 3.19   | 8.1.34 | end of life, final release        |
| `8.2`     | 3.22   | 8.2.35 | security fixes only               |
| `8.3`     | 3.24   | 8.3.36 | bug and security fixes            |
| `8.4`     | 3.24   | 8.4.27 | bug and security fixes            |
| `8.5`     | 3.24   | 8.5.12 | current stable                    |
| `8.6`     | edge   | 8.6.0RC5 | release candidate, not `latest` |

The JavaScript toolchain — `node`, `npm` and `yarn` — comes from the Alpine
release of the directory, as do `nginx`, `git` and `supervisor`. `7.4` and `8.0`
therefore carry node 16, the same age as their PHP series. That is deliberate: a
project that still needs PHP 7.4 or 8.0 is unlikely to run a newer node, and the
alternative is a second apk repository in those two directories, for a version
that matches no other part of the image. The versions an image really has are in
its own `/etc/laserstack/versions.txt`.

The `8.6` directory builds: Alpine carries `php86` in the `edge/testing`
repository, and the Dockerfile installs the series from there. PHP 8.6 has no
stable release yet (GA is planned for 19 November 2026), so the image is a
release candidate, and `latest` stays on `8.5` because
`.github/workflows/nightly-publish.yml` sets `APP_LATEST=8.5`. When Alpine moves
`php86` to `edge/community`, delete the `ARG PHP_REPO` line from
`8.6/Dockerfile`; nothing else changes.

A directory whose series lives outside `main` and `community` names its
repository in an `ARG PHP_REPO` line. `buildx.sh` reads that value, so the
version resolution installs the series the same way the Dockerfile does.

`.buildx-skip` holds one version directory per line. Blank lines and lines that
are not `major.minor` are ignored. It is empty at the moment.

Each image runs nginx (vhosts from `nginx-site.conf` on port 80) and php-fpm
under supervisord. Xdebug is loaded with `xdebug.mode=profile`, and `phpunit`
is the version `composer global require` resolved for that PHP series. Every
image from `7.4` to `8.5` carries the `memcached` extension, so a client can use
the memcached profile of the stack as a cache store. `8.6` does not: Alpine has
no package for it and pecl's `memcached` 3.4.0 does not compile against 8.6. The
mysql client and the postgres client (`psql`, `pg_dump`) are installed, for
`laser mysql` and `laser psql` of
[laserstack](https://github.com/sdbruder/laserstack).

`buildx-orbstack.sh` tags each image `laserstack/app:<php-version>` and
`laserstack/app:<major.minor>`, and gives the `APP_LATEST` directory the
`latest` tag.

## What is inside an image

Every image writes its own inventory at build time, so the answer to "which php,
which composer, which node is in there" comes from the image and not from this
file:

```sh
docker run --rm --entrypoint cat laserstack/app:8.5 /etc/laserstack/versions.txt
docker run --rm --entrypoint cat laserstack/app:8.5 /etc/laserstack/packages.txt
```

`versions.txt` carries one tool per line: php, composer, phpunit, node, npm,
yarn, nginx, git and supervisor. A tool that an image does not carry has no
line, so the file of the production overlay is shorter than the file of the
image it builds on. `packages.txt` is `apk info -v`, the whole apk inventory, at
about 150 lines per image.

The table above is the policy: which Alpine release and which PHP series each
directory takes. Its patch versions are a snapshot of the day the table was
written — for the exact numbers, ask the image. `CHANGELOG.md` holds the changes
that matter (a series added or dropped, a base moved, a pin introduced), each
entry with the versions the images carried at that moment.


## Publishing

`buildx.sh` builds every directory for `linux/amd64` and `linux/arm64`, pushes
`laserstack/app:<major.minor>` and `laserstack/app:<php-version>`, and gives
`latest` to the newest directory (or to `APP_LATEST`, when set; the workflow
sets it to `8.5`, so a release candidate cannot take `latest`). It reads
`HUB_USER` and `HUB_PASSWORD` from the environment or from `.env`.

`BUILDX_CACHE=gha` turns on the GitHub Actions build cache. A failed cache
does not block the build; the script retries without it.

After the push of each image, the script runs it and prints
`/etc/laserstack/versions.txt`, the file the image writes for itself (see "What
is inside an image"). The versions of an image are therefore in the log of the
run that published it, and — when a workflow runs the script — on the summary
page of that run.

`.github/workflows/nightly-publish.yml` runs the same script every night at
01:00 UTC, and on demand from the Actions tab. It needs two repository
secrets:

| Secret         | Value                                            |
| -------------- | ------------------------------------------------ |
| `HUB_USER`     | Docker Hub user name                             |
| `HUB_PASSWORD` | Docker Hub access token with read and write access |


## Dependency updates

`renovate.json5` configures [Renovate](https://docs.renovatebot.com/), and
`.github/workflows/renovate.yml` runs it on this repository. The run is
self-hosted: it uses a token of this repository, and not the hosted app. It
needs one repository secret:

| Secret          | Value                                                           |
| --------------- | --------------------------------------------------------------- |
| `RENOVATE_TOKEN` | classic token with the scopes `public_repo` and `workflow`, or a fine-grained token of this repository with Contents, Pull requests, Issues and Workflows set to read and write |

The `workflow` permission is necessary, because Renovate changes files in
`.github/workflows`. The GITHUB_TOKEN of the job will not do: a pull request
that a bot opens needs a manual approval before a workflow runs on it, and
`build-pull-request.yml` is that workflow.

The job runs every Monday at 04:00 UTC. That cron is the cadence of the
branches: `renovate.json5` holds no schedule of its own, so a manual dispatch of
the workflow behaves exactly like the scheduled run.

| Item | What Renovate does |
| ---- | ------------------ |
| `actions/checkout`, `docker/setup-qemu-action`, `renovatebot/github-action` | Pins each action to a commit digest, and keeps the pin current. The nightly publish runs with `HUB_PASSWORD`, so a moved tag is a supply chain risk |
| `runs-on: ubuntu-24.04` | Opens a pull request for a newer Ubuntu runner |
| `renovate-version` of `renovate.yml` | Bumps the pinned Renovate version. The manager reads the input of the action and knows the tag of the image |
| `ARG COMPOSER_VERSION` of every Dockerfile | Bumps the pinned composer, through the marker comment above the line. The version is a packagist release, and one version serves every series: composer 2.x needs PHP 7.2.5 or newer |
| `FROM alpine:` of `8.4` and `8.5` | Proposes a newer stable Alpine, and waits for approval on the dependency dashboard |

Renovate never moves the `FROM alpine:` line of the other directories. The rule
above, "the newest Alpine release that still packages that series", is not
visible to Renovate: the Alpine that adds a release drops an older series, so
`7.4` to `8.3` hold the last Alpine that carries their series.

Four items stay hand-managed, on purpose:

- the apk packages. No Dockerfile writes a version, and the nightly publish
  rebuilds every image with `apk upgrade`, so a pin would hold every image
  back.
- the PHP patch version. `buildx.sh` resolves it from apk at build time, from
  the `#PHP` marker of each Dockerfile.
- the `phpunit` of the images. `composer global require phpunit/phpunit`
  resolves the newest phpunit that the series can run — 9.6 for 7.4 and 8.0,
  10.5 for 8.1, 11.5 for 8.2, 12.5 for 8.3, 13.4 for 8.4 and newer. A pin would
  replace that with a matrix of constraints per directory.
- `prod/digests.lock`. Its digest is the one of the image the nightly publish
  pushed, and it changes every night, so Renovate would open a pull request
  every day. `./prod/build.sh --update` stays the checkpoint.

`build-pull-request.yml` builds the images that a pull request changes, and
pushes nothing: `docker build` for each changed version directory, and
`./prod/build.sh` when a file under `prod/` or `examples/` changes. It is the
check of a Renovate pull request, and it needs the full clone, because it diffs
against the base branch. `buildx.sh` cannot serve: it logs in and pushes.

Check a change of `renovate.json5` without a branch or a pull request:

```sh
docker run --rm -v "$PWD":/usr/src/app -w /usr/src/app \
  -e RENOVATE_CONFIG_FILE=/usr/src/app/renovate.json5 \
  renovate/renovate --platform=local --dry-run=lookup
```

The command prints every dependency it found and every update it would propose.
`--dry-run=extract` stops after the dependency extraction. The `local` platform
does not read the config of the repository, so the `RENOVATE_CONFIG_FILE`
variable is necessary. Add `--platform=github`, with `RENOVATE_TOKEN` and
`RENOVATE_REPOSITORIES=<owner>/<repo>`, to include the actions of the workflow:
those need a GitHub token for their lookup.


## License

 Laser Stack (and this container image) is open-sourced software licensed under [BSD license](LICENSE.md).
