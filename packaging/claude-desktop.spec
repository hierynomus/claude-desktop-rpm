#
# spec file for package claude-desktop
#
# Copyright (c) 2026, jeroen
#
# All license terms are preserved from the original .deb payload.
# NOTE: claude-desktop is Anthropic's proprietary desktop app. The "MIT"
# tag below is a packaging placeholder matching the local build; the app
# ships LICENSES.chromium.html (Chromium, BSD-3-Clause) plus Apache/BSD
# for the bundled virtiofsd. Revisit the License tag before any external
# submission.
#

# SHA256 of the upstream .deb, taken from Anthropic's apt Packages index
# (dists/stable/main/binary-amd64/Packages, field "SHA256:"). Bumped in
# lockstep with Version by scripts/bump-version.sh. Verified in %prep so a
# changed-out-from-under-us payload fails the build instead of shipping.
%global deb_sha256 80182e8511c6bbee6de26c7ee225fbd2a9aba2274ef1405a1d89cd8fe7a380dc

Name:           claude-desktop
Version:        1.40609.1
Release:        4
Summary:        Desktop application for Claude (Chat, Cowork, Code)
License:        MIT
URL:            https://claude.ai
# Fetched at build time by the _service download_url service (see _service).
# Kept as a bare filename so OBS does not treat Source0 as a stored blob.
Source0:        claude-desktop_%{version}_amd64.deb

ExclusiveArch:  x86_64
# chrome-sandbox is SUID-root (Electron's sandbox helper refuses to start
# without it). The SUID bit is declared to the SUSE permissions framework
# via a /usr/share/permissions/permissions.d drop-in; 'permissions'
# (permctl/chkstat) applies and re-applies the mode at install time.
PreReq:         permissions
BuildRequires:  fdupes

# Mapping of the .deb's Depends onto openSUSE Leap 16 packages:
#   libgtk-3-0        -> libgtk-3-0
#   libnotify4        -> libnotify4
#   libnss3           -> mozilla-nss
#   xdg-utils         -> xdg-utils
#   libatspi2.0-0     -> at-spi2-core
#   libdrm2           -> libdrm2
#   libgbm1           -> libgbm1
#   libxcb-dri3-0     -> libxcb-dri3-0
#   libsecret-1-0     -> libsecret-1-0
#   libc6 (>= 2.34)   -> glibc (always present)
#   libxtst6          -> libXtst6
#   libuuid1          -> libuuid1
#   xdg-desktop-portal-> xdg-desktop-portal
#   trash alt group   -> gvfs (gvfs-trash) or kde-cli-tools6 (KIO trash);
#                        keep gvfs as the portable one
Requires:       glibc
Requires:       libgtk-3-0
Requires:       libnotify4
Requires:       mozilla-nss
Requires:       xdg-utils
Requires:       at-spi2-core
Requires:       libdrm2
Requires:       libgbm1
Requires:       libxcb-dri3-0
Requires:       libsecret-1-0
Requires:       libXtst6
Requires:       libuuid1
Requires:       xdg-desktop-portal
Requires:       gvfs

# Deb Recommends (audio + app indicator + certs + Cowork VM stack)
Recommends:     libpulse0
Recommends:     libappindicator3-1
Recommends:     ca-certificates
Suggests:       qemu
Suggests:       ovmf
Suggests:       virtiofsd

%description
Claude desktop application for Linux (beta). Provides Chat, Cowork and
Claude Code in a native app. Upstream only ships an amd64/.deb build;
this package repackages the official .deb payload for RPM systems.
Cowork additionally needs a KVM-capable machine, QEMU, OVMF and
virtiofsd, plus the user in the KVM group.

%prep
# Integrity check: the .deb is fetched over TLS by the download_url service;
# pin it to the checksum Anthropic publishes in their apt index as well.
echo '%{deb_sha256}  %{SOURCE0}' | sha256sum -c -
# The .deb is an ar archive: debian-binary, control.tar.xz, data.tar.xz
ar x %{SOURCE0}
mkdir -p payload
tar -xJf data.tar.xz -C payload

%build
# Nothing to compile: self-contained Electron payload.
# Strip the two shipped objects that still carry debug info.
strip --strip-unneeded payload/usr/lib/claude-desktop/libvulkan.so.1
strip --strip-unneeded payload/usr/lib/claude-desktop/resources/app.asar.unpacked/node_modules/node-pty/prebuilds/linux-x64/pty.node

