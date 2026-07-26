{ ... }:
{
  features.fluteos.projects.groups."group-name" = {
    displayName = "Group Name";
    gitUserName = "Your Name";
    gitUserEmail = "your@email.com";
    logo = ''
      ╔════════════════════════════╗
      ║   GROUP NAME               ║
      ╚════════════════════════════╝
    '';
    firefoxProfile = {};            # {} = create profile with group defaults; null = no profile (uses fallback)
    # icon = "🪷";                     # waybar/which-key glyph
    # sshKeySource = ./credentials/id_ed25519;
    # sshKeySourcePub = ./credentials/id_ed25519.pub;
    # devTools = "use nix -p httpie"; # group-wide direnv snippet (inherited by projects)
    # agentCommand = "opencode";      # default is "claude"
  };
}
