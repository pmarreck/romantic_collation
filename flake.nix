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
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, rust-overlay }:
    flake-utils.lib.eachSystem [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ] (system:
      let
        pkgs = import nixpkgs { inherit system; overlays = [ rust-overlay.overlays.default ]; };
        rustToolchain = pkgs.rust-bin.stable."1.100.0".minimal.override { extensions = [ "rustfmt" "clippy" ]; };
        pname = "romantic_collation";
        version = "0.1.0";
        zigPkg = zig-overlay.packages.${system}."0.17.1";
        unicodeData = pkgs.fetchurl {
          url = "https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt";
          hash = "sha256-Lh78HctZxXXu31zK5g+VIp9wbubQMYNSR9hDwR2WRww=";
        };
        unicodeProperties = pkgs.fetchurl {
          url = "https://www.unicode.org/Public/17.0.0/ucd/PropList.txt";
          hash = "sha256-Ew3N3Kra8HEAi9/OHndD4E/fvJEIhvAX2fmskx2MZN0=";
        };
        coreSource = pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions [ ./build.zig ./build.zig.zon ./src ./include ./cli
            ./tests/unit/cli_key_failure.c ./tests/unit/cli_key_arena.c ./tests/unit/ffi_contract.c ];
        };
        installCliAlias = ''ln -s collate "$out/bin/romantic-collate"'';
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
            # Windows packages have collate.exe and must not require symlinks.
            if [[ ! -f "$out/bin/collate.exe" ]]; then
              test -x "$out/bin/collate"
              ${installCliAlias}
            fi
          '';
          dontInstall = true;
        };
        # Database modules must use the host libc, not the standalone CLI's musl.
        hostTarget = if pkgs.stdenv.isLinux then "${pkgs.stdenv.hostPlatform.parsed.cpu.name}-linux-gnu" else "aarch64-macos";
        hostCore = mkCore "-Dtarget=${hostTarget}";
        rustPlatform = pkgs.makeRustPlatform { cargo = rustToolchain; rustc = rustToolchain; };
        rustCore = rustPlatform.buildRustPackage {
          pname = "romantic-collation-rust";
          inherit version;
          src = ./rust;
          cargoLock.lockFile = ./rust/Cargo.lock;
          nativeBuildInputs = [ pkgs.jq ];
          buildPhase = ''
            runHook preBuild
            cargo build --release --lib --offline --locked --message-format=json > artifacts.jsonl
            runHook postBuild
          '';
          checkPhase = ''
            cargo test --offline --locked
            cargo clippy --all-targets --offline --locked -- -D warnings
            cargo fmt --check
          '';
          installPhase = ''
            mkdir -p $out/lib $out/include
            while IFS= read -r artifact; do
              case "$artifact" in
                *.a|*.rlib|*.so|*.dylib) cp "$artifact" $out/lib/ ;;
              esac
            done < <(jq -r 'select(.reason == "compiler-artifact" and .target.name == "romantic_collation") | .filenames[]' artifacts.jsonl)
            cp ${./include/romantic_collation.h} $out/include/romantic_collation.h
            test -f $out/lib/libromantic_collation.a
          '';
        };
        # CLI consumers see only the packaged header/archive, never core sources.
        mkCliWith = flags: core: pkgs.stdenv.mkDerivation {
          pname = "romantic-collation-cli";
          inherit version;
          src = pkgs.lib.fileset.toSource { root = ./.; fileset = ./cli; };
          dontConfigure = true;
          buildPhase = ''
            $CC ${flags} -std=c11 -Wall -Wextra -Werror -I${core}/include cli/main.c \
              ${core}/lib/libromantic_collation.a -lm \
              ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-ldl -lpthread"} -o collate
          '';
          installPhase = ''
            mkdir -p "$out/bin"
            cp collate "$out/bin/"
            ${installCliAlias}
          '';
        };
        mkCli = mkCliWith "-O3 -DNDEBUG";
        rustDebug = rustCore.overrideAttrs (_: {
          buildPhase = ''cargo build --lib --offline --locked --message-format=json > artifacts.jsonl'';
        });
        zigShared = pkgs.stdenv.mkDerivation {
          pname = "romantic-collation-oracle";
          inherit version;
          dontUnpack = true;
          buildPhase = ''
            mkdir -p $out/lib
            $CC -shared ${pkgs.lib.optionalString pkgs.stdenv.isDarwin "-Wl,-all_load"} \
              ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-Wl,--whole-archive"} ${hostCore}/lib/libromantic_collation.a \
              ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-Wl,--no-whole-archive"} -o $out/lib/libromantic_collation${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
          '';
          dontInstall = true;
        };
        parity = pkgs.stdenv.mkDerivation {
          pname = "romantic-backend-parity";
          inherit version;
          src = pkgs.lib.fileset.toSource { root = ./.; fileset = ./tests/unit/backend_parity.c; };
          dontConfigure = true;
          buildPhase = ''
            $CC -O2 -std=c11 -Wall -Wextra -Werror -I${rustCore}/include tests/unit/backend_parity.c \
              ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-ldl"} -o backend-parity
          '';
          installPhase = ''mkdir -p $out/bin; cp backend-parity $out/bin/'';
          doInstallCheck = true;
          installCheckPhase = ''
            $out/bin/backend-parity ${zigShared}/lib/libromantic_collation${pkgs.stdenv.hostPlatform.extensions.sharedLibrary} \
              ${rustCore}/lib/libromantic_collation${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
          '';
        };
        structuralCheck = pkgs.stdenv.mkDerivation {
          pname = "romantic-unicode-structure";
          inherit version;
          src = pkgs.lib.fileset.toSource { root = ./.; fileset = ./tests/unit/structural_unicode.c; };
          dontConfigure = true;
          buildPhase = ''
            $CC -O2 -std=c11 -Wall -Wextra -Werror -I${hostCore}/include tests/unit/structural_unicode.c \
              ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-ldl"} -o unicode-structure
          '';
          installPhase = ''mkdir -p $out/bin; cp unicode-structure $out/bin/'';
          doInstallCheck = true;
          installCheckPhase = ''
            $out/bin/unicode-structure ${zigShared}/lib/libromantic_collation${pkgs.stdenv.hostPlatform.extensions.sharedLibrary} ${unicodeData} ${unicodeProperties}
            $out/bin/unicode-structure ${rustCore}/lib/libromantic_collation${pkgs.stdenv.hostPlatform.extensions.sharedLibrary} ${unicodeData} ${unicodeProperties}
          '';
        };
        elixirNif = pkgs.stdenv.mkDerivation {
          pname = "romantic-elixir-nif";
          inherit version;
          src = pkgs.lib.fileset.toSource { root = ./.; fileset = ./native; };
          dontConfigure = true;
          buildPhase = ''
            $CC -O3 -fPIC -shared -Wall -Wextra -Werror -I${rustCore}/include \
              -I${pkgs.erlang}/lib/erlang/usr/include native/elixir_nif.c ${rustCore}/lib/libromantic_collation.a \
              -lm ${pkgs.lib.optionalString pkgs.stdenv.isLinux "-ldl -lpthread"} \
              ${pkgs.lib.optionalString pkgs.stdenv.isDarwin "-Wl,-undefined,dynamic_lookup"} -o romantic_nif.so
          '';
          installPhase = ''mkdir -p $out/lib; cp romantic_nif.so $out/lib/'';
        };
        elixirCheck = pkgs.stdenv.mkDerivation {
          pname = "romantic-elixir-test";
          inherit version;
          src = pkgs.lib.fileset.toSource { root = ./.; fileset = pkgs.lib.fileset.unions [ ./mix.exs ./elixir ]; };
          nativeBuildInputs = [ pkgs.elixir pkgs.erlang ];
          dontConfigure = true;
          buildPhase = ''
            export HOME=$TMPDIR
            export MIX_HOME=$TMPDIR/mix
            export ERL_FLAGS="+S 2:2 +SDcpu 2 +SDio 1"
            export ELIXIR_ERL_OPTIONS="+fnu"
            export ROMANTIC_COLLATION_NIF=${elixirNif}/lib/romantic_nif
            mix format --check-formatted mix.exs elixir/lib/*.ex elixir/test/*.exs
            mix test --no-deps-check > test.log 2>&1 || { cat test.log; exit 1; }
          '';
          installPhase = ''mkdir -p $out; cp test.log $out/test.log'';
        };
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
            cp db/romantic_collation.control db/romantic_collation--2.0.sql $out/share/postgresql/extension/
          '';
        };
      in {
        packages.default = mkCore "";
        packages.build-tools = pkgs.coreutils;
        packages.debug = mkCore "-Doptimize=debug";
        packages.library = hostCore;
        packages.rust-library = rustCore;
        packages.rust = pkgs.symlinkJoin { name = "romantic-rust"; paths = [ rustCore (mkCli rustCore) ]; };
        packages.rust-debug = pkgs.symlinkJoin { name = "romantic-rust-debug"; paths = [ rustDebug (mkCliWith "-Og -g" rustDebug) ]; };
        packages.rust-cli = mkCli rustCore;
        packages.zig-cli = mkCli hostCore;
        packages.zig-oracle = zigShared;
        packages.backend-parity = parity;
        packages.unicode-structure = structuralCheck;
        packages.elixir-nif = elixirNif;
        packages.sqlite-extension = sqliteExtension;
        packages.postgres-extension = postgresExtension;
        packages.linux-arm64 = mkCore "-Dtarget=aarch64-linux-musl";
        packages.linux-amd64 = mkCore "-Dtarget=x86_64-linux-musl";
        packages.linux-arm64-debug = mkCore "-Dtarget=aarch64-linux-musl -Doptimize=debug";
        packages.mswin-amd64 = mkCore "-Dtarget=x86_64-windows-gnu";
        packages.mswin-arm64 = mkCore "-Dtarget=aarch64-windows-gnu";
        packages.macos-arm64 = mkCore "-Dtarget=aarch64-macos";
        packages.macos-arm64-debug = mkCore "-Dtarget=aarch64-macos -Doptimize=debug";
        packages.mswin-amd64-debug = mkCore "-Dtarget=x86_64-windows-gnu -Doptimize=debug";
        packages.mswin-arm64-debug = mkCore "-Dtarget=aarch64-windows-gnu -Doptimize=debug";

        # NOTE: don't key on ${system} here — flake-utils.eachDefaultSystem
        # already wraps the returned attrs in ${system}. Writing
        # `checks.${system} = ...` produces checks.<sys>.<sys>, which no CI
        # resolves, so the targets in .mechatron-prime/targets would not exist.
        checks = {
          parity = parity;
          structural = structuralCheck;
          elixir = elixirCheck;
          build = self.packages.${system}.default;
          cross = pkgs.linkFarm "romantic-cross-targets" (map (name: {
            inherit name;
            path = self.packages.${system}.${name};
          }) [ "linux-arm64" "mswin-amd64" "mswin-arm64" "macos-arm64" ]);
          test = assert pkgs.lib.all (line:
            let columns = pkgs.lib.splitString " " line;
            in builtins.length columns == 5 && pkgs.lib.all (name: builtins.hasAttr name self.packages.${system})
              [ (builtins.elemAt columns 3) (builtins.elemAt columns 4) ]
          ) (builtins.filter (line: line != "" && !(pkgs.lib.hasPrefix "#" line))
            (pkgs.lib.splitString "\n" (builtins.readFile ./build-targets.tsv)));
          pkgs.stdenv.mkDerivation {
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
              pkgs.luajit
              pkgs.file
            ];
            dontConfigure = true;
            dontFixup = true;
            buildPhase = ''
              export HOME=$TMPDIR
              export RCOL_SQLITE_EXTENSION=${sqliteExtension}/lib/romantic${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
              export RCOL_PG_EXTENSION=${postgresExtension}/lib/romantic_collation${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
              export RCOL_PG_SQL=${postgresExtension}/share/postgresql/extension/romantic_collation--2.0.sql
              export RCOL_LIBRARY=${hostCore}
              export RCOL_RUST_LIBRARY=${rustCore}
              export RCOL_ZIG_CLI=${mkCli hostCore}/bin/collate
              export RCOL_RUST_CLI=${mkCli rustCore}/bin/collate
              export RCOL_DEFAULT_CLI=${self.packages.${system}.default}/bin/collate
              export RCOL_RUST_PRODUCT_CLI=${self.packages.${system}.rust}/bin/collate
              export RCOL_PARITY=${parity}/bin/backend-parity
              export RCOL_ZIG_SHARED=${zigShared}/lib/libromantic_collation${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
              export RCOL_RUST_SHARED=${rustCore}/lib/libromantic_collation${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
              export RCOL_ELIXIR_LOG=${elixirCheck}/test.log
              export RCOL_COREUTILS=${pkgs.coreutils}
              export RCOL_STRUCTURE_ORACLE=${structuralCheck}/bin/unicode-structure
              export RCOL_UNICODE_DATA=${unicodeData}
              export RCOL_PROP_LIST=${unicodeProperties}
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
            pkgs.time
            rustToolchain
            pkgs.elixir
            pkgs.erlang
            pkgs.file
          ];
          # In buildInputs so pkg-config finds icu-uc/icu-i18n on PKG_CONFIG_PATH.
          buildInputs = [ pkgs.icu ];
        };
      });
}
