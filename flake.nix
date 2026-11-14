{
  description = "romantic_collation — fast, opinionated, reproducible string collation that ignores the OS locale";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Pin Zig explicitly via mitchellh/zig-overlay, which exposes every
    # release as a named attr. Insulates this project from upstream nixpkgs
    # jumping Zig versions unannounced.
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay }:
    flake-utils.lib.eachSystem [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pname = "romantic_collation";
        version = "0.1.0";
        zigPkg = zig-overlay.packages.${system}."0.17.1";
        coreSource = pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions [ ./build.zig ./build.zig.zon ./src ./include ./cli ./tests/unit ];
        };
        mkCore = extra: pkgs.stdenv.mkDerivation {
          inherit pname version;
          src = coreSource;
          nativeBuildInputs = [ zigPkg ];
          dontConfigure = true;
          dontFixup = true;
          buildPhase = ''
            export HOME=$TMPDIR
            ${pkgs.lib.optionalString pkgs.stdenv.isDarwin "unset NIX_CFLAGS_COMPILE NIX_LDFLAGS"}
            zig build ${extra} --prefix $out
          '';
          dontInstall = true;
        };
        # Database modules must use the host libc, not the standalone CLI's musl.
        hostTarget = if pkgs.stdenv.isLinux then "${pkgs.stdenv.hostPlatform.parsed.cpu.name}-linux-gnu" else "aarch64-macos";
        hostCore = mkCore "-Dtarget=${hostTarget}";
        sqliteExtension = pkgs.stdenv.mkDerivation {
          pname = "romantic-sqlite";
          inherit version;
          src = ./.;
          buildInputs = [ pkgs.sqlite ];
          dontConfigure = true;
          buildPhase = ''
            $CC -O3 -fPIC -shared -Wall -Wextra -Werror -Iinclude db/sqlite.c \
              ${hostCore}/lib/libromantic_collation.a -o romantic${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
          '';
          installPhase = ''
            mkdir -p $out/lib
            cp romantic${pkgs.stdenv.hostPlatform.extensions.sharedLibrary} $out/lib/
          '';
        };
        postgresExtension = pkgs.llvmPackages.stdenv.mkDerivation {
          pname = "romantic-postgresql";
          inherit version;
          src = ./.;
          nativeBuildInputs = [ pkgs.postgresql ];
          buildInputs = [ pkgs.postgresql ];
          dontConfigure = true;
          buildPhase = ''
            $CC -O3 -fPIC -shared -Wall -Wextra -Werror -Iinclude -I${pkgs.postgresql.dev}/include/server \
              db/postgres.c ${hostCore}/lib/libromantic_collation.a \
              ${pkgs.lib.optionalString pkgs.stdenv.isDarwin "-Wl,-undefined,dynamic_lookup"} \
              -o romantic_collation${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
            nm -g romantic_collation${pkgs.stdenv.hostPlatform.extensions.sharedLibrary} | grep -q 'Pg_magic_func' || exit 1
          '';
          installPhase = ''
            mkdir -p $out/lib $out/share/postgresql/extension
            cp romantic_collation${pkgs.stdenv.hostPlatform.extensions.sharedLibrary} $out/lib/
            cp db/romantic_collation.control db/romantic_collation--1.0.sql $out/share/postgresql/extension/
          '';
        };
      in {
        packages.default = mkCore "";
        packages.debug = mkCore "-Doptimize=debug";
        packages.library = hostCore;
        packages.sqlite-extension = sqliteExtension;
        packages.postgres-extension = postgresExtension;
        packages.linux-arm64 = mkCore "-Dtarget=aarch64-linux-musl";
        packages.mswin-amd64 = mkCore "-Dtarget=x86_64-windows-gnu";
        packages.mswin-arm64 = mkCore "-Dtarget=aarch64-windows-gnu";
        packages.macos-arm64 = mkCore "-Dtarget=aarch64-macos";

        # NOTE: don't key on ${system} here — flake-utils.eachDefaultSystem
        # already wraps the returned attrs in ${system}. Writing
        # `checks.${system} = ...` produces checks.<sys>.<sys>, which no CI
        # resolves, so the targets in .mechatron-prime/targets would not exist.
        checks = {
          build = self.packages.${system}.default;
          cross = pkgs.linkFarm "romantic-cross-targets" (map (name: {
            inherit name;
            path = self.packages.${system}.${name};
          }) [ "linux-arm64" "mswin-amd64" "mswin-arm64" "macos-arm64" ]);
          test = pkgs.stdenv.mkDerivation {
            pname = "${pname}-test";
            inherit version;
            src = ./.;
            nativeBuildInputs = [
              zigPkg
              pkgs.bash
              pkgs.bc
              pkgs.coreutils
              pkgs.ripgrep
              pkgs.sqlite
              pkgs.postgresql
            ];
            dontConfigure = true;
            dontFixup = true;
            buildPhase = ''
              export HOME=$TMPDIR
              export RCOL_SQLITE_EXTENSION=${sqliteExtension}/lib/romantic${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
              export RCOL_PG_EXTENSION=${postgresExtension}/lib/romantic_collation${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
              export RCOL_PG_SQL=${postgresExtension}/share/postgresql/extension/romantic_collation--1.0.sql
              export RCOL_LIBRARY=${hostCore}
              ${pkgs.lib.optionalString pkgs.stdenv.isDarwin "unset NIX_CFLAGS_COMPILE NIX_LDFLAGS"}
              timeout 600 ${pkgs.bash}/bin/bash ./test > test.log 2>&1 || { cat test.log; exit 1; }
            '';
            installPhase = ''
              mkdir -p $out
              cp test.log $out/test.log
            '';
          };
        };

        devShells.default = pkgs.mkShell {
          # coreutils `sort` (LC_ALL=C) is the differential oracle for the
          # code-point fallback integration test; `bc` is the independent
          # ARBITRARY-PRECISION oracle for the big-integer numeric tests
          # (coreutils `sort -g` loses precision past ~19 significant digits, so
          # it cannot serve); hyperfine for benchmarks; luajit generates the
          # benchmark corpus. pkg-config/gcc/icu are used ONLY by ./bm to compile
          # the ICU and glibc-strcoll comparison harnesses — NOT dependencies of
          # the library, CLI, or CI `checks`.
          nativeBuildInputs = [
            zigPkg
            pkgs.hyperfine
            pkgs.coreutils
            pkgs.bc
            pkgs.luajit
            pkgs.pkg-config
            pkgs.gcc
            pkgs.jq
          ];
          # In buildInputs so pkg-config finds icu-uc/icu-i18n on PKG_CONFIG_PATH.
          buildInputs = [ pkgs.icu ];
        };
      });
}
