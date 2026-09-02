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

The package source **is this repo** — OBS mirrors it via `<scmsync>` and
rebuilds on every push to `main`. The 166 MB `.deb` is never committed:
`packaging/_service` fetches it at build time and `packaging/claude-desktop.spec`
verifies its SHA256 in `%prep` against the value in Anthropic's apt index.

| path | what |
|---|---|
| `packaging/claude-desktop.spec` | the recipe (dependency mapping, SUID sandbox handling, `%prep` checksum) |
| `packaging/_service` | `download_url` for the upstream `.deb` |
| `.obs/workflows.yml` | OBS SCM/CI: build each PR in `home:hierynomus:ci`, report status back |
| `.github/workflows/upstream-bump.yml` | daily — open a PR when Anthropic publishes a newer build |
| `scripts/bump-version.sh` | rewrite `packaging/` from the apt index (no `.deb` download) |
| `scripts/local-build.sh` | fetch the `.deb` + `rpmbuild -bb` locally, to test before OBS |
| `scripts/obs-bootstrap.sh` | one-time OBS setup (`:ci` project + `<scmsync>`) |
| `docs/obs-setup.md` | the one-time token + webhook steps |
| `docs/worklog.md` | history / rpmlint notes |

## Update flow

1. `upstream-bump.yml` (or `scripts/bump-version.sh` by hand) opens a PR
   bumping `Version` + `%global deb_sha256` + the `_service` URL.
2. OBS builds the PR in `home:hierynomus:ci`; the check lands on the PR.
3. Merge → OBS re-syncs and rebuilds `home:hierynomus/claude-desktop`.

## Local build

```sh
scripts/local-build.sh        # -> ./dist/claude-desktop-*.x86_64.rpm
```

Needs `rpm-build`. Same `%prep` checksum gate as OBS.

## One-time OBS wiring

See [`docs/obs-setup.md`](docs/obs-setup.md): run `scripts/obs-bootstrap.sh`,
then create the OBS workflow token and the GitHub webhook.

## Notes

- Unsigned local builds: `sudo zypper --no-gpg-checks install ./dist/*.rpm`,
  or add the OBS repo (signed) as above.
- `License: MIT` in the spec is a packaging placeholder — Claude Desktop is
  Anthropic proprietary; the payload bundles Chromium (BSD-3-Clause) and
  virtiofsd (Apache/BSD). Revisit before any non-home submission.
- If a future `.deb` moves files or adds SUID helpers, update `%files` and
  the permissions drop-in in the spec.
