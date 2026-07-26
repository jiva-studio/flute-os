# What the live image itself runs.
#
# The image used to be built from a HOST: `mkISO "yoga"` composed the author's
# laptop — its timezone, its locale, its tailnets, its widgets, a 21.8 GiB
# closure — and handed that to whoever downloaded the ISO. Worse, the same
# coupling meant the x86_64 image could only exist on a machine that had the
# author's private directory.
#
# An installer image is not a machine anybody owns, so it states its own feature
# set here and takes nothing from `hosts/` or `personal/`. Two people building
# this ISO from the same commit get the same image.
#
# Deliberately narrower than a real install: enough for FluteOS to be
# recognisably itself and for the user to get online and run flute-install.
# Nothing that only earns its size once you have your own data on disk — no dev
# toolchains, no media library, no phone, no containers.
{ lib, ... }:
{
  # The primary user. Its name comes from the product default (`user`), which is
  # also what live-session.nix auto-logs in and what the installed system will
  # have unless the target host says otherwise.
  features.base.system.enable = true;
  features.base.system.hostname = "fluteos-live";

  features.profiles.desktop = true;

  # `features.base.greetd` actually configures *ly*, and the live session needs
  # passwordless autologin, which live-session.nix sets up with greetd itself.
  # Leaving both on gave the image two display managers racing for tty1, with
  # greetd winning only because systemd links unit aliases last. One wins here
  # on purpose.
  features.base.greetd.enable = lib.mkForce false;

  # Getting online, reading the instructions, looking at the disk.
  features.base.wifi.enable = true;
  features.base.firefox.enable = true;
  features.base.yazi.enable = true;
}
