{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, rust-overlay, ... }:
    {
      devShells = nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" "aarch64-darwin" ] (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };

          mdbook-frontmatter-strip = pkgs.rustPlatform.buildRustPackage (finalAttrs: {
            pname = "mdbook-frontmatter-strip";
            version = "2.0.0";
            src = pkgs.fetchCrate {
              inherit (finalAttrs) pname version;
              hash = "sha256-6/d3Ghd57NAfV+HEnYkh6tBo/9+v582vOrxihegdv08=";
            };
            cargoHash = "sha256-zpa7Ok6db4XMXAZC1FKsybD1YOzZZemAXLBxie/2qFw=";
          });
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              # Use nightly for formatting only
              rust-bin.nightly.latest.rustfmt

              # Latest as of the `rust-overlay` revision pinned in `flake.lock`, not as of each
              # flake evaluation
              (rust-bin.stable.latest.minimal.override { extensions = [ "rust-analyzer" ]; })

              codebook
              just
              mdbook
              mdbook-frontmatter-strip
              mdbook-rss-feed
            ];
          };
        }
      );
    };
}
