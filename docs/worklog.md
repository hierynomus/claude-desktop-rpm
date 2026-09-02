# Claude Desktop → OBS: work log (2026-09-02)

Goal: install Anthropic's Claude Desktop beta (Linux) on openSUSE Leap 16 via
zypper, using a home OBS project so the package is GPG-signed by OBS.

## What works today

- **OBS project:** `home:hierynomus` on build.opensuse.org, repo
  `openSUSE_Leap_16.0` / `standard` / `x86_64`.
- **Package:** `claude-desktop`, revision 1 committed:
  `claude-desktop.spec`, `_service` (download_url), `_servicedata.xml`
  (sha512 pin). Build **SUCCEEDED**; RPM `claude-desktop-1.40609.1-1.x86_64.rpm`
  is published at
  `https://download.opensuse.org/repositories/home:hierynomus/openSUSE_Leap_16.0/x86_64/`.
- **Install on the desktop:**
  ```
  sudo zypper ar https://download.opensuse.org/repositories/home:hierynomus/openSUSE_Leap_16.0/home:hierynomus.repo
  sudo zypper refresh && sudo zypper install claude-desktop
  ```

## How we got there (bugs found & fixed, in order)

1. **osc workflow** — there is no `osc login`; first real command prompts for
   credentials (or pre-fill `~/.oscrc`). Committing files is `osc ci`/`osc
   commit`, **not** `osc up` (`osc up` only refreshes the working copy). New
   files must be staged with `osc addremove` first, or `up`/`ci` commit
   nothing.
2. **Server package creation** — `osc up` does not create a package on the
   server (404 "package not found"); `osc meta pkg home:hierynomus
   claude-desktop -F -` (from `_package` metadata) does.
3. **`osc meta prj`** — the file flag is `-F`/`--file` (or `-F -` for stdin),
   not `-c`. setup.sh now merges the build target into the *live* project
   metadata instead of replacing it, and is idempotent.
4. **`osc build <prj> <pkg> <repo> <arch>` doesn't exist** — `osc build` is a
   local build. Server builds trigger **automatically on commit** to a project
   that has the build target.
5. **`_service` schema** — an empty `<sourceSubdir></sourceSubdir>` element is
   rejected by the OBS server ("Did not expect element sourceSubdir"); removed.
6. Verification gotcha: `osc ls <prj> <pkg>` with two args lists top-level
   project namespaces, not the package's files; `osc status`/`osc log` in the
   working copy is the reliable check.

## rpmlint cleanup (in progress — this is the current work)

First OBS build reported **17 errors / 27 warnings** (report only, does not
block the build in a home project). Plan agreed with jeroen:

- **Option A (clean fixes):** fdupes (kills `files-duplicated-waste`,
  badness 100), `ExclusiveArch` instead of `BuildArch`, `strip
  --strip-unneeded` on `libvulkan.so.1` + `pty.node`, literal paths in
  `%post`/`%postun` (kills `percent-in-%post*`).
- **Option B (SUSE permissions framework for the SUID bit):** ship
  `/usr/share/permissions/permissions.d/claude-desktop` declaring
  `/usr/lib/claude-desktop/chrome-sandbox root:root 4755`, add
  `PreReq: permissions`, `%set_permissions ...` in `%post`, and a
  `%verifyscript` running
  `/usr/bin/chkstat -n --warn --system -e /usr/lib/claude-desktop/chrome-sandbox`
  (chkstat → permctl symlink; macros verified to expand to exactly what
  rpmlint's `SUIDPermissionsCheck` greps for).
- **Kept as-is by decision:** all 8 `explicit-lib-dependency` `Requires`
  (libgtk-3-0, libnotify4, libsecret-1-0, libuuid1, libXtst6, libdrm2,
  libgbm1, libxcb-dri3-0) — jeroen: leave them. 6 of the 8 are not direct
  NEEDED of any shipped ELF (verified with readelf), only libgtk-3/libgbm
  are auto-detected, so these are load-bearing for a bare install.
- **Intentionally left (upstream-inherent, not fixable without rebuilding
  the .deb):** 2x statically-linked-binary (github-mcp-server,
  cowork-linux-helper), position-independent-executable-suggested x2,
  gethostbyname, no-%check-section, setgroups-before-setuid, and
  invalid-desktopfile (cosmetic; .desktop passes desktop-file-validate
  locally).

### Spec changes already made (in `claude-desktop/claude-desktop.spec`,
Release bumped to 2, **not yet pushed to OBS**)

- `ExclusiveArch: x86_64`, `PreReq: permissions`, `BuildRequires: fdupes`
- `%build`: strips libvulkan.so.1 and pty.node
- `%install`: `fdupes %{buildroot}` + writes the permissions.d drop-in
- `%files`: `%verify(not user group mode)` + `%attr(04755,root,root)` on
  chrome-sandbox; drop-in file listed
