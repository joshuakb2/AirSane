{
  description = "airsane packages, overlays, devShells, and nixos modules.";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
  };

  outputs =
    inputs:
    let
      forEachSystem = f: builtins.mapAttrs f inputs.nixpkgs.legacyPackages;
    in
    {
      packages = forEachSystem (
        system: pkgs:
        let
          ourPkgs = pkgs.extend inputs.self.overlays.default;
        in
        {
          airsane = ourPkgs.airsane;
          default = ourPkgs.airsane;
        }
      );

      overlays.default = final: prev: {
        airsane = final.callPackage (
          {
            avahi,
            cmake,
            lib,
            libjpeg,
            libpng,
            libusb1,
            sane-backends,
            stdenv,
          }:
          stdenv.mkDerivation {
            name = "airsane";
            src = lib.cleanSource ./.;
            buildInputs = [
              avahi
              libjpeg
              libpng
              libusb1
              sane-backends
            ];
            nativeBuildInputs = [ cmake ];
            configurePhase = "mkdir build && cd build && cmake -DCMAKE_INSTALL_PREFIX=$out/ ..";
          }
        ) { };
      };

      devShells = forEachSystem (
        system: pkgs: {
          default = pkgs.mkShell {
            name = "airsane-devshell";
            inputsFrom = [ inputs.self.packages.${system}.airsane ];
          };
        }
      );

      nixosModules.default =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        let
          cfg = config.services.airsane;
        in
        {
          options.services.airsane = with lib.options; {
            enable = mkEnableOption "airsane";
            args = mkOption {
              type =
                with lib.types;
                attrsOf (oneOf [
                  bool
                  int
                  str
                  path
                ]);
              default = { };
              example = lib.literalExpression ''
                services.airsane.args = {
                  "announce-secure" = true;
                  debug = false;
                  "job-timeout" = 120;
                  "ignore-list" = ./airsane/ignore.conf;
                  "access-log" = "-";
                };
              '';
              description = "Command-line arguments to pass to airsaned.";
            };
          };
          config = lib.mkIf cfg.enable {
            nixpkgs.overlays = [ inputs.self.overlays.default ];
            systemd.services.airsane = {
              description = "Publish SANE scanners to MacOS, Android, and Windows via Apple AirScan.";
              after = [ "avahi-daemon.service" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "simple";
                ExecStart =
                  let
                    toArg = name: value: "--${name}=${toArgValue value}";
                    toArgValue =
                      value:
                      if builtins.typeOf value == "bool" then if value then "true" else "false" else toString value;
                  in
                  "${pkgs.airsane}/bin/airsaned ${lib.escapeShellArgs (map toArg (lib.attrsToList cfg.args))}";
                ExecReload = pkgs.writeShellScript "airsane-exec-start" ''
                  kill -HUP $MAINPID
                '';
                ExecStartPre = pkgs.writeShellScript "airsane-exec-start-pre" ''
                  sleep 3
                  ${pkgs.sane-backends}/bin/scanimage -L
                  sleep 5
                '';
                User = "scanner";
                Group = "scanner";
              };
            };
            users.groups.scanner.gid = config.ids.gids.scanner;
            users.users.scanner = {
              uid = config.ids.uids.scanner;
              group = "scanner";
              extraGroups = [ "lp" ] ++ lib.optionals config.services.avahi.enable [ "avahi" ];
            };
          };
        };

      formatter = forEachSystem (_: pkgs: pkgs.nixfmt-rfc-style);
    };
}