%install
install -dm 0755 %{buildroot}/usr/lib
cp -a payload/usr/lib/claude-desktop %{buildroot}/usr/lib/
install -dm 0755 %{buildroot}/usr/bin
ln -sf ../lib/claude-desktop/claude-desktop %{buildroot}/usr/bin/claude-desktop
install -dm 0755 %{buildroot}/usr/share/applications
cp -a payload/usr/share/applications/com.anthropic.Claude.desktop \
    %{buildroot}/usr/share/applications/
install -dm 0755 %{buildroot}/usr/share/icons
cp -a payload/usr/share/icons/hicolor %{buildroot}/usr/share/icons/

# The Electron payload ships many byte-identical files (icon light/dark
# pairs, content-hashed JS chunks); hardlink them. Must be the %fdupes
# macro, not bare `fdupes`: the macro recurses, plain fdupes does not.
%fdupes %{buildroot}

# Electron sandbox helper: must be SUID root or the app refuses to start.
# The bit is declared via the permissions.d drop-in below; permctl applies
# it at install time (kept here so the packaged bit matches the profile).
chmod 4755 %{buildroot}/usr/lib/claude-desktop/chrome-sandbox

# SUSE permissions framework drop-in: declares the SUID helper so
# permctl/chkstat manage its mode instead of it being an unexplained bit.
install -dm 0755 %{buildroot}/usr/share/permissions/permissions.d
cat > %{buildroot}/usr/share/permissions/permissions.d/claude-desktop <<'EOF'
# Claude Desktop: Electron SUID sandbox helper (upstream ships 4755)
/usr/lib/claude-desktop/chrome-sandbox root:root 4755
EOF

%files
%defattr(-,root,root)
/usr/bin/claude-desktop
/usr/lib/claude-desktop
/usr/share/applications/com.anthropic.Claude.desktop
/usr/share/icons/hicolor
/usr/share/permissions/permissions.d/claude-desktop
# SUID bit is managed by the permissions framework (permctl/chkstat via the
# drop-in above); keep rpm's own verifier from flagging the mode it manages.
%verify(not user group mode)
%attr(04755,root,root)
/usr/lib/claude-desktop/chrome-sandbox

%verifyscript
/usr/bin/chkstat -n --warn --system -e /usr/lib/claude-desktop/chrome-sandbox 1>&2

%post
%set_permissions /usr/lib/claude-desktop/chrome-sandbox
gtk-update-icon-cache -q /usr/share/icons 2>/dev/null || :
update-desktop-database -q /usr/share/applications 2>/dev/null || :

%postun
gtk-update-icon-cache -q /usr/share/icons 2>/dev/null || :
update-desktop-database -q /usr/share/applications 2>/dev/null || :

%changelog
* Wed Sep 02 2026 jeroen <jeroen@hierynomus.com> - 1.40609.1-4
- Fix fdupes: use the %%fdupes macro (recurses) instead of bare fdupes,
  which was a no-op - clears files-duplicated-waste + files-duplicate
- Drop "ai"/"qemu"/"kvm" spelling-errors (Summary + %%description wording)
- Add claude-desktop-rpmlintrc for the upstream-inherent / deliberate
  findings (static Go binaries, PIE, setgroups, gethostbyname, the
  explicit lib Requires). permissions-file-unauthorized stays: it is a
  BlockedFilter and needs SUSE security review to whitelist.

* Wed Sep 02 2026 jeroen <jeroen@hierynomus.com> - 1.40609.1-3
- Move to scmsync: package source is the GitHub repo, built via OBS
  SCM/CI workflow integration (PR builds + auto-sync on push to main)
- Verify the .deb SHA256 (from Anthropic's apt index) in %prep;
  drop the inert _servicedata.xml checksum pin (download_url does not
  consume it)

* Wed Sep 02 2026 jeroen <jeroen@localhost> - 1.40609.1-2
- Declare SUID chrome-sandbox to the SUSE permissions framework
  (permissions.d drop-in + permctl/chkstat scriptlets)
- fdupes: hardlink byte-identical Electron payload files
- strip libvulkan.so.1 and pty.node
- ExclusiveArch instead of BuildArch; literal scriptlet paths

* Wed Sep 02 2026 jeroen <jeroen@localhost> - 1.40609.1-1
- Initial import of upstream .deb payload as native RPM (OBS home:hierynomus)