- `%verifyscript` / `%post` as in option B; scriptlets use literal paths
- Verified locally: RPM builds clean, chrome-sandbox ships as
  `0104755 root root` with verify-attrs `0 0 0`.

### Open items (where we stopped)

1. **fdupes didn't take effect locally:** the call in %install is `fdupes
   %{buildroot}` (plain binary, installed locally) but on OBS the binary is
   not guaranteed present at %install time unless `BuildRequires: fdupes`
   pulls it in — it does in the OBS build env, but confirm hardlinks in the
   next OBS rpmlint log (`files-duplicated-waste` should be gone).
2. **`permissions-file-unauthorized`** on the new drop-in showed up in the
   *local* rpmlint run (FileDigestLocation wants the permissions.d path
   whitelisted / digests registered). Check whether OBS's rpmlint-mini flags
   it too; if so, either add a `claude-desktop.rpmlintrc` Source with
   `addFilter('permissions-file-unauthorized')` (accepted for reviewed
   drop-ins) or drop option B and keep a plain `chmod 4755` +
   `permissions-file-setuid-bit` (which is only gated for official SUSE
   submission, not for home projects).
3. Spelling errors (`ai`, `qemu`, `kvm` in Summary/%description) surfaced in
   the local run but not in the OBS log — OBS's opensuse.toml likely
   whitelists them; verify after the next OBS build.
4. Push the v2 spec: `cd home:hierynomus/claude-desktop && osc ci`
   (working copy lives in `obs/home:hierynomus/`, owned by jeroen now),
   watch `osc results` + `osc rpmlintlog openSUSE_Leap_16.0 x86_64`.

Local build tree (odin): `~/rpmbuild/` — SOURCES has the .deb, latest
test RPM at `~/rpmbuild/RPMS/x86_64/claude-desktop-1.40609.1-2.x86_64.rpm`.

---

# 2026-09-02 (later): move to a GitHub repo + OBS SCM/CI integration

Reworked from "prepare files locally, `osc ci` to OBS" into: **GitHub repo
is the package source**, OBS pulls it via `<scmsync>`, PRs get test-built.

## Why

- Git history = package history, PRs get reviewed + build-tested before
  they reach `home:hierynomus`.
- The upstream version-bump job needs **no OBS credentials** — it only
  touches git; OBS reacts to the push.
- The old `_servicedata.xml` sha512 pin was **inert**: `download_url` is a
  plain `wget` and never reads it. Integrity moved into `%prep`
  (`sha256sum -c` against Anthropic's apt-index `SHA256:` field).

## New layout

```
packaging/claude-desktop.spec       canonical recipe (was obs/claude-desktop/)
packaging/claude-desktop-rpmlintrc  filters for upstream-inherent findings
packaging/_service                  download_url only; no _servicedata.xml
.obs/workflows.yml              PR builds -> branch into home:hierynomus:ci
.github/workflows/upstream-bump.yml   daily: open a bump PR if upstream moved
scripts/bump-version.sh         rewrite spec+_service from the apt index
scripts/local-build.sh          fetch .deb + rpmbuild -bb, for local testing
scripts/obs-bootstrap.sh        one-time: create :ci project, set <scmsync>
docs/obs-setup.md               the manual token + webhook steps
```

Deleted: `obs/` (osc checkout, setup.sh, update-obs.sh, prepared files),
root `claude-desktop/claude-desktop.spec` + `update.sh` (the standalone
local-rpmbuild variant — folded into `packaging/` + `scripts/local-build.sh`).

---

# 2026-09-02 (later still): rpmlint on the release-2 OBS build

`osc ci` of release 2 went through; OBS published
`claude-desktop-1.40609.1-lp160.2.1.x86_64.rpm`. Pulled it and ran
rpmlint 2.10 locally with `/etc/xdg/rpmlint/opensuse.toml` (what OBS uses):
**17 errors, 21 warnings, 125 badness.** Analysed each; release 4 addresses
them.

## Fixed in release 4 (spec)

1. **`files-duplicated-waste` (badness 100) + 15x `files-duplicate`** -
   the real bug: `%install` ran bare `fdupes %{buildroot}`, which does NOT
   recurse, so it hardlinked nothing (confirmed: the shipped icons are
   separate inodes). Changed to the `%fdupes %{buildroot}` macro (the
   openSUSE wrapper, recurses + hardlinks). Links ~35 files.
2. **`spelling-error` x3 (`ai`, `qemu`, `kvm`)** - OBS's opensuse.toml does
   NOT whitelist them (WORKLOG guess was wrong). rpmlint's speller skips
   all-caps tokens, so: Summary "Claude.ai" -> "Claude"; %description
   "qemu"/"kvm" -> "QEMU"/"KVM".

## Filtered in release 4 (`packaging/claude-desktop-rpmlintrc`)

Verified locally that each regex matches a real finding (no
`unused-rpmlintrc-filter`) and that the finding disappears:

- `statically-linked-binary` x2, `position-independent-executable-suggested`
  x2 - upstream Go binaries (github-mcp-server, cowork-linux-helper)
- `missing-call-to-setgroups-before-setuid` - Electron chrome-sandbox +
  node-pty pty.node (upstream)
- `binary-or-shlib-calls-gethostbyname` - Chromium net stack
- `explicit-lib-dependency` x8 - the deliberate load-bearing Requires

## Accepted residual - cannot be fixed at home:-project level

**`permissions-file-unauthorized` (badness 10)** on
`/usr/share/permissions/permissions.d/claude-desktop`. Emitted by
`FileDigestCheck`, and it is listed in opensuse.toml's **`BlockedFilters`**
-> `addFilter()` is ignored for it (tested: filter reported unused, error
still printed). The plain-`chmod 4755` alternative trades it for
`permissions-file-setuid-bit`, also a BlockedFilter. The only way to
silence it is registering the drop-in's digests in rpmlint's
`permissions-whitelist.toml` upstream, which needs SUSE security-team
review and does not apply to `home:` projects. Keeping the drop-in (it is
the correct mechanism and what an eventual official submission needs) and
living with the one non-fatal error.

## Also seen locally, not real

- `unknown-key b6bf489c` - just this laptop lacking the OBS project key;
  OBS signs with a key its own rpmlint trusts.

## Projected release-4 rpmlint

**1 error (`permissions-file-unauthorized`), 0 warnings, badness 10** -
from 17E / 27W originally. Needs an actual OBS rebuild to confirm the
`%fdupes` + spelling changes (no `rpmbuild` on odin to pre-check).

---

# 2026-09-02 (night): scmsync push webhook + r4/r5 rpmlint

Repo pushed to github.com/hierynomus/claude-desktop-rpm. scmsync set on the
package (`?subdir=packaging#main`). First sync grabbed `d586500` (r3) and
then **stopped** — pushes weren't rebuilding.

