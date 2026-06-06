{
  description = "crucible — Julia drug-discovery sim with an LLM paper-transpiler";

  # Pinned to a tarball URL (not `github:`) so the flake resolves without
  # hitting api.github.com — a small but real concern from behind corporate
  # proxies or when CI runners share an IP. Mirrors the in-fleet `thea` pattern.
  inputs.nixpkgs.url = "https://github.com/NixOS/nixpkgs/archive/refs/heads/nixos-24.11.tar.gz";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in {
      # IMPURITY NOTE — why there is a devShell but no sandboxed packages.default:
      #
      # Julia package builds are network-impure: `Pkg.instantiate()` reaches the
      # Julia General registry (and downloads artifacts) at build time. Nix's
      # build sandbox has no network, so a pure `packages.default` that ran
      # `Pkg.instantiate` would fail by construction. The honest deliverable is a
      # pinned dev shell that pins the *toolchain* (julia + the native deps the
      # project dlopens) and lets `Pkg.instantiate` run with network access,
      # driven by CI as `nix develop -c julia --project -e 'using Pkg; Pkg.instantiate()'`.
      #
      # We therefore deliberately omit `checks` (a `nix flake check` check would
      # run inside that same network-free sandbox and could not instantiate the
      # Julia env). CI's `nix develop` job is the real gate. `nix flake show`
      # is the offline smoke for the flake itself.

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShell {
            buildInputs = [
              # `julia-bin` is the upstream Julia binary (JuliaLang generic
              # tarball repackaged) — Project.toml pins `julia = "1.10"` as the
              # floor; nixos-24.11 ships a 1.10.x-compatible release. Use
              # `pkgs.julia` instead if you want the nixpkgs-built Julia.
              pkgs.julia-bin

              # Native dep: DuckDB. The `DuckDB.jl` package vendors its own
              # libduckdb via JLL, so the Julia path does not strictly need the
              # system `duckdb`, but having the CLI + shared lib in the shell is
              # useful for poking the database directly and for any non-JLL path.
              pkgs.duckdb

              # PDFAdapter tests shell out to `pdftotext`.
              pkgs.poppler_utils

              # Pkg.instantiate clones registries / artifacts over git+https.
              pkgs.git
            ];

            shellHook = ''
              echo "crucible dev shell — $(julia --version)"
              echo "duckdb $(duckdb --version 2>/dev/null | head -1)"
            '';
          };

          # OPTIONAL OpenMM / Conda / Python backend.
          #
          # The OpenMM backend (PythonCall + CondaPkg → openmm/pdbfixer/mdtraj)
          # is intentionally NOT part of the default shell — the native Julia
          # path (MollyBackend) is the default and CondaPkg manages its own
          # micromamba env outside Nix. To work on the OpenMM path, uncomment and
          # `nix develop .#openmm`:
          #
          # openmm = pkgs.mkShell {
          #   buildInputs = [
          #     pkgs.julia-bin
          #     pkgs.duckdb
          #     pkgs.poppler_utils
          #     pkgs.git
          #     pkgs.micromamba   # CondaPkg.toml drives the conda-forge env
          #     # or, for a pure-nix python path:
          #     # (pkgs.python311.withPackages (ps: with ps; [ openmm mdtraj numpy ]))
          #   ];
          # };
        });
    };
}
