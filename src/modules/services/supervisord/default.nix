{ config, lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkOption mkIf;
  inherit (lib) types;

  serviceOpts = { name, config, ...}: {
    options = {
      command = mkOption {
        description = "The command to execute";
      };
      directory = mkOption {
        default = "/";
        description = "Current directory when running the command";
      };
      environment = mkOption {
        default = {};
        example = {
          PATH = "/some/path";
        };
      };
      path = mkOption {
        default = [];
        description = "Current directory when running the command";
      };
      stopsignal = mkOption {
        default = "TERM";
      };
      startsecs = mkOption {
        default = 1;
        example = 0;
      };
      pidfile = mkOption {
        default = null;
      };
    };
  };

  cfg = config.services.supervisord;

  configFile = pkgs.writeText "supervisord.conf" ''
        [supervisord]
        pidfile=${config.env.DEVENV_STATE}/supervisord/run/supervisord.pid
        childlogdir=${config.env.DEVENV_STATE}/supervisord/log/
        logfile=${config.env.DEVENV_STATE}/supervisord/log/supervisord.log

        [supervisorctl]
        serverurl = http://localhost:${toString config.services.supervisord.port}

        [inet_http_server]
        port = 127.0.0.1:${toString config.services.supervisord.port}

        [rpcinterface:supervisor]
        supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

        ${lib.concatMapStrings (name:
          let
            cfg = lib.getAttr name config.services.supervisord.services;
  		      path = if lib.isList cfg.path then lib.concatStringsSep ":" cfg.path else cfg.path;
          in
            ''
            [program:${name}]
            command=${if cfg.pidfile == null then cfg.command else "${supervisor}/bin/pidproxy ${cfg.pidfile} ${cfg.command}"}
            environment=${lib.concatStrings
              (lib.mapAttrsToList (name: value: "${name}=\"${value}\",") (
                cfg.environment // { PATH = lib.concatStringsSep ":"
                  [("%(ENV_PATH)s") (path) (lib.maybeAttr "PATH" "" cfg.environment)];
                }
              )
            )}
            directory=${cfg.directory}
            redirect_stderr=true
            startsecs=${toString cfg.startsecs}
            stopsignal=${cfg.stopsignal}
            stopasgroup=true
            ''
          ) (attrNames services)
        }
      '';


  supervisor = cfg.package;

  supervisordWrapper = pkgs.writeScript "supervisord-wrapper" ''
    #!${pkgs.stdenv.shell}
    extraFlags="-j ${config.env.DEVENV_STATE}/supervisord/run/supervisord.pid -d ${config.env.DEVENV_STATE}/supervisord/ -q ${config.env.DEVENV_STATE}/supervisord/log/ -l ${config.env.DEVENV_STATE}/supervisord/log/supervisord.log"
    mkdir -p "${config.env.DEVENV_STATE}"/supervisord/{run,log}

    export PATH="${pkgs.coreutils}/bin"

    # Run supervisord
    ${supervisor}/bin/supervisord -c ${configFile} $extraFlags $@
  '';

#
#  supervisorctlWrapper = pkgs.writeScript "supervisorctl-wrapper" ''
#  	#!/usr/bin/env bash
#    ${supervisor}/bin/supervisorctl -c ${config.supervisord.configFile} $@
#  '';

in
{
  options.services.supervisord = {
    enable = mkEnableOption "Supervisord Service";

    package = mkOption {
      type = types.package;
      default = pkgs.python312Packages.supervisor;
      description = "Supervisord package";
    };

    services = mkOption {
      default = {};
      type = types.loaOf types.optionSet;
      description = ''
        Supervisord services to start.
      '';
      options = [ serviceOpts ];
    };

    stateDir = mkOption {
      default = "./var";
      type = types.str;
      description = ''
        Supervisord state directory.
      '';
    };

  };

  config = mkIf cfg.enable {
    packages = [ cfg.package ];


    processes.supervisord.exec =
      let

      in
      ''
        set -euxo pipefail


        exec ${supervisordWrapper}/bin/supervisord-wrapper
      '';


  };
}
