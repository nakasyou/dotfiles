npx -y @ts-for-gir/cli@4.1.0 generate 'Astal*' \
  --ignoreVersionConflicts \
  --ignore Gtk3 \
  --ignore Astal3 \
  --outdir ~/dotfiles/config/shoji-bar-2/@girs \
  -g /nix/store/gk0a6r76jbmlascc26j8rqfjbslqzhkd-gir-dirs/share/gir-1.0 \
  -g /nix/store/rdg8lakfnz1d1zq46g6sfif2gkbqnpfz-gtk4-4.22.4-dev/share/gir-1.0 \
  -g /nix/store/pyhyqj1vfs2dmhm4x4vnirg24inapysq-graphene-1.10.8-dev/share/gir-1.0
