{
  description = "devenv.sh - Fast, Declarative, Reproducible, and Composable Developer Environments";

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  inputs.nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
  inputs.pre-commit-hooks = {
    url = "github:cachix/pre-commit-hooks.nix";
    inputs = {
      nixpkgs.follows = "nixpkgs";
      flake-compat.follows = "flake-compat";
    };
  };
  inputs.treefmt-nix = {
    url = "github:numtide/treefmt-nix";
    inputs = {
      nixpkgs.follows = "nixpkgs";
    };
  };
  inputs.flake-compat = {
    url = "github:edolstra/flake-compat";
    flake = false;
  };
  inputs.nix = {
    url = "github:domenkozar/nix/devenv-2.21";
    inputs = {
      nixpkgs.follows = "nixpkgs";
      flake-compat.follows = "flake-compat";
    };
  };
  inputs.cachix = {
    url = "github:cachix/cachix";
    inputs = {
      nixpkgs.follows = "nixpkgs";
      pre-commit-hooks.follows = "pre-commit-hooks";
      flake-compat.follows = "flake-compat";
    };
  };


  outputs = { self, nixpkgs, pre-commit-hooks, treefmt-nix, nix, ... }@inputs:
    let
      systems = [ "x86_64-linux" "i686-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f: builtins.listToAttrs (map (name: { inherit name; value = f name; }) systems);
      mkPackage = pkgs: import ./package.nix { inherit pkgs inputs; };
      mkDevShellPackage = config: pkgs: import ./src/devenv-devShell.nix { inherit config pkgs; };
      mkDocOptions = pkgs:
        let
          inherit (pkgs) lib;
          eval = pkgs.lib.evalModules {
            modules = [
              ./src/modules/top-level.nix
              { devenv.warnOnNewVersion = false; }
            ];
            specialArgs = { inherit pre-commit-hooks treefmt-nix pkgs inputs; };
          };
          sources = [
            { name = "${self}"; url = "https://github.com/cachix/devenv/blob/main"; }
            { name = "${pre-commit-hooks}"; url = "https://github.com/cachix/pre-commit-hooks.nix/blob/master"; }
            { name = "${treefmt-nix}"; url = "https://github.com/numtide/treefmt-nix/blob/main"; }
          ];
          rewriteSource = decl:
            let
              prefix = lib.strings.concatStringsSep "/" (lib.lists.take 4 (lib.strings.splitString "/" decl));
              source = lib.lists.findFirst (src: src.name == prefix) { } sources;
              path = lib.strings.removePrefix prefix decl;
              url = "${source.url}${path}";
            in
            { name = url; url = url; };
          options = pkgs.nixosOptionsDoc {
            options = builtins.removeAttrs eval.options [ "_module" ];

            warningsAreErrors = false;

            transformOptions = opt: (
              opt // { declarations = map rewriteSource opt.declarations; }
            );
          };
        in
        options;

    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          options = mkDocOptions pkgs;
        in
        {
          default = self.packages.${system}.devenv;
          devenv = mkPackage pkgs;
          devenv-docs-options = options.optionsCommonMark;
          devenv-docs-options-json = options.optionsJSON;
        });

      modules = ./src/modules;
      isTmpDir = true;
      hasIsTesting = true;

      templates =
        let

          flake-parts = {
            path = ./templates/flake-parts;
            description = "A flake with flake-parts, direnv and devenv.";
            welcomeText = ''
              # `.devenv` should be added to `.gitignore`
              ```sh
                echo .devenv >> .gitignore
              ```
            '';
          };

          simple = {
            path = ./templates/simple;
            description = "A direnv supported Nix flake with devenv integration.";
            welcomeText = ''
              # `.devenv` should be added to `.gitignore`
              ```sh
                echo .devenv >> .gitignore
              ```
            '';
          };
        in
        {
          inherit simple flake-parts;
          terraform = {
            path = ./templates/terraform;
            description = "A Terraform Nix flake with devenv integration.";
            welcomeText = ''
              # `.devenv` should be added to `.gitignore`
              ```sh
                echo .devenv >> .gitignore
              ```
            '';
          };
          default = simple;
        };

      flakeModule = import ./flake-module.nix self;

      lib = {
        mkConfig = args@{ pkgs, inputs, modules }:
          (self.lib.mkEval args).config;
        mkEval = { pkgs, inputs, modules }:
          let
            moduleInputs = { inherit pre-commit-hooks; } // inputs;
            project = inputs.nixpkgs.lib.evalModules {
              specialArgs = moduleInputs // {
                inherit pkgs;
                inputs = moduleInputs;
              };
              modules = [
                (self.modules + /top-level.nix)
                ({ config, ... }: {
                  packages = [
                    (mkDevShellPackage config pkgs)
                  ];
                  devenv.warnOnNewVersion = false;
                  devenv.flakesIntegration = true;
                })
              ] ++ modules;
            };
          in
          project;
        mkShell = args:
          let
            config = self.lib.mkConfig args;
          in
          config.shell // {
            ci = config.ciDerivation;
            inherit config;
          };
      };

      overlays.default = final: prev: {
        devenv = self.packages.${prev.system}.default;
      };
    };
}
