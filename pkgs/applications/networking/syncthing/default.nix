{ buildGoModule, stdenv, lib, procps, fetchFromGitHub, nixosTests }:

let
  common = { stname, target, postInstall ? "" }:
    buildGoModule rec {
      version = "1.8.0";
      name = "${stname}-${version}";

      src = fetchFromGitHub {
        owner  = "syncthing";
        repo   = "syncthing";
        rev    = "v${version}";
        sha256 = "047y2sy9zif19dlh098ihaski9f3b971q3mmqg97qgfzpa8z8fpr";
      };

      vendorSha256 = "0l08d96226l135cqbv1qqw0136f5nzw7likc0nmhcm6ynzv83kj2";

      doCheck = false;

      patches = [
        ./add-stcli-target.patch
      ];
      BUILD_USER="nix";
      BUILD_HOST="nix";

      buildPhase = ''
        runHook preBuild
        go run build.go -no-upgrade -version v${version} build ${target}
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        install -Dm755 ${target} $out/bin/${target}
        runHook postInstall
      '';

      inherit postInstall;

      passthru.tests = with nixosTests; {
        init = syncthing-init;
        relay = syncthing-relay;
      };

      meta = with lib; {
        homepage = "https://syncthing.net/";
        description = "Open Source Continuous File Synchronization";
        license = licenses.mpl20;
        maintainers = with maintainers; [ pshendry joko peterhoeg andrew-d ];
        platforms = platforms.unix;
      };
    };

in {
  syncthing = common {
    stname = "syncthing";
    target = "syncthing";

    postInstall = ''
      # This installs man pages in the correct directory according to the suffix
      # on the filename
      for mf in man/*.[1-9]; do
        mantype="$(echo "$mf" | awk -F"." '{print $NF}')"
        mandir="$out/share/man/man$mantype"
        install -Dm644 "$mf" "$mandir/$(basename "$mf")"
      done

    '' + lib.optionalString (stdenv.isLinux) ''
      mkdir -p $out/lib/systemd/{system,user}

      substitute etc/linux-systemd/system/syncthing-resume.service \
                 $out/lib/systemd/system/syncthing-resume.service \
                 --replace /usr/bin/pkill ${procps}/bin/pkill

      substitute etc/linux-systemd/system/syncthing@.service \
                 $out/lib/systemd/system/syncthing@.service \
                 --replace /usr/bin/syncthing $out/bin/syncthing

      substitute etc/linux-systemd/user/syncthing.service \
                 $out/lib/systemd/user/syncthing.service \
                 --replace /usr/bin/syncthing $out/bin/syncthing
    '';
  };

  syncthing-cli = common {
    stname = "syncthing-cli";

    target = "stcli";
  };

  syncthing-discovery = common {
    stname = "syncthing-discovery";
    target = "stdiscosrv";
  };

  syncthing-relay = common {
    stname = "syncthing-relay";
    target = "strelaysrv";

    postInstall = lib.optionalString (stdenv.isLinux) ''
      mkdir -p $out/lib/systemd/system

      substitute cmd/strelaysrv/etc/linux-systemd/strelaysrv.service \
                 $out/lib/systemd/system/strelaysrv.service \
                 --replace /usr/bin/strelaysrv $out/bin/strelaysrv
    '';
  };
}
