# Changelog

What changed in these images, and why. A new patch version does not belong
here: the nightly publish rebuilds every image, and each image carries its own
inventory — `/etc/laserstack/versions.txt`, see "What is inside an image" in
README.md.

An entry is for a decision: a series added or dropped, a base image moved, a pin
introduced, a layer added or removed. Each entry carries the versions the images
had at the moment of the entry, so the history keeps the numbers without a file
that goes stale the next morning.

## 2026-11-10

### The composer of every image is pinned (#4)

`ARG COMPOSER_VERSION` with a `# renovate: datasource=packagist
depName=composer/composer` marker, above the installer step of every Dockerfile,
and the installer now takes `--version`. A rebuild of one directory gives the
same composer instead of whatever the installer offered that day, and Renovate
keeps the pin current. One version serves every series: composer 2.x needs PHP
7.2.5 or newer.

### Every image describes itself (#4)

The images write two files at build time, and a reader asks the image instead of
the README:

- `/etc/laserstack/versions.txt`: php, composer, phpunit, node, npm, yarn,
  nginx, git, supervisor. A tool the image does not carry has no line.
- `/etc/laserstack/packages.txt`: `apk info -v`, the whole apk inventory.

The nightly publish prints the first file and, when a workflow runs the script,
copies it to the summary of the run.

### phpunit stays rolling on purpose (#4)

`composer global require phpunit/phpunit` keeps resolving the newest phpunit a
series can run — 9.6 for 7.4 and 8.0, 10.5 for 8.1, 11.5 for 8.2, 12.5 for 8.3,
13.4 for 8.4 and newer. Pinning it would need a constraint matrix per
directory, to reproduce what the resolver already does.

### Dependency automation (#1, #2, #5, issue #3)

- Self-hosted Renovate, Monday 04:00 UTC, from `.github/workflows/renovate.yml`.
  It pins the actions of the workflows to a commit digest, tracks the runner of
  every workflow, and proposes the Alpine bump of `8.4` and `8.5` with approval
  on the dependency dashboard. The Alpine tags of `7.4` to `8.3` are frozen: each
  holds the last Alpine release that still packages its PHP series.
- `build-pull-request.yml` builds the images a pull request changes, and pushes
  nothing.
- `master` is protected by a ruleset: pull request only, the `build pull
  request` check green, no force push, no branch deletion. Only the owner has
  write access, and a merged branch is deleted.
- The old `php81` branch was deleted; it was an ancestor of `master` and held
  nothing of its own.

### Versions of the published images at 2026-11-10

| dir | php | composer | phpunit | node | npm | yarn | nginx | git | supervisor | apk |
| --- | --- | -------- | ------- | ---- | --- | ---- | ----- | --- | ---------- | --- |
| `7.4` | 7.4.33 | 2.11.1 | 9.6.38 | 16.20.2 | 8.1.3 | 1.22.17 | 1.20.2 | 2.34.8 | 4.2.2 | 119 |
| `8.0` | 8.0.30 | 2.11.1 | 9.6.38 | 16.20.2 | 8.10.0 | 1.22.19 | 1.22.1 | 2.36.6 | 4.2.4 | 118 |
| `8.1` | 8.1.34 | 2.11.1 | 10.5.66 | 20.15.1 | 10.2.5 | 1.22.19 | 1.24.0 | 2.43.7 | 4.2.5 | 152 |
| `8.2` | 8.2.35 | 2.11.1 | 11.5.57 | 22.23.4 | 11.6.4 | 1.22.22 | 1.28.3 | 2.49.1 | 4.2.5 | 147 |
| `8.3` | 8.3.36 | 2.11.1 | 12.5.43 | 24.22.1 | 11.12.1 | 1.22.22 | 1.30.6 | 2.54.0 | 4.3.0 | 148 |
| `8.4` | 8.4.27 | 2.11.1 | 13.4.6 | 24.22.1 | 11.12.1 | 1.22.22 | 1.30.6 | 2.54.0 | 4.3.0 | 148 |
| `8.5` | 8.5.12 | 2.11.1 | 13.4.6 | 24.22.1 | 11.12.1 | 1.22.22 | 1.30.6 | 2.54.0 | 4.3.0 | 147 |
| `8.6` | 8.6.0RC5 | 2.11.1 | 13.4.6 | 24.22.1 | 12.2.1 | 1.22.22 | 1.30.6 | 2.56.0 | 4.3.0 | 144 |

The composer of the published images is still 2.11.1: they were built at 08:05
UTC, and 2.11.2 appeared at 09:12 the same morning. That is the drift the pin of
this entry removes — the next rebuild of a directory carries the pinned version
whatever the installer offers.

### The old node in `7.4` and `8.0` stays

The table makes one fact visible: `node` in `7.4` and `8.0` is 16.20.2, because
those directories take their JavaScript toolchain from Alpine 3.15 and 3.16.
Node 16 is end-of-life, and no file said so before the table existed.

Decision: keep it. The JavaScript toolchain of an image follows the Alpine
release of its directory — the same rule that fixes its PHP series — and a
project that still needs PHP 7.4 or 8.0 is unlikely to run a newer node. The
alternative is a second apk repository in those two directories, for a version
that matches no other part of the image. So `7.4` and `8.0` carry node 16 until
the day their Alpine release carries something else, and those two directories
are frozen by the PHP series they serve.
