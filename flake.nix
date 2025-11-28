{
  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url  = "github:hercules-ci/flake-parts";
    rust-overlay = {
        url = "github:oxalica/rust-overlay";
        inputs.nixpkgs.follows = "nixpkgs";
    };
    git-z.url        = "github:ejpcmac/git-z?ref=v0.2.4";
  };

  outputs = { flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];

    perSystem = { system, inputs', ... }:
      let
        overlays      = [ inputs.rust-overlay.overlays.default ];
        pkgs          = import inputs.nixpkgs {
          inherit system overlays;
        };

        rustToolchain = (pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml).override {
          # targets = [ "x86_64-unknown-linux-musl" ];
        };

        jj              = pkgs.jujutsu;
        git-z           = inputs'.git-z.packages.git-z;
        git             = pkgs.git;

        makeShellScript = name: text: let
          script = pkgs.writeShellScriptBin name text;
        in script;

        scripts = [
          # Keep jj log in the shell.
          (makeShellScript "jjw"
            ''
              watch --no-title -c 'jj log --no-pager --color always -r ::'
            ''
          )

          # Shortcut for jj log.
          (makeShellScript "jjl"
            ''
              jj log --no-pager
            ''
          )

          # jj commit with git-z.
          (makeShellScript "jjz"
            ''
              jjz_cmd() {
                local bookmarks="$(
                  jj log --no-graph -r 'heads(::@ & bookmarks())' -T 'self.bookmarks()'
                )"
                git z commit \
                  --topic "$bookmarks" \
                  --command "sh -c \" \
                    echo -n '\$message' \
                    | sed 's/^#\(.*\)/JJ:\1/' \
                    | jj describe $@ --edit --stdin\" \
                    "
              }
              jjz_cmd
            ''
          )
        ];

        # === Build the Rust application ===
        izo-app = pkgs.rustPlatform.buildRustPackage {
          pname = "izo";
          version = "1.0.0";
          src = ./.;

          nativeBuildInputs = [ ];

          cargoLock = {
            lockFile = ./Cargo.lock;
          };
        };
      in
      {
        # Expose the Docker image as a package
        packages = {
          default = izo-app;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            jj
            git
            git-z
            rustToolchain
          ] ++ scripts;

          shellHook = ''
            echo "Dev env loaded !"
          '';
        };
      };
  };
}
