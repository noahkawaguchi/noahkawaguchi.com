# Serve the site from a VM using the hostname 10.0.2.15 (default recipe)
serve-vm:
    mdbook serve --hostname 10.0.2.15

# Check spelling with Codebook
spell-check:
    git ls-files -z | xargs -0 codebook-lsp lint
