{
  description = "Academic paper build environment (Markdown + Mermaid -> PDF)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Vendored upstream assets, formerly git submodules. Pin in
    # flake.lock; bump with `nix flake update`.
    eisvogel = {
      url = "github:Wandmalfarbe/pandoc-latex-template/v3.4.0";
      flake = false;
    };
    pandoc-lua-types = {
      url = "github:rnwst/pandoc-lua-types";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      eisvogel,
      pandoc-lua-types,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # TeX Live profile: medium scheme covers what pandoc's default
        # LaTeX template needs (fonts, hyperref, longtable, booktabs,
        # caption, subcaption, microtype, fancyvrb, ...). Add small
        # extras pandoc commonly pulls in plus everything Eisvogel
        # (templates/eisvogel.latex) requires beyond texliveMedium.
        texEnv = pkgs.texliveMedium.withPackages (
          ps: with ps; [
            # pandoc defaults
            xurl
            footnotebackref
            mdframed
            sourcesanspro
            sourcecodepro
            # Eisvogel additions (per upstream README's "with
            # texlive-latex-extra you also need…" list, minus the
            # language-specific ones we don't use: babel-german, bidi,
            # xecjk).
            adjustbox
            background
            collectbox
            csquotes
            everypage
            filehook
            fontawesome5
            footmisc
            framed
            fvextra
            letltxmacro
            ly1
            mweights
            needspace
            pagecolor
            titling
            ucharcat
            unicode-math
            upquote
            ulem
            zref
            # Filter-driven extras
            draftwatermark   # filters/02-draft.lua
            xcolor           # filters/04-todos.lua \colorbox
            pgf              # filters/tikz.lua — TikZ/PGF graphics
            standalone       # filters/tikz.lua — \documentclass{standalone}
            # make diff (tracked changes target)
            latexdiff
            # make review (line-numbered build for supervisor feedback)
            lineno
          ]
        );

        # Runtime deps shared by `nix build` and `nix develop`. Anything
        # the Makefile shells out to during a build belongs here.
        buildDeps = with pkgs; [
          pandoc
          haskellPackages.pandoc-crossref
          texEnv
          mermaid-cli   # `mmdc` (configured for NixOS chromium)
          plantuml      # full UML 2.x (class, sequence, activity, …)
          graphviz      # `dot`; also used directly by filters/graphviz.lua
          d2            # filters/d2.lua — declarative diagrams
          librsvg       # `rsvg-convert` (SVG -> PDF)
          gnumake
          curl          # make refs/harvard.csl fetches the CSL; make check-links HEADs URLs
          # Author-side proofreading tools (separate from build-critical deps).
          (aspellWithDicts (d: [ d.en ]))   # make spellcheck
        ];

        # Patched Cite Them Right CSL. Same patch the Makefile applies
        # at curl-time, but pre-fetched so `nix build` works offline.
        # The styles repo doesn't tag releases — bump the sha256 with
        # `nix-prefetch-url <url>` (then `nix-hash --to-sri --type sha256`)
        # whenever upstream changes the file.
        harvardCsl = pkgs.runCommand "harvard-cite-them-right.csl" { } ''
          cp ${pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/citation-style-language/styles/master/harvard-cite-them-right.csl";
            sha256 = "sha256-DKPSx8iBzZjN2BCYtTSfWSHt9DBJiqmlpBkYYhz3zEU=";
          }} $out
          chmod +w $out
          ${pkgs.gnused}/bin/sed -i '/<text variable="publisher-place"\/>/d' $out
          ${pkgs.gnused}/bin/sed -i 's|<title>Cite Them Right 12th edition (author-date/Harvard)</title>|<title>Cite Them Right 13th edition (author-date/Harvard) — local patch</title>|' $out
        '';

        # Build a PDF from a consumer's source tree. The consumer's
        # flake.nix calls this with their own `src` (a directory
        # containing `src/*.md` and optionally `refs/refs.bib`); the
        # template's bundled Makefile + filters + eisvogel + types are
        # threaded in from this flake's nix-store paths.
        mkReport =
          {
            src,
            name ? "report",
            # Subdirs inside `src` that hold the user's content.
            srcDir ? "src",
            refsDir ? "refs",
            # Override the default xelatex engine if needed.
            engine ? "xelatex",
            # Extra Make goals beyond the default PDF (e.g. ["html"]).
            extraGoals ? [ ],
            # Consumer Lua filters layered on top of the bundled set.
            # Either a list of .lua file paths or a list of directories
            # (every *.lua inside is loaded; _-prefixed files skipped).
            # Order: bundled filters first, then these in given order.
            extraFilters ? [ ],
            # Override the LaTeX template entirely. Must point at a
            # .latex file; pandoc resolves partials relative to it.
            template ? null,
          }:
          pkgs.stdenv.mkDerivation {
            pname = name;
            version = "0.0.0";
            src = pkgs.lib.cleanSource src;

            nativeBuildInputs = buildDeps;

            # Sandbox needs a writable HOME for fontconfig + chromium.
            buildPhase = ''
              runHook preBuild
              export HOME=$TMPDIR
              export FONTCONFIG_PATH=${pkgs.fontconfig.out}/etc/fonts

              # Provide the patched CSL if the consumer hasn't shipped
              # one of their own. -n preserves any user file.
              mkdir -p ${refsDir}
              cp -n ${harvardCsl} ${refsDir}/harvard.csl 2>/dev/null || true

              make -f ${self}/Makefile \
                SRC_DIR=${srcDir} \
                REFS_DIR=${refsDir} \
                FILTERS_DIR=${self}/filters \
                TEMPLATES_DIR=${eisvogel} \
                OUT_DIR=$PWD/build \
                ENGINE=${engine} \
                ${pkgs.lib.optionalString (template != null) "TEMPLATE=${template}"} \
                ${pkgs.lib.optionalString (extraFilters != [ ])
                  "EXTRA_FILTERS=${pkgs.lib.escapeShellArg
                    (pkgs.lib.concatStringsSep " " (map toString extraFilters))}"} \
                ${pkgs.lib.concatStringsSep " " extraGoals}
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out
              cp build/*.pdf $out/ 2>/dev/null || true
              cp build/*.html $out/ 2>/dev/null || true
              cp build/*.docx $out/ 2>/dev/null || true
              cp build/*.epub $out/ 2>/dev/null || true
              runHook postInstall
            '';

            # Sandbox default off — we don't fetch anything at build
            # time (CSL is pre-fetched as a flake-level fixed-output).
          };

        # Wrap a `make` target from this template's Makefile as a Nix
        # derivation, so every proofread check becomes a Cachix-cacheable
        # flake check instead of a dev-shell command. The unpacked source
        # tree gives the target the same layout it sees inside `nix
        # develop` (filters/, src/, refs/, tests/fixtures/, .luarc.json),
        # plus the two symlinks shellHook would create.
        mkMakeCheck =
          {
            target,
            extraInputs ? [ ],
          }:
          pkgs.stdenv.mkDerivation {
            pname = target;
            version = "0.0.0";
            src = pkgs.lib.cleanSource ./.;
            nativeBuildInputs = buildDeps ++ extraInputs;

            EISVOGEL_DIR = "${eisvogel}";
            PANDOC_LUA_TYPES_DIR = "${pandoc-lua-types}";

            # Sandbox defaults to LANG unset → POSIX/C; that turns
            # multibyte source bytes (e.g. ² in `E=mc²`) into garbled
            # input for aspell and breaks spellcheck on legal prose.
            LANG = "C.UTF-8";
            LC_ALL = "C.UTF-8";

            buildPhase = ''
              runHook preBuild
              export HOME=$TMPDIR
              export FONTCONFIG_PATH=${pkgs.fontconfig.out}/etc/fonts

              # Mirror shellHook: ensure the two symlinks the in-tree
              # defaults rely on (templates/eisvogel for TEMPLATES_DIR,
              # ./types for .luarc.json's workspace.library) point at
              # this flake's pinned inputs, regardless of whatever the
              # source snapshot happened to ship.
              rm -rf templates/eisvogel types
              mkdir -p templates
              ln -sfn ${eisvogel} templates/eisvogel
              ln -sfn ${pandoc-lua-types} types

              # Patched CSL alongside the in-tree copy. -n preserves
              # whatever the source ships (same patched file); kept for
              # consistency with mkReport's own setup.
              mkdir -p refs
              cp -n ${harvardCsl} refs/harvard.csl 2>/dev/null || true

              make ${target}
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out
              runHook postInstall
            '';
          };

        # Single source of truth for VS Code / VSCodium extension
        # recommendations: parsed from .vscode/extensions.json so the
        # editor's native "recommended extensions" prompt and our
        # opt-in shell-hook installer stay in sync.
        recommendedExtensions =
          (builtins.fromJSON (builtins.readFile ./.vscode/extensions.json)).recommendations;
      in
      {
        # Re-export so consumer flakes can build their own report:
        #   acedemic.lib.${system}.mkReport { src = ./.; }
        lib = {
          inherit mkReport;
        };

        devShells.default = pkgs.mkShell {
          name = "pandoc-report-template";

          packages = buildDeps ++ (with pkgs; [
            entr                 # `make watch`
            zip                  # `make submit`
            pre-commit           # `pre-commit run --all-files`
            lua-language-server  # `make typecheck`
            poppler-utils        # `pdfinfo` etc. for debugging
            act                  # `make ci-local` — run GH Actions locally
          ]);

          # Exported so the Makefile picks them up via its `?=`
          # defaults — works whether you're in this template's tree or
          # a downstream consumer repo that just brings its own src/.
          EISVOGEL_DIR = "${eisvogel}";
          PANDOC_LUA_TYPES_DIR = "${pandoc-lua-types}";
          ACEDEMIC_FILTERS_DIR = "${self}/filters";
          ACEDEMIC_MAKEFILE = "${self}/Makefile";

          shellHook = ''
            echo ""
            echo "📄 pandoc-report-template dev shell"
            echo "   pandoc       : $(pandoc --version | head -1 | awk '{print $2}')"
            echo "   mmdc         : $(mmdc --version 2>/dev/null || echo present)"
            echo "   plantuml     : $(plantuml -version 2>/dev/null | head -1 | awk '{print $3}')"
            echo "   dot          : $(dot -V 2>&1 | awk '{print $5}')"
            echo "   rsvg-convert : $(rsvg-convert --version | awk '{print $2}')"
            echo ""
            echo "   make         build  build/report.pdf"
            echo "   make watch          rebuild on save (entr)"
            echo "   make open           open the PDF"
            echo "   make clean          remove build/"
            echo ""

            # In-tree convenience: provide local symlinks for the two
            # vendored assets so (a) the Makefile defaults Just Work
            # without env wiring and (b) .luarc.json's
            # `workspace.library = ["types"]` resolves for VS Code's
            # LuaLS. Both paths are gitignored.
            mkdir -p templates
            [ -e templates/eisvogel ] || ln -sfn "$EISVOGEL_DIR" templates/eisvogel
            [ -e types ]              || ln -sfn "$PANDOC_LUA_TYPES_DIR" types

            # --- Install recommended VS Code / VSCodium extensions ---
            # Opt-in: set ACEDEMIC_INSTALL_EXTENSIONS=1 in your env (or
            # .envrc.local) to enable. VS Code/VSCodium will surface its
            # own native "recommended extensions" prompt for the same
            # list in .vscode/extensions.json anyway; this just batches
            # the install for users who'd rather skip the prompt.
            if [ "''${ACEDEMIC_INSTALL_EXTENSIONS:-0}" = "1" ]; then
              EDITOR_BIN=""
              for c in codium code code-insiders cursor; do
                if command -v "$c" >/dev/null 2>&1; then EDITOR_BIN="$c"; break; fi
              done

              if [ -n "$EDITOR_BIN" ]; then
                installed=$("$EDITOR_BIN" --list-extensions 2>/dev/null || true)
                missing=()
                for ext in ${pkgs.lib.concatStringsSep " " recommendedExtensions}; do
                  if ! printf '%s\n' "$installed" | grep -qi "^$ext$"; then
                    missing+=("$ext")
                  fi
                done
                if [ "''${#missing[@]}" -gt 0 ]; then
                  echo "📦 Installing missing extensions into $EDITOR_BIN:"
                  for ext in "''${missing[@]}"; do
                    echo "   · $ext"
                    "$EDITOR_BIN" --install-extension "$ext" --force \
                      >/dev/null 2>&1 || echo "     ⚠ failed: $ext"
                  done
                  echo ""
                fi
              fi
            fi
          '';
        };

        # `nix build` produces this template's own bundled report. A
        # downstream consumer would call `acedemic.lib.${system}.mkReport`
        # against their own source tree instead.
        packages.default = mkReport {
          src = ./.;
          name = "pandoc-report-template";
        };

        # Flake checks. Run with `nix flake check`. The minimal fixture
        # exercises `mkReport` against a tiny consumer-shaped source
        # tree, so any breaking change to mkReport's arg surface or
        # to the bundled filter set fails CI here. The inverse fixture
        # flips toggleable-filter defaults so the OTHER branch of each
        # toggle (todos.hide, glossary.append, unknown cover-style,
        # wordcount warn, csv io.open failure, csv empty-rows failure,
        # csv header=false) runs on every CI build — without these the
        # minimal fixture only ever exercises the default path. The
        # anonymous fixture isolates filters/03-anonymous.lua from
        # filters/07-authors.lua (only the simple `author:` field is
        # set), so a regression in 03 cannot be hidden by 07's rewrite.
        checks = {
          mkReport-minimal = mkReport {
            src = ./tests/fixtures/minimal;
            name = "mkReport-minimal";
          };
          mkReport-inverse = mkReport {
            src = ./tests/fixtures/inverse;
            name = "mkReport-inverse";
          };
          mkReport-anonymous = mkReport {
            src = ./tests/fixtures/anonymous;
            name = "mkReport-anonymous";
          };

          # Proofread gate, every sub-target lifted out of `make
          # proofread` and run as its own derivation. CI calls these
          # straight from `nix flake check` / `nix build .#checks.*`;
          # results land in Cachix so re-runs on unchanged inputs are
          # free instead of re-running aspell/pandoc/luals from scratch.
          typecheck = mkMakeCheck {
            target = "typecheck";
            extraInputs = [ pkgs.lua-language-server ];
          };
          check-refs = mkMakeCheck { target = "check-refs"; };
          spellcheck = mkMakeCheck { target = "spellcheck"; };
          check-inverse = mkMakeCheck { target = "check-inverse"; };
          check-diagram-failure = mkMakeCheck { target = "check-diagram-failure"; };
          check-wordcount-strict = mkMakeCheck { target = "check-wordcount-strict"; };
          check-csv-strict = mkMakeCheck { target = "check-csv-strict"; };
          check-anonymous = mkMakeCheck { target = "check-anonymous"; };
        };

        # `nix run` against a consumer repo's working dir builds the
        # PDF in-place under ./build, no flake.nix required on their
        # end. Useful for CI on a paper repo that doesn't have its own
        # flake yet.
        apps.default = {
          type = "app";
          program = toString (pkgs.writeShellScript "build-report" ''
            export PATH=${pkgs.lib.makeBinPath buildDeps}:$PATH
            export FONTCONFIG_PATH=${pkgs.fontconfig.out}/etc/fonts
            exec ${pkgs.gnumake}/bin/make -f ${self}/Makefile \
              FILTERS_DIR=${self}/filters \
              TEMPLATES_DIR=${eisvogel} \
              SRC_DIR="$PWD/src" \
              REFS_DIR="$PWD/refs" \
              OUT_DIR="$PWD/build" \
              "$@"
          '');
        };
      }
    );
}
