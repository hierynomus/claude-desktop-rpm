#
# spec file for package claude-desktop
#
# Copyright (c) 2026 Jeroen van Erp
# Packaging under the MIT License (see LICENSE at the repo root).
#
# All license terms are preserved from the original .deb payload.
# claude-desktop is Anthropic's proprietary desktop app (-> LicenseRef-
# SUSE-NonFree); it also ships LICENSES.chromium.html (Chromium,
# BSD-3-Clause) and Apache-2.0 for the bundled virtiofsd.
#

# SHA256 of the upstream .deb, taken from Anthropic's apt Packages index
# (dists/stable/main/binary-amd64/Packages, field "SHA256:"). Bumped in
# lockstep with Version by scripts/bump-version.sh. Verified in %%prep so a
# changed-out-from-under-us payload fails the build instead of shipping.
%global deb_sha256 80182e8511c6bbee6de26c7ee225fbd2a9aba2274ef1405a1d89cd8fe7a380dc

Name:           claude-desktop
Version:        1.40609.1
# OBS supplies the real release (lp160.N.M); 0 is the openSUSE convention.
Release:        0
Summary:        Desktop application for Claude (Chat, Cowork, Code)
License:        LicenseRef-SUSE-NonFree AND BSD-3-Clause AND Apache-2.0
URL:            https://claude.ai
# Fetched at build time by the _service download_url service (see _service).
# Kept as a bare filename so OBS does not treat Source0 as a stored blob.
Source0:        claude-desktop_%{version}_amd64.deb

ExclusiveArch:  x86_64
# Electron's chrome-sandbox is shipped NON-SUID (0755). Chromium prefers the
# unprivileged-user-namespace sandbox and only falls back to the SUID helper
# when userns is unavailable; openSUSE enables unprivileged userns by default
# (podman-rootless, flatpak). The sandbox stays fully active - this is not
# --no-sandbox. Dropping the SUID bit also drops the SUSE permissions-
# framework drop-in and rpmlint's SUID review flag. See README "Sandbox".
BuildRequires:  fdupes
BuildRequires:  desktop-file-utils

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
# Upstream ships Categories=Utility;Development; - two "main" categories,
# which desktop-file-validate/rpmlint reject (the entry would show up twice
# in the menu). Collapse to a single main category.
sed -i 's/^Categories=.*/Categories=Utility;/' \
    %{buildroot}/usr/share/applications/com.anthropic.Claude.desktop
desktop-file-validate %{buildroot}/usr/share/applications/com.anthropic.Claude.desktop
install -dm 0755 %{buildroot}/usr/share/icons
cp -a payload/usr/share/icons/hicolor %{buildroot}/usr/share/icons/

# The Electron payload ships many byte-identical files (icon light/dark
# pairs, content-hashed JS chunks); hardlink them. Must be the %%fdupes
# macro, not bare `fdupes`: the macro recurses, plain fdupes does not.
%fdupes %{buildroot}

# Ship chrome-sandbox NON-SUID (upstream .deb has it 4755). Chromium uses the
# user-namespace sandbox when unprivileged userns is available (openSUSE
# default) and never touches this helper; the SUID path is a fallback only.
# No SUID bit -> no permissions-framework drop-in, no rpmlint SUID review.
chmod 0755 %{buildroot}/usr/lib/claude-desktop/chrome-sandbox

# No %%post/%%postun: openSUSE runs update-desktop-database and
# gtk-update-icon-cache from file triggers (desktop-file-utils, gtk3) on
# /usr/share/applications and /usr/share/icons.

%files
%defattr(-,root,root)
/usr/bin/claude-desktop
/usr/lib/claude-desktop
/usr/share/applications/com.anthropic.Claude.desktop
/usr/share/icons/hicolor

%changelog
* Thu Sep 03 2026 jeroen <jeroen@hierynomus.com> - 1.40609.1-0
- Initial packaging: repackage Anthropic's Claude Desktop .deb as an
  openSUSE RPM, built from git via OBS scmsync. Non-SUID chrome-sandbox
  (user-namespace sandbox), SHA256-verified payload, rpmlint clean.
