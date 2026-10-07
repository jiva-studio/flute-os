# The profile shape shared by every Firefox profile: the default one and each
# per-group one, which then overrides individual fields.
#
# Everything here is either a product decision — privacy and debloat prefs,
# hardware video decode, thin scrollbars — or a value read from
# features.base.firefox.*. Nothing is hardcoded taste: the extension set, the
# theme, the toolbar layout and the chrome tweaks all arrive through options.
{ lib, cfg }:

let
  # Collapsing the tab strip leaves a dead titlebar band behind, so the two
  # rules travel together under one switch.
  hideTabBarCss = ''
    #TabsToolbar { visibility: collapse !important; }
    #titlebar { appearance: none !important; height: 0 !important; }
  '';

  autoHideNavbarCss = ''
    /* Auto-hide nav-bar */
    #navigator-toolbox {
      --uc-navbar-height: 40px;
      margin-top: calc(-1 * var(--uc-navbar-height));
      transition: margin-top 0.2s ease-in-out;
    }
    #navigator-toolbox:hover,
    #navigator-toolbox:focus-within {
      margin-top: 0;
    }
  '';
in
{
  extensions.packages = cfg.extensions;

  settings = {
    "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
    "browser.tabs.inTitlebar" = 1;
    "browser.uidensity" = 1;
    "browser.toolbars.bookmarks.visibility" = "never";
    "extensions.autoDisableScopes" = 0;
    "extensions.enabledScopes" = 15;

    # Fonts
    "font.default.x-western" = "sans-serif";
    "font.default.x-cyrillic" = "sans-serif";
    "font.default.x-unicode" = "sans-serif";
    "font.name.sans-serif.x-western" = "Noto Sans";
    "font.name.sans-serif.x-cyrillic" = "Noto Sans";
    "font.name.sans-serif.x-unicode" = "Noto Sans";
    "font.name.serif.x-western" = "Noto Serif";
    "font.name.serif.x-cyrillic" = "Noto Serif";
    "font.name.serif.x-unicode" = "Noto Serif";
    "font.name.monospace.x-western" = "JetBrainsMono Nerd Font";
    "font.name.monospace.x-cyrillic" = "JetBrainsMono Nerd Font";
    "font.name.monospace.x-unicode" = "JetBrainsMono Nerd Font";
    "font.name-list.system-ui.x-western" = "Noto Sans, sans-serif";
    "font.name-list.system-ui.x-cyrillic" = "Noto Sans, sans-serif";
    "font.name-list.system-ui.x-unicode" = "Noto Sans, sans-serif";

    # Session persistence - keep logged in between browser restarts
    "network.cookie.lifetimePolicy" = 0;           # 0 = keep cookies until they expire naturally
    "privacy.clearOnShutdown.cookies" = false;     # don't clear cookies on exit
    "privacy.clearOnShutdown.cache" = false;       # don't clear cache on exit
    "privacy.clearOnShutdown.history" = false;     # don't clear history on exit
    "privacy.sanitize.sanitizeOnShutdown" = false; # disable auto-sanitization on shutdown

    # Disable Alt key menu activation
    "ui.key.menuAccessKeyFocuses" = false;

    # Disable extension welcome/onboarding pages
    "extensions.postDownloadThirdPartyPrompt" = false;
    "browser.startup.upgradeDialog.enabled" = false;

    # Thin scrollbars
    "widget.gtk.overlay-scrollbars.enabled" = true;
    "widget.non-native-theme.scrollbar.style" = 5;

    # Empty new tab
    "browser.newtabpage.enabled" = false;
    "browser.newtab.url" = "about:blank";
    "browser.startup.homepage" = "about:blank";

    # Disable translation prompts
    "browser.translations.enable" = false;

    # Disable fingerprinting resistance for site compatibility
    "privacy.resistFingerprinting" = false;
    "privacy.resistFingerprinting.letterboxing" = false;
    "webgl.disabled" = false;

    # --- Debloat: strip the stuff Firefox ships that LibreWolf omitted ---
    # Pocket
    "extensions.pocket.enabled" = false;
    # Telemetry / data reporting / studies
    "toolkit.telemetry.enabled" = false;
    "toolkit.telemetry.unified" = false;
    "toolkit.telemetry.archive.enabled" = false;
    "toolkit.telemetry.newProfilePing.enabled" = false;
    "toolkit.telemetry.shutdownPingSender.enabled" = false;
    "toolkit.telemetry.updatePing.enabled" = false;
    "toolkit.telemetry.bhrPing.enabled" = false;
    "toolkit.telemetry.firstShutdownPing.enabled" = false;
    "toolkit.telemetry.coverage.opt-out" = true;
    "toolkit.coverage.opt-out" = true;
    "toolkit.coverage.endpoint.base" = "";
    "datareporting.healthreport.uploadEnabled" = false;
    "datareporting.policy.dataSubmissionEnabled" = false;
    "app.shield.optoutstudies.enabled" = false;
    "app.normandy.enabled" = false;
    "app.normandy.api_url" = "";
    # Crash reporting
    "breakpad.reportURL" = "";
    "browser.tabs.crashReporting.sendReport" = false;
    # New-tab / activity-stream: sponsored stories & shortcuts, telemetry
    "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
    "browser.newtabpage.activity-stream.showSponsored" = false;
    "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
    "browser.newtabpage.activity-stream.system.showSponsored" = false;
    "browser.newtabpage.activity-stream.telemetry" = false;
    "browser.newtabpage.activity-stream.feeds.telemetry" = false;
    "browser.ping-centre.telemetry" = false;
    # In-product nags, recommendations, "more from Mozilla", onboarding
    "browser.discovery.enabled" = false;
    "browser.shopping.experience2023.enabled" = false;
    "browser.preferences.moreFromMozilla" = false;
    "browser.messaging-system.whatsNewPanel.enabled" = false;
    "browser.aboutwelcome.enabled" = false;
    "browser.uitour.enabled" = false;
    "extensions.getAddons.showPane" = false;
    "extensions.htmlaboutaddons.recommendations.enabled" = false;
    "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = false;
    "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;
    # URL bar: Firefox Suggest sponsored/non-sponsored & trending
    "browser.urlbar.quicksuggest.enabled" = false;
    "browser.urlbar.suggest.quicksuggest.sponsored" = false;
    "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
    "browser.urlbar.suggest.trending" = false;
    # Don't pester about default browser (workspace launcher owns MIME)
    "browser.shell.checkDefaultBrowser" = false;

    # Hardware video decode (VA-API).
    # On Wayland, widget.dmabuf.force-enabled is required for the RDD
    # process to share decoded frames with the compositor via DMA-BUF
    # zerocopy. Without it Firefox/Librewolf silently falls back to
    # CPU decode even with vaapi.enabled=true.
    "media.ffmpeg.vaapi.enabled" = true;
    "media.hardware-video-decoding.enabled" = true;
    "media.hardware-video-decoding.force-enabled" = true;
    "widget.dmabuf.force-enabled" = true;

    # GPU rendering
    "gfx.webrender.all" = true;
    "layers.gpu-process.enabled" = true;

    # Reduce disk writes
    "browser.sessionstore.interval" = 60000;

    # Content process limit (RAM management)
    "dom.ipc.processCount" = 4;
  }
  # Theme and toolbar layout: absent unless chosen, so a fresh install gets
  # Firefox's own theme and its own button placement.
  // lib.optionalAttrs (cfg.activeThemeID != null) {
    "extensions.activeThemeID" = cfg.activeThemeID;
  }
  // lib.optionalAttrs (cfg.uiCustomizationState != null) {
    "browser.uiCustomization.state" = cfg.uiCustomizationState;
  };

  # Empty when no switch is on — home-manager then writes no userChrome.css.
  userChrome = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
    (lib.optionalString cfg.chrome.hideTabBar hideTabBarCss)
    (lib.optionalString cfg.chrome.autoHideNavbar autoHideNavbarCss)
    cfg.chrome.extraCss
  ]);
}
