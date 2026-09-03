# claude-desktop for openSUSE

Repackages Anthropic's official [Claude Desktop](https://claude.ai) Linux
beta (shipped only as an `amd64` `.deb`) into a native **RPM for openSUSE**,
built and GPG-signed by the [Open Build Service](https://build.opensuse.org)
project [`home:hierynomus`](https://build.opensuse.org/package/show/home:hierynomus/claude-desktop).

## Install

```sh
sudo zypper ar https://download.opensuse.org/repositories/home:hierynomus/openSUSE_Leap_16.0/home:hierynomus.repo
sudo zypper refresh
sudo zypper install claude-desktop
```

x86_64 only (upstream ships no other arch). Cowork additionally needs a
KVM-capable host with `qemu` + `ovmf` + `virtiofsd` and your user in the
`kvm` group.

## How it works

The package source **is this repo**. OBS mirrors `packaging/` via
`<scmsync>` and rebuilds when a push changes it. The 166 MB `.deb` is never
committed: `packaging/_service` fetches it at build time and
`packaging/claude-desktop.spec` verifies its SHA256 in `%prep` against the
value in Anthropic's apt index.

| path | what |
|---|---|
| `packaging/claude-desktop.spec` | the recipe — dependency mapping, `%prep` checksum, non-SUID sandbox |
| `packaging/claude-desktop-rpmlintrc` | rpmlint filters for upstream-inherent / deliberate findings |
| `packaging/_service` | `download_url` for the upstream `.deb` |
| `.obs/workflows.yml` | OBS SCM/CI — build each PR in a scratch project, report status back |
| `.github/workflows/upstream-bump.yml` | daily — open a PR when Anthropic publishes a newer build |
| `scripts/bump-version.sh` | rewrite `packaging/` from the apt index (no `.deb` download) |
| `scripts/local-build.sh` | fetch the `.deb` + `rpmbuild -bb` locally, to test before OBS |
| `scripts/obs-bootstrap.sh` | one-time OBS setup (`:ci` project, `<scmsync>`, runservice token) |
| `docs/obs-setup.md` | the one-time token + webhook steps |

## Update flow

1. `upstream-bump.yml` (or `scripts/bump-version.sh` by hand) opens a PR
   bumping `Version` + `%global deb_sha256` + the `_service` URL.
2. OBS test-builds the PR; the status check lands on it.
3. Merge → OBS re-syncs and rebuilds `home:hierynomus/claude-desktop`.

## Local build

```sh
scripts/local-build.sh        # -> ./dist/claude-desktop-*.x86_64.rpm
```

Needs `rpm-build`. Same `%prep` checksum gate as OBS.

## One-time OBS wiring

See [`docs/obs-setup.md`](docs/obs-setup.md): run `scripts/obs-bootstrap.sh`,
create a GitHub PAT and the `workflow` token, then add two GitHub webhooks
(push → `/trigger/webhook`, PR → `/trigger/workflow`).

## Sandbox

`chrome-sandbox` is shipped **non-SUID** (upstream's `.deb` sets it `4755`).
Chromium prefers the unprivileged **user-namespace sandbox** and only uses
the SUID helper as a fallback; openSUSE enables unprivileged user namespaces
by default (podman-rootless, flatpak rely on it), so the sandbox is fully
active. This is *not* `--no-sandbox`, and it's verified working on openSUSE.

If a host has unprivileged userns disabled, the app fails to start with
`The SUID sandbox helper binary was found, but is not configured correctly`.
Re-enable userns (`user.max_user_namespaces`), don't chmod the helper.

## Notes

- Unsigned local builds: `sudo zypper --no-gpg-checks install ./dist/*.rpm`,
  or add the OBS repo (signed) as above.
- `License:` is `LicenseRef-SUSE-NonFree AND BSD-3-Clause AND Apache-2.0` —
  Anthropic's app is proprietary; the payload bundles Chromium (BSD-3) and
  virtiofsd (Apache-2.0).
- If a future `.deb` moves files or adds SUID helpers, update `%files` and
  revisit the sandbox note above.

## License

The packaging in this repo (spec, `_service`, scripts, CI config) is
[MIT](LICENSE). It does not contain or redistribute Claude Desktop itself —
the app is Anthropic's, fetched from their apt repo at build time.
