{
  description = "Private War: a Garry's Mod gamemode (development toolchain and quality gates)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # GMod API annotations for LuaLS (data only, nothing is built).
    glua-api-snippets = {
      url = "github:luttje/glua-api-snippets/lua-language-server-addon";
      flake = false;
    };

    # Test framework and its Docker runner (development tool, never shipped).
    gluatest = {
      url = "github:CFC-Servers/GLuaTest";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      git-hooks,
      glua-api-snippets,
      gluatest,
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});

      # Sources the gates read; research notes and local-only material stay out.
      gateSource =
        pkgs:
        pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions (
            [
              ./.glualint.json
              ./.luarc.json
              ./.markdownlint-cli2.yaml
              ./README.md
              ./scripts/check
              ./addons
              ./docs
              ./tests
            ]
            ++ map (f: ./. + "/${f}") [
              "CLAUDE.md"
              "DESIGN.md"
              "TASKS.md"
            ]
          );
        };

      toolsFor = pkgs: self': [
        self'.glualint-bin
        pkgs.lua-language-server
        pkgs.markdownlint-cli2
        pkgs.luajit
        pkgs.coreutils
        pkgs.gnused
        pkgs.gnumake
        pkgs.jq
        pkgs.rsync
      ];

      # A gate script wrapped with its tools, so git hooks work outside the devShell too.
      gateCommand =
        pkgs: self': name:
        pkgs.writeShellApplication {
          name = "pw-gate-${name}";
          # Keep macOS SSH (including its supported user-config options); Linux needs a supplied client.
          runtimeInputs = toolsFor pkgs self' ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.openssh ];
          text = ''
            export PW_GLUA_API=${glua-api-snippets}
            export PW_GLUATEST=${gluatest}
            exec bash scripts/check/${name}.sh "$@"
          '';
        };

      # Git hooks (T-0.7). pre-commit runs the fast gates over the whole project: they take seconds and
      # types cross file boundaries, so checking only staged files would miss breakage.
      gitHooksFor =
        system: pkgs:
        let
          self' = self.packages.${system};
          gateHook = name: description: {
            enable = true;
            name = description;
            entry = pkgs.lib.getExe (gateCommand pkgs self' name);
            pass_filenames = false;
            stages = [ "pre-commit" ];
          };
        in
        git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            pw-lint = gateHook "lint" "glualint";
            pw-types = gateHook "types" "lua-language-server --check";
            pw-markdown = gateHook "markdown" "markdownlint-cli2";
            pw-rules = gateHook "rules" "size limits and net.WriteTable";
          };
        };

      # Runs one gate script over a copy of the sources inside the sandbox.
      mkGate =
        pkgs: self': name: script:
        pkgs.runCommand "privatewar-${name}"
          {
            nativeBuildInputs = toolsFor pkgs self';
            PW_GLUA_API = glua-api-snippets;
            PW_GLUATEST = gluatest;
            PW_TEST_GATE = pkgs.lib.getExe (gateCommand pkgs self' "test");
          }
          ''
            cp --recursive ${gateSource pkgs} src
            chmod --recursive u+w src
            cd src
            export HOME="$TMPDIR"
            bash ${script}
            touch "$out"
          '';
    in
    {
      packages = forAllSystems (
        system: pkgs: {
          glualint-bin = pkgs.callPackage ./nix/glualint-bin.nix { };
        }
      );

      checks = forAllSystems (
        system: pkgs:
        let
          self' = self.packages.${system};
          gate = mkGate pkgs self';
        in
        {
          lint = gate "lint" "scripts/check/lint.sh";
          types = gate "types" "scripts/check/types.sh";
          markdown = gate "markdown" "scripts/check/markdown.sh";
          rules = gate "rules" "scripts/check/rules.sh";
          # The gates must reject known-bad fixtures, otherwise a green check proves nothing.
          gates-selftest = gate "gates-selftest" "scripts/check/selftest.sh";
        }
      );

      devShells = forAllSystems (
        system: pkgs:
        let
          self' = self.packages.${system};
          gitHooks = gitHooksFor system pkgs;
        in
        {
          default = pkgs.mkShell {
            packages = toolsFor pkgs self' ++ gitHooks.enabledPackages;
            PW_GLUA_API = glua-api-snippets;
            PW_GLUATEST = gluatest;
            PW_TEST_GATE = pkgs.lib.getExe (gateCommand pkgs self' "test");
            shellHook = ''
              ${gitHooks.shellHook}
              # The generated root-checkout path is shared with linked worktrees, whose .git is a file.
              # Normalize only that generated local value; leave custom hook directories untouched.
              if git rev-parse --git-dir >/dev/null 2>&1 \
                && [ -L "$GIT_WC/.pre-commit-config.yaml" ] \
                && [ "$(git config --local --get core.hooksPath)" = ".git/hooks" ]; then
                git config --local core.hooksPath "$(git rev-parse --path-format=absolute --git-common-dir)/hooks"
              fi
              # LuaLS reads the GMod annotations and GLuaTest types from stable paths named in .luarc.json.
              mkdir --parents .nix
              ln --symbolic --force --no-target-directory "$PW_GLUA_API" .nix/glua-api
              ln --symbolic --force --no-target-directory "$PW_GLUATEST" .nix/gluatest
            '';
          };
        }
      );

      formatter = forAllSystems (system: pkgs: pkgs.nixfmt);
    };
}
