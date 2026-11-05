# OpenSSH on musl: CVE-2026-123158 and these images

2026-11-05

## The vulnerability

An sshd password-authentication bypass affects Linux systems that use musl
libc with PAM disabled. Alpine Linux is the common case.

An account whose password field in `/etc/shadow` is `*` — an account that must
never accept a password, for example a key-only user or the locked root of
Alpine — accepts any password of 257 to 1024 bytes. One connection is enough.

The condition:

- sshd runs on musl (Alpine, OpenWRT, Buildroot, Yocto)
- it does not use PAM: Alpine's `openssh-server` is built without PAM, or you
  set `UsePAM no`
- `PasswordAuthentication` is `yes`, the OpenSSH default
- one account has a `*` field and some other account has a real password

`PermitRootLogin prohibit-password`, the default, still protects root.

Cause: musl `crypt()` returns the string `*` when it cannot compute a hash,
for example for a password beyond its 256-byte limit, and sshd accepts that as
a match. OpenSSH fixed this in 10.6p2, released 2026-11-05; the CVE is
CVE-2026-123158 (CVSS 8.1).

## These images are not affected

The app images contain no sshd and no ssh client, so the vulnerability has no
target. Nothing in this repository installs or starts sshd: nginx and php-fpm
run under supervisord.

Evidence:

```
$ docker run --rm laserstack/app:8.5 sh -c 'apk info | grep -ci ssh; ls /usr/sbin/sshd'
0
ls: /usr/sbin/sshd: No such file or directory

$ docker run --rm laserstack/app:8.6 sh -c 'apk info | grep -ci ssh; ls /usr/bin/ssh'
0
ls: /usr/bin/ssh: No such file or directory

$ docker run --rm laserstack/app:7.4 sh -c 'apk info | grep -ci ssh'
0

$ docker run --rm laserstack/app-prod:8.6 sh -c 'apk info | grep -ci ssh'
0

$ grep -rniE 'openssh|sshd|dropbear' --include='*' .   # no match outside .git
```

The images hold 143 packages each. None has `ssh` in its name.

## If you add sshd inside one of these images

The version you get depends on the Alpine branch of the image. Every branch
rebuilt `openssh-server` on 2026-11-05, the day of the fix, except the Alpine
3.15 of the `7.4` image:

| Image | Alpine | `openssh-server` | Built | Fix |
| ----- | ------ | ---------------- | ----- | --- |
| `7.4` | 3.15 | 8.8_p1-r1 | 2021-11-16 | **no**, and 3.15 is end of life |
| `8.0` | 3.16 | 9.0_p1-r6 | 2026-11-05 | yes |
| `8.1` | 3.19 | 9.6_p1-r3 | 2026-11-05 | yes |
| `8.2` | 3.22 | 10.0_p1-r11 | 2026-11-05 | yes |
| `8.3`, `8.4`, `8.5` | 3.24 | 10.3_p1-r2 | 2026-11-05 | yes |
| `8.6` | edge | 10.6_p2-r0 | 2026-11-05 | yes, the upstream version |

Check it the same way:

```
curl -sL https://dl-cdn.alpinelinux.org/alpine/v3.24/main/aarch64/APKINDEX.tar.gz \
  | tar xzO APKINDEX | grep -A2 '^P:openssh-server$'
```

The `7.4` image is the only one that would install a vulnerable sshd. It also
runs an Alpine branch that receives no updates at all.

Note that the `laser` user of the development images has an empty password
field (`passwd -d laser laser`). That is a different field from `*`, and
OpenSSH refuses an empty password by default (`PermitEmptyPasswords no`). Do not
set that option to `yes` in an image with the `laser` user.

## If you run sshd on Alpine outside these images

```
apk upgrade openssh
rc-service sshd restart
```

The restart is required: the running daemon keeps the vulnerable code. When you
cannot update, close the hole with password logins instead:

```
echo "PasswordAuthentication no" > /etc/ssh/sshd_config.d/00-no-passwords.conf
rc-service sshd restart
```

## Sources

- <https://sshhole.com> — the write-up, with the musl commits
- <https://www.openssh.com/txt/release-10.6p2> — the release that fixes it
- <https://alpinelinux.org/posts/2026-11-05-openssh-password-authentication-bypass/> — the Alpine advisory
- <https://openwall.com/lists/musl/2026/11/05/4> — the musl advisory
- <https://lwn.net/Articles/1105464/> — LWN, on the affected configurations
