{ stdenv, fetchurl, fetchgit
, pkgconfig, makeWrapper, autoreconfHook, fetchpatch
, coreutils, libxml2, gnutls, perl, python2, attr, glib, docutils
, iproute, iptables, readline, lvm2, utillinux, systemd, libpciaccess, gettext
, libtasn1, ebtables, libgcrypt, yajl, pmutils, libcap_ng, libapparmor
, dnsmasq, libnl, libpcap, libxslt, xhtml1, numad, numactl, perlPackages
, curl, libiconv, gmp, zfs, parted, bridge-utils, dmidecode, dbus, libtirpc, rpcsvc-proto
, enableXen ? false, xen ? null
, enableIscsi ? false, openiscsi
, enableCeph ? false, ceph
}:

with stdenv.lib;

# if you update, also bump <nixpkgs/pkgs/development/python-modules/libvirt/default.nix> and SysVirt in <nixpkgs/pkgs/top-level/perl-packages.nix>
let
  buildFromTarball = stdenv.isDarwin;
in stdenv.mkDerivation rec {
  pname = "libvirt";
  version = "6.3.0";

  src =
    if buildFromTarball then
      fetchurl {
        url = "http://libvirt.org/sources/${pname}-${version}.tar.xz";
        sha256 = "1xcng497hs1gary3pz3fp590a4r1kqs4d0d8k5p370j0scw981kl";
      }
    else
      fetchgit {
        url = "git://libvirt.org/libvirt.git";
        rev = "v${version}";
        sha256 = "129b3p72jlb40dsidak3nvpssv75xx2v99y63gzp5k074fp8y8x4";
        fetchSubmodules = true;
      };

  patches = [
    ./0001-Fix-build-with-libtirpc.patch
  ];

  nativeBuildInputs = [ makeWrapper pkgconfig docutils rpcsvc-proto ]
    ++ optionals (!buildFromTarball) [ autoreconfHook ];
  buildInputs = [
    libxml2 gnutls perl python2 readline gettext libtasn1 libgcrypt yajl
    libxslt xhtml1 perlPackages.XMLXPath curl libpcap glib dbus libtirpc
  ] ++ optionals stdenv.isLinux [
    libpciaccess lvm2 utillinux systemd libnl numad zfs
    libapparmor libcap_ng numactl attr parted
  ] ++ optionals (enableXen && stdenv.isLinux && stdenv.isx86_64) [
    xen
  ] ++ optionals enableIscsi [
    openiscsi
  ] ++ optionals enableCeph [
    ceph
  ] ++ optionals stdenv.isDarwin [
    libiconv gmp
  ];

  preConfigure = ''
    PATH=${stdenv.lib.makeBinPath ([ dnsmasq ] ++ optionals stdenv.isLinux [ iproute iptables ebtables lvm2 systemd numad ] ++ optionals enableIscsi [ openiscsi ])}:$PATH
    # the path to qemu-kvm will be stored in VM's .xml and .save files
    # do not use "''${qemu_kvm}/bin/qemu-kvm" to avoid bound VMs to particular qemu derivations
    substituteInPlace src/lxc/lxc_conf.c \
      --replace 'lxc_path,' '"/run/libvirt/nix-emulators/libvirt_lxc",'
    patchShebangs . # fixes /usr/bin/python references
    mkdir -p build && cd build
  '';

  configureScript = "../configure";

  dontAddDisableDepTrack = true;

  configureFlags = [
    "--with-runstatedir=/run" # TODO: remove when autoconf 1.70 is released
    "--localstatedir=/var"
    "--sysconfdir=/var/lib"
    "--with-libpcap"
    "--with-qemu"
    "--with-vmware"
    "--with-vbox"
    "--with-test"
    "--with-esx"
    "--with-remote"
    "--with-polkit"
  ] ++ optionals stdenv.isLinux [
    "QEMU_BRIDGE_HELPER=/run/wrappers/bin/qemu-bridge-helper"
    "QEMU_PR_HELPER=/run/libvirt/nix-helpers/qemu-pr-helper"
    "EBTABLES_PATH=${ebtables}/bin/ebtables-legacy"
    "CFLAGS=-I${libtirpc.dev}/include/tirpc"
    "--with-attr"
    "--with-apparmor"
    "--with-secdriver-apparmor"
    "--with-numad"
    "--with-macvtap"
    "--with-virtualport"
    "--with-storage-disk"
  ] ++ optionals (stdenv.isLinux && zfs != null) [
    "--with-storage-zfs"
  ] ++ optionals enableIscsi [
    "--with-storage-iscsi"
  ] ++ optionals enableCeph [
    "--with-storage-rbd"
  ] ++ optionals stdenv.isDarwin [
    "--with-init-script=none"
  ];

  installFlags = [
    "runstatedir=${placeholder "out"}/run"
    "localstatedir=$(TMPDIR)/var"
    "sysconfdir=$(out)/var/lib"
  ];

  postInstall = let
    binPath = [ iptables iproute pmutils numad numactl bridge-utils dmidecode dnsmasq ebtables ] ++ optionals enableIscsi [ openiscsi ];
  in ''
    substituteInPlace $out/libexec/libvirt-guests.sh \
      --replace 'ON_BOOT=start'       'ON_BOOT=''${ON_BOOT:-start}' \
      --replace 'ON_SHUTDOWN=suspend' 'ON_SHUTDOWN=''${ON_SHUTDOWN:-suspend}' \
      --replace "$out/bin"            '${gettext}/bin' \
      --replace 'lock/subsys'         'lock' \
      --replace 'gettext.sh'          'gettext.sh
  # Added in nixpkgs:
  gettext() { "${gettext}/bin/gettext" "$@"; }
  '
  '' + optionalString stdenv.isLinux ''
    substituteInPlace $out/lib/systemd/system/libvirtd.service --replace /bin/kill ${coreutils}/bin/kill
    rm $out/lib/systemd/system/{virtlockd,virtlogd}.*
    wrapProgram $out/sbin/libvirtd \
      --prefix PATH : /run/libvirt/nix-emulators:${makeBinPath binPath}
  '';

  enableParallelBuilding = true;

  NIX_CFLAGS_COMPILE = "-fno-stack-protector";

  meta = {
    homepage = "http://libvirt.org/";
    repositories.git = "git://libvirt.org/libvirt.git";
    description = ''
      A toolkit to interact with the virtualization capabilities of recent
      versions of Linux (and other OSes)
    '';
    license = licenses.lgpl2Plus;
    platforms = platforms.unix;
    maintainers = with maintainers; [ fpletz globin ];
  };
}
