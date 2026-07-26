# Extra shape for the *default* profile only, merged over profile-config.nix.
#
# The default profile is the one a user lands in, so it gets Firefox's home page
# (search box plus a Shortcuts row) rather than the blank page the per-group
# profiles use. What goes ON that page — bookmarks and pinned tiles — is empty
# until someone says otherwise: see features.base.firefox.defaultProfile.*.
{ lib, cfg }:

let
  dp = cfg.defaultProfile;
in
{
  settings = {
    # Show the home page instead of a blank one
    "browser.newtabpage.enabled" = true;
    "browser.startup.page" = 1;
    "browser.startup.homepage" = "about:home";

    # Homepage Content
    "browser.newtabpage.activity-stream.showSearch" = true;              # Web Search
    "browser.newtabpage.activity-stream.feeds.topsites" = true;          # Shortcuts
    "browser.newtabpage.activity-stream.topSitesRows" = 2;               # 2 rows
    "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;  # Sponsored shortcuts off

    "browser.newtabpage.activity-stream.feeds.section.highlights" = false;  # Recent activity off
    "browser.newtabpage.activity-stream.section.highlights.includeBookmarks" = true;  # Bookmarks on
    "browser.newtabpage.activity-stream.section.highlights.includeVisited" = false;
    "browser.newtabpage.activity-stream.section.highlights.includeDownloads" = false;
  }
  # No tiles configured → the pref is not written at all, and the Shortcuts row
  # fills itself from the user's own browsing.
  // lib.optionalAttrs (dp.pinnedSites != [ ]) {
    "browser.newtabpage.pinned" =
      builtins.toJSON (map (s: { inherit (s) url label; }) dp.pinnedSites);
  };
}
# Bookmarks are managed only when a tree was supplied; otherwise home-manager
# never touches the profile's places database and the user keeps their own.
// lib.optionalAttrs (dp.bookmarks != [ ]) {
  bookmarks = {
    force = dp.bookmarksForce;
    settings = dp.bookmarks;
  };
}
