{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkOption optionalString mkIf;
  inherit (lib) types;

  cfg = config.services.supervisor;
  supervisor = cfg.package;

  supervisorctlConfig = optionalString cfg.supervisorctl.enable ''
    [supervisorctl]
    serverurl = ${cfg.supervisorctl.url}:${toString cfg.supervisorctl.port}

    [inet_http_server]
    port = 127.0.0.1:${toString cfg.supervisorctl.port}
  '';

  programSections = lib.concatStringsSep "\n" (lib.filter (s: s != "") (lib.mapAttrsToList
    (name: program:
      if program.enable then
        program.program
      else
        ""
    )
    cfg.programs));

  configFile = pkgs.writeText "supervisor.conf" ''
    [supervisord]
    pidfile=${config.env.DEVENV_STATE}/supervisor/run/supervisor.pid
    childlogdir=${config.env.DEVENV_STATE}/supervisor/log/
    logfile=${config.env.DEVENV_STATE}/supervisor/log/supervisor.log

    ${supervisorctlConfig}

    ${programSections}

    [rpcinterface:supervisor]
    supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
  '';

  supervisorWrapper = pkgs.writeScript "supervisor-wrapper" ''
    #!/usr/bin/env bash
    mkdir -p ${config.env.DEVENV_STATE}/supervisor/{run,log}

    export PATH="${pkgs.coreutils}/bin"

    # Run supervisor
    ${supervisor}/bin/supervisord \
     --configuration=${configFile} \
     --nodaemon \
     --pidfile=${config.env.DEVENV_STATE}/supervisor/run/supervisor.pid \
     --childlogdir=${config.env.DEVENV_STATE}/supervisor/log/ \
     --logfile=${config.env.DEVENV_STATE}/supervisor/log/supervisor.log
  '';

  supervisorctlWrapper = pkgs.writeScript "supervisorctl-wrapper" ''
    #!/usr/bin/env bash
    ${supervisor}/bin/supervisorctl -c ${configFile} $@
  '';

in
{
  options.services.supervisor = {
    enable = mkEnableOption "Supervisor Service";

    package = mkOption {
      type = types.package;
      default = pkgs.python312Packages.supervisor;
      description = "Supervisor package";
    };

    supervisorctl = {
      enable = mkEnableOption "Enable supervisorctl";
      url = mkOption {
        type = types.str;
        default = "http://localhost";
        description = "URL for supervisorctl";
      };
      port = mkOption {
        type = types.int;
        default = 65123;
        description = "Port for supervisorctl";
      };
    };

    programs = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "Enable this program";
          program = mkOption {
            type = types.lines;
            description = "The program configuration. See http://supervisord.org/configuration.html#program-x-section-settings";
          };
        };
      });
      default = { };
      description = "Configuration for each program.";
    };
  };

  config = mkIf cfg.enable {
    packages = [
      cfg.package
    ];

    processes.supervisor.exec = ''
      set -euxo pipefail
      exec ${supervisorWrapper}
    '';

    scripts = mkIf cfg.supervisorctl.enable {
      supervisorctl = {
        exec = ''
          set -euxo pipefail
          exec ${supervisorctlWrapper}
        '';
      };
    };
  };
}
