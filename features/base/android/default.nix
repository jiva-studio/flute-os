{ lib, config, ... }:
{
  options.features.base.android = {
    enable = lib.mkEnableOption "Android development (SDK + build tools)";
  };

  config = lib.mkIf config.features.base.android.enable {
    home-manager.users.${config.features.base.system.user.name} = { pkgs, ... }:
    let
      androidSdk = pkgs.androidenv.composeAndroidPackages {
        platformVersions = [ "36" ];
        buildToolsVersions = [ "35.0.0" "36.0.0" ];
        includeEmulator = false;
        includeSources = false;
        includeSystemImages = false;
        includeNDK = false;
        abiVersions = [ "arm64-v8a" "x86_64" ];
      };
    in {
      home.packages = [
        pkgs.android-tools
        pkgs.jdk21
        androidSdk.androidsdk
      ];

      home.sessionVariables = {
        ANDROID_HOME = "${androidSdk.androidsdk}/libexec/android-sdk";
        ANDROID_SDK_ROOT = "${androidSdk.androidsdk}/libexec/android-sdk";
      };
    };
  };
}
