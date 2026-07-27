# Waybar CSS styles
{ theme }:

let
  # Chip helpers come from the theme, so a chip contributed through
  # features.fluteos.waybar.extraModules can use the same ones.
  styles = theme.css;
in
''
  * {
    font-family: "${theme.fonts.mono}";
    font-size: 13px;
    min-height: 0;
    border: none;
    border-radius: 0;
  }

  window#waybar {
    background: transparent;
    color: ${theme.palette.text};
  }

  window#waybar > box {
    background: ${theme.colors.mantle-alpha-90};
    border-radius: ${toString theme.uiConstants.borderRadius.normal}px;
    padding: ${toString theme.uiConstants.spacing.xs}px;
  }

  /* Niri windows minimap styles */
  .cffi-niri-windows {
    padding: 0;
    margin: 0;
  }

  .cffi-niri-windows .tile {
    background: ${theme.palette.yellow};
    border-radius: ${toString theme.uiConstants.borderRadius.small}px;
    margin: 0 1px 0 0;
    padding: 0;
  }

  .cffi-niri-windows .tile:hover {
    background: ${theme.palette.peach};
  }

  .cffi-niri-windows .tile.active,
  .cffi-niri-windows .tile:active {
    background: ${theme.palette.peach};
  }

  .cffi-niri-windows .tile label {
    color: ${theme.palette.base};
    font-size: 24px;
    margin: 0 6px;
  }

  .cffi-niri-windows .tile.active label,
  .cffi-niri-windows .tile:active label {
    color: ${theme.palette.base};
  }

  /* Urgent tile - pulsing attention animation */
  @keyframes pulse-urgent {
      0%   { background: ${theme.palette.red}; }
      50%  { background: ${theme.palette.maroon}; }
      100% { background: ${theme.palette.red}; }
  }

  .cffi-niri-windows .tile.urgent {
      animation: pulse-urgent 1s ease-in-out infinite;
  }

  .cffi-niri-windows .tile.urgent label {
      color: ${theme.palette.base};
  }

  #custom-workspace-name {
    padding: 0 10px;
    margin: 0;
    border-radius: ${toString theme.uiConstants.borderRadius.small}px;
    background: ${theme.palette.green};
    color: ${theme.palette.base};
    font-weight: bold;
  }

  #custom-workspace-name:hover {
    background: ${theme.palette.teal};
  }

  #custom-workspace-name.no-name {
    color: ${theme.palette.base};
  }

  /* System status group */
  #status { ${styles.chipStatus theme.palette.teal} }

  /* Standard modules using moduleBase */
  #custom-weather { ${styles.chip theme.palette.sapphire} }
  #clock { ${styles.chip theme.palette.blue} }
  #tray { ${styles.chip theme.palette.mauve} }
  #custom-obsidian { ${styles.chip theme.palette.peach} }
  #custom-claude { ${styles.chip theme.palette.yellow} }
  /* Tailnet switcher — lavender sits between clock (blue) and tray (mauve) to
     keep the right-side catppuccin gradient flowing (…sapphire→blue→lavender→mauve). */
  #custom-tailnet { ${styles.chip theme.palette.lavender} }
  #custom-mpd { ${styles.chip theme.palette.red} }

  #cpu,
  #memory,
  #battery,
  #network,
  #pulseaudio {
    color: ${theme.palette.base};
    padding: 0 8px;
    margin: 0;
  }

  /* Claude agents share the usage chip, and they colour it: yellow is the
     resting state, but an agent that is working or waiting has to be visible
     from across the room without reading anything.

       working  green,  slow gentle pulse — something is happening, no action
       waiting  blue,   fast bright blink — an agent is blocked on YOU
       idle     yellow, static            — the usage chip's own colour

     Animated background rather than coloured glyphs: the chip has exactly one
     background, and dark text on it is the only combination that stays legible
     through every frame of an animation. The dot shapes in the text (◉ ● ○)
     carry the same information for anyone who cannot rely on colour. */
  @keyframes agents-working {
    0%   { background: ${theme.palette.yellow}; }
    50%  { background: ${theme.palette.green}; }
    100% { background: ${theme.palette.yellow}; }
  }

  @keyframes agents-waiting {
    0%   { background: ${theme.palette.blue}; }
    50%  { background: ${theme.palette.sky}; }
    100% { background: ${theme.palette.blue}; }
  }

  #custom-claude.agents-working {
    animation: agents-working 3s ease-in-out infinite;
  }

  /* The widget emits the most urgent state only, so these never collide: with
     one agent waiting and three working the chip is blue, and the text still
     shows ◉1 ●3. */
  #custom-claude.agents-waiting {
    animation: agents-waiting 1s ease-in-out infinite;
  }

  /* PTT Mode widget. Background lives on the base rule, not per-mode, so a new
     mode inherits it instead of rendering as a transparent gap. */
  #custom-ptt-mode {
    border-radius: ${toString theme.uiConstants.borderRadius.small}px;
    background: ${theme.palette.sky};
    color: ${theme.palette.base};
    padding: 0 10px;
    margin: 0;
  }

  /* MPD hover state */
  #custom-mpd:hover { background: ${theme.palette.maroon}; }

  /* MPD control buttons */
  #custom-mpd-prev,
  #custom-mpd-next { ${styles.chipControl theme.palette.red} }

  #custom-mpd-prev:hover,
  #custom-mpd-next:hover { background: ${theme.palette.maroon}; }
''
