{ pkgs, lib, config, ... }:

let
  inherit (lib) types mkOption mkEnableOption;
  inherit (import ../utils.nix { inherit lib pkgs; }) recipeModule recipeType;

  cfg = config.just.recipes.git-cliff;
  fileName = cfg.settings.file-name;

  git-cliff-config = pkgs.writeTextFile {
    name = "cliff.toml";
    text = cfg.settings.config-file;
  };

  git-cliff-entry = pkgs.writeShellScriptBin "git-cliff" ''
    ${lib.optionalString cfg.settings.integrations.github.enable ''
      # Get the remote URL
      REMOTE_URL=$(git config --get remote.origin.url)

      # Extract the owner and repo name from the URL
      if [[ $REMOTE_URL =~ ^https://github.com/(.*)/(.*)\.git$ ]]; then
          OWNER=''${BASH_REMATCH[1]}
          REPO=''${BASH_REMATCH[2]}
      elif [[ $REMOTE_URL =~ ^git@github.com:(.*)/(.*)\.git$ ]]; then
          OWNER=''${BASH_REMATCH[1]}
          REPO=''${BASH_REMATCH[2]}
      else
          echo "Unsupported remote URL format: $REMOTE_URL"
          exit 1
      fi

      # Combine owner and repo name
      GITHUB_REPO="$OWNER/$REPO"
    ''}

    ${lib.getExe' cfg.package "git-cliff"} \
    --output ${fileName} \
    --config ${git-cliff-config.outPath}
  '';

in
{
  options.just.recipes.git-cliff = mkOption {
    description = "Add the 'changelog' target calling convco";
    type = types.submodule {
      imports = [ recipeModule ];
      options.settings = {
        file-name =
          mkOption {
            type = types.str;
            description = lib.mdDoc "The name of the file to output the chaneglog to.";
            default = "CHANGELOG.md";
          };

        config-file = mkOption {
          type = types.str;
          description = ''
            The git-cliff config to use.

            See https://git-cliff.org/docs/configuration/
          '';
          default = ''
            [changelog]
            header = """
            # Changelog\n
            All notable changes to this project will be documented in this file.\n
            """
            body = """
            {% if version %}\
                ## [{{ version | trim_start_matches(pat="v") }}] - {{ timestamp | date(format="%Y-%m-%d") }}
            {% else %}\
                ## [unreleased]
            {% endif %}\
            {% for group, commits in commits | group_by(attribute="group") %}
                ### {{ group | striptags | trim | upper_first }}
                {% for commit in commits %}
                    - {% if commit.scope %}*({{ commit.scope }})* {% endif %}\
                        {% if commit.breaking %}[**breaking**] {% endif %}\
                        {{ commit.message | upper_first }}\
                {% endfor %}
            {% endfor %}\n
            """
            # template for the changelog footer
            footer = """
            <!-- generated by git-cliff -->
            """
            # remove the leading and trailing s
            trim = true

            [git]
            conventional_commits = true
            filter_unconventional = true
            split_commits = false
            commit_parsers = [
              { message = "^feat", group = "<!-- 0 -->🚀 Features" },
              { message = "^fix", group = "<!-- 1 -->🐛 Bug Fixes" },
              { message = "^doc", group = "<!-- 3 -->📚 Documentation" },
              { message = "^perf", group = "<!-- 4 -->⚡ Performance" },
              { message = "^refactor", group = "<!-- 2 -->🚜 Refactor" },
              { message = "^style", group = "<!-- 5 -->🎨 Styling" },
              { message = "^test", group = "<!-- 6 -->🧪 Testing" },
              { message = "^chore\\(release\\): prepare for", skip = true },
              { message = "^chore\\(deps.*\\)", skip = true },
              { message = "^chore\\(pr\\)", skip = true },
              { message = "^chore\\(pull\\)", skip = true },
              { message = "^chore|^ci", group = "<!-- 7 -->⚙️ Miscellaneous Tasks" },
              { body = ".*security", group = "<!-- 8 -->🛡️ Security" },
              { message = "^revert", group = "<!-- 9 -->◀️ Revert" },
            ]
            protect_breaking_commits = false
            filter_commits = false
            topo_order = false
            sort_commits = "oldest"
          '';
        };
        integrations = {
          github.enable = mkEnableOption "GitHub integration. See https://git-cliff.org/docs/integration/github";
        };
      };
    };
  };

  config.just.recipes.git-cliff = lib.mkIf config.just.enable {
    package = lib.mkDefault pkgs.git-cliff;
    justfile = lib.mkDefault
      ''
        # Generate ${fileName} using recent commits
        changelog:
          ${git-cliff-entry}/bin/git-cliff
      '';
  };
}