## The webhook bug

The GitHub webhook was pointed at `/trigger/workflow?id=<workflow-token>`.
OBS response to the push:

  > No steps were triggered for the workflow 'pull_request': the received
  > event matched no filter

`/trigger/workflow` **only** runs `.obs/workflows.yml` steps. Our file has
only a `pull_request` workflow, so a push to `main` did literally nothing -
the scmsync package never re-synced (`_scmsync.obsinfo` stuck on d586500).
obs-scm-bridge does not poll on its own here.

**Fix:** a *second* token + webhook.
- `osc token --create --operation runservice home:hierynomus claude-desktop`
  -> webhook `/trigger/webhook?id=<id>`, event Pushes. This re-pulls git.
- keep the workflow token/webhook for Pull requests only.
- manual equivalent: `osc service remoterun home:hierynomus claude-desktop`
  (used it to unblock; r4 then synced + built immediately).

docs/obs-setup.md and scripts/obs-bootstrap.sh updated for the two-webhook
setup. runservice token created: id 12231. workflow token: id 12228.

## r4 rpmlint (OBS, rpmlint 2.7): 2 E / 4 W / 11 badness

Down from 17 E / 27 W / 125. rpmlintrc filtered 36. Remaining:

- `permissions-file-unauthorized` (E, badness 10) - the known residual.
- `invalid-desktopfile` (E) - upstream ships `Categories=Utility;Development;`
  (two main categories). rpmlint 2.10 locally didn't flag it, 2.7 on OBS
  does. r5: `sed` it to `Categories=Utility;` in %install +
  `desktop-file-validate` (BuildRequires: desktop-file-utils).
- `macro-in-comment %prep` / `%fdupes`, `macro-in-%changelog %prep` (W x3) -
  bare `%word` in our own comments/changelog. r5: escaped to `%%word`.
- `no-%check-section` (W) - no upstream testsuite. r5: filtered in rpmlintrc.

Projected r5: **1 E (permissions-file-unauthorized) / 0 W.**

## r5 built: 1 E / 0 W / 10 badness  ->  rpmlint cleanup DONE

`claude-desktop-1.40609.1-lp160.6.1` published. Only `permissions-file-
unauthorized` remains (accepted, unfilterable). From the original
17 E / 27 W this is as clean as a home: project with a SUID helper gets.

Note: OBS replaces the spec's `Release:` with its own `lp160.<n>.<r>`
scheme, so the `Release:` field + changelog `-N` are documentation only.

## Status

- [x] repo on GitHub, scmsync set
- [x] webhook root-caused; two-webhook fix in docs + obs-bootstrap.sh
- [x] r5 built and published: **1 E / 0 W** (from 17 E / 27 W)
- [ ] **runservice webhook (id 12231) still not firing** - no "Triggered at"
      on the token after a push; forced every sync so far with
      `osc service remoterun`. User checking the GitHub webhook config
      (URL must be /trigger/webhook, Secret = token string, event Pushes).
- [ ] confirm PR build path (open a throwaway PR) + workflow token PAT
- [ ] upstream-bump action: needs repo setting "Allow GitHub Actions to
      create and approve pull requests"
