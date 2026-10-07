# Catppuccin Mocha color palette
# https://github.com/catppuccin/catppuccin
{
  name = "Catppuccin Mocha";

  # Which upstream catppuccin flavour and accent these colours ARE.
  #
  # Some applications are themed by catppuccin/nix ports (GTK, Qt, zathura, yazi,
  # neovim) which take these NAMES rather than colours, so a palette that is a
  # catppuccin flavour has to say which one. A palette that is not one omits this
  # attribute, and those ports are then left alone rather than silently themed to
  # something the rest of the system is not.
  catppuccin = {
    flavor = "mocha";
    accent = "mauve";
  };

  # Accent colors
  rosewater = "#f5e0dc";
  flamingo = "#f2cdcd";
  pink = "#f5c2e7";
  mauve = "#cba6f7";
  red = "#f38ba8";
  maroon = "#eba0ac";
  peach = "#fab387";
  yellow = "#f9e2af";
  green = "#a6e3a1";
  teal = "#94e2d5";
  sky = "#89dceb";
  sapphire = "#74c7ec";
  blue = "#89b4fa";
  lavender = "#b4befe";

  # UI colors
  text = "#cdd6f4";
  subtext1 = "#bac2de";
  subtext0 = "#a6adc8";
  overlay2 = "#9399b2";
  overlay1 = "#7f849c";
  overlay0 = "#6c7086";
  surface2 = "#585b70";
  surface1 = "#45475a";
  surface0 = "#313244";
  base = "#1e1e2e";
  mantle = "#181825";
  crust = "#11111b";

  # Ink: accents meant to be drawn ON a chip, not as one.
  #
  # Every accent above is a background colour in a dark theme — light by
  # construction — and a bar chip inverts that: its background is the accent and
  # its text is `base`. A green dot painted in `green` on a yellow chip is
  # therefore invisible. These are the same hues from catppuccin's LIGHT flavour
  # (latte), which is exactly "these colours, dark enough to write with".
  ink = {
    blue = "#1e66f5";
    green = "#40a02b";
    red = "#d20f39";
    amber = "#df8e1d";
    neutral = "#4c4f69";
    dim = "#8c8fa1";
  };
}
