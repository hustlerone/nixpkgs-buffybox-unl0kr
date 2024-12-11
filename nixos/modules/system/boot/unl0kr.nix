{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.boot.initrd.unl0kr;
  settingsFormat = pkgs.formats.ini { };
in
{
  options.boot.initrd.unl0kr = {
    enable = lib.mkEnableOption "unl0kr in initrd" // {
      description = ''Whether to enable the unl0kr on-screen keyboard in initrd to unlock LUKS.'';
    };

    package = lib.mkPackageOption pkgs "buffybox" { };

    allowVendorDrivers = lib.mkEnableOption "load optional drivers" // {
      description = ''Whether to load additional drivers for certain vendors (I.E: Wacom, Intel, etc.)'';
    };

    settings = lib.mkOption {
      description = ''
        Configuration for `unl0kr`.

        See `unl0kr.conf(5)` for supported values.

        Alternatively, visit `https://gitlab.postmarketos.org/postmarketOS/buffybox/-/blob/3.2.0/unl0kr/unl0kr.conf`
      '';

      example = lib.literalExpression ''
        {
          general.animations = true;
          theme = {
            default = "pmos-dark";
            alternate = "pmos-light";
          };
        }
      '';
      default = { };
      type = lib.types.submodule { freeformType = settingsFormat.type; };
    };
  };

  config = lib.mkIf cfg.enable {
    meta.maintainers = with lib.maintainers; [ hustlerone ];
    assertions = [
      {
        assertion = cfg.enable -> config.boot.initrd.systemd.enable;
        message = "boot.initrd.unl0kr is only supported with boot.initrd.systemd.";
      }
    ];

    warnings =
      if config.hardware.amdgpu.initrd.enable then
        [ ''Use early video loading at your risk. It's not guaranteed to work with unl0kr.'' ]
      else if config.boot.plymouth.enable then
        [ ''Plymouth **might** cause issues'' ]
      else
        [ ];

    boot.initrd.availableKernelModules =
      lib.optionals cfg.enable [
        "hid-multitouch"
        "hid-generic"
        "usbhid"

        "i2c-designware-core"
        "i2c-designware-platform"
        "i2c-hid-acpi"

        "usbtouchscreen"
        "evdev"
      ]
      ++ lib.optionals cfg.allowVendorDrivers [
        "intel_lpss_pci"
        "elo"
        "wacom"
      ];

    boot.initrd.systemd = {
      contents."/etc/unl0kr.conf".source = settingsFormat.generate "unl0kr.conf" cfg.settings;
      storePaths = (
        with pkgs;
        [
          libinput
          libwacom
          xkeyboard_config
          cfg.package
        ]
      );
      services = {
        unl0kr-agent = {
          description = "Dispatch Password Requests to unl0kr";

          unitConfig.DefaultDependencies = false;
          unitConfig.ConditionPathExists = "!/run/plymouth/pid";

          after = [
            "plymouth-start.service"
          ];
          conflicts = [
            "emergency.service"
            "shutdown.target"
            "initrd-switch-root.target"
          ];
          before = [
            "emergency.service"
            "shutdown.target"
            "initrd-switch-root.target"
          ];

          serviceConfig.ExecStart = "${cfg.package}/libexec/unl0kr-agent";
        };
      };

      paths = {
        unl0kr-agent = {
          description = "Dispatch Password Requests to unl0kr Directory Watch";

          unitConfig.DefaultDependencies = false;
          unitConfig.ConditionPathExists = "!/run/plymouth/pid";

          after = [
            "plymouth-start.service"
          ];
          conflicts = [
            "emergency.service"
            "shutdown.target"
          ];
          before = [
            "paths.target"
            "cryptsetup.target"
            "emergency.service"
            "shutdown.target"
          ];

          pathConfig = {
            DirectoryNotEmpty = "/run/systemd/ask-password";
            MakeDirectory = true;
          };
        };
      };
    };
  };
}
