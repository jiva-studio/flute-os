# Which-key menu CSS styles
{ theme, c }:

''
  .menu-window {
    background-color: #${c theme.colors.bg-light};
    border: ${toString theme.uiConstants.borderWidth.normal}px solid #${c theme.colors.accent};
    padding: 0;
  }
  flowbox, flowboxchild {
    outline: none;
    border: none;
    background: transparent;
  }
  flowboxchild:focus, flowboxchild:selected {
    outline: none;
    border: none;
    background: transparent;
  }
  .search-entry {
    background-color: transparent;
    color: #${c theme.colors.fg};
    border: none;
    outline: none;
    box-shadow: none;
    padding: 4px 0;
    font-family: "${theme.fonts.mono}";
    font-size: ${toString (theme.fonts.size.normal + 2)}pt;
  }
  .search-entry:focus {
    border: none;
    outline: none;
    box-shadow: none;
  }
  .search-entry selection {
    background-color: #${c theme.colors.accent};
    color: #${c theme.colors.bg};
  }
  .search-entry > * {
    border: none;
    outline: none;
    box-shadow: none;
  }
  .menu-item {
    padding: 4px 8px;
    font-family: "${theme.fonts.mono}";
    font-size: ${toString (theme.fonts.size.normal + 2)}pt;
    color: #${c theme.colors.fg};
    border-radius: ${toString theme.uiConstants.borderRadius.normal}px;
  }
  .menu-item.selected {
    background-color: #${c theme.colors.accent};
    color: #${c theme.colors.bg};
  }
  .menu-item.disabled {
    opacity: 0.3;
  }
  .item-icon {
    font-family: "${theme.fonts.mono}";
    font-size: ${toString (theme.fonts.size.normal + 2)}pt;
    color: inherit;
  }
  .item-label {
    font-family: "${theme.fonts.mono}";
    font-size: ${toString (theme.fonts.size.normal + 2)}pt;
    color: inherit;
  }
  .item-key {
    font-family: "${theme.fonts.mono}";
    font-size: ${toString (theme.fonts.size.normal + 2)}pt;
    color: #${c theme.colors.accent};
    min-width: 1.5em;
    padding: 2px 6px;
    border-radius: ${toString theme.uiConstants.borderRadius.normal}px;
  }
''
