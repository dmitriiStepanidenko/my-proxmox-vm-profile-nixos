{
  config,
  pkgs,
  modulesPath,
  lib,
  system,
  ...
}: let
  pubKeys = lib.filesystem.listFilesRecursive ./pub_keys;
in {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    #(modulesPath + "/virtualisation/proxmox-image.nix")
  ];

  config = {
    nix = {
      optimise.automatic = true;
      gc = {
        automatic = true;
        dates = "5:00";
        options = "--delete-older-than 7d";
      };
      extraOptions = ''
        min-free = ${toString (100 * 1024 * 1024)}
        max-free = ${toString (1024 * 1024 * 1024)}
      '';
      settings = {
        # Cuz of this, I will need to recompile everything from store again
        #auto-optimise-store = true;

        # Allow remote updates with flakes and non-root users
        trusted-users = ["root" "@wheel" "dmitrii"];
        experimental-features = ["nix-command" "flakes"];
      };
    };

    networking.firewall = {
      allowedTCPPorts = [
        22
      ];
      interfaces.wg0 = {
        allowedUDPPorts = [
          9002
        ];
        allowedTCPPorts = [
          9002
        ];
      };
    };
    #Provide a default hostname
    networking.hostName = lib.mkDefault "base";
    services = {
      # Enable QEMU Guest for Proxmox
      qemuGuest.enable = true;
      avahi = {
        # Enable mDNS for `hostname.local` addresses
        enable = true;
        nssmdns4 = true;
        publish = {
          enable = true;
          addresses = true;
        };
      };

      fail2ban = {
        enable = true;
        maxretry = 5;
      };
      prometheus = {
        exporters = {
          node = {
            enable = true;
            enabledCollectors = ["systemd" "processes"];
            port = 9002;
          };
        };
      };

      # Enable ssh
      openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
        settings.KbdInteractiveAuthentication = false;
      };

      openssh.openFirewall = true;

      cloud-init.enable = lib.mkDefault true;
      alloy = {
        enable = true;
      };
    };
    environment.etc."alloy/config.alloy" = {
      text = ''
        local.file_match "local_files" {
          path_targets = [{"__path__" = "/var/log/*.log"}]
          sync_period = "5s"
        }
        loki.source.journal "${config.networking.hostName}" {
          forward_to = [loki.process.filter_logs.receiver]
        }
        loki.source.file "log_scrape" {
          targets    = local.file_match.local_files.targets
          forward_to = [loki.process.filter_logs.receiver]
          tail_from_end = true
        }
        loki.process "filter_logs" {
            stage.drop {
                source = ""
                expression  = ".*Connection closed by authenticating user root"
                drop_counter_reason = "noisy"
              }
            forward_to = [loki.write.grafana_loki.receiver]
        }
        loki.write "grafana_loki" {
            endpoint {
              url = "http://10.252.1.11:3030/loki/api/v1/push"
            }
          }
      '';
    };

    boot = {
      # Use the boot drive for grub
      loader.grub.enable = lib.mkDefault true;
      loader.grub.devices = ["nodev"];

      growPartition = lib.mkDefault true;
    };

    # Some sane packages we need on every system
    environment.systemPackages = with pkgs; [
      vim # for emergencies
      neovim
      git # for pulling nix flakes
      python # for ansible
      htop
      wget
      curl
    ];

    # Don't ask for passwords
    security.sudo.wheelNeedsPassword = false;
    users = {
      users = {
        "dmitrii".uid = 1000;
        "dmitrii".isNormalUser = true;
        "dmitrii".group = "dmitrii";
        "dmitrii".extraGroups = ["wheel" "docker" "networkmanager"];
        "dmitrii".openssh.authorizedKeys.keys = lib.lists.forEach pubKeys (key: builtins.readFile key);
        "root".openssh.authorizedKeys.keys = lib.lists.forEach pubKeys (key: builtins.readFile key);
      };
      groups.dmitrii.gid = 1000;
    };

    programs.ssh.startAgent = true;

    # Default filesystem
    fileSystems."/" = lib.mkDefault {
      device = "/dev/disk/by-label/nixos";
      autoResize = true;
      fsType = "ext4";
    };

    system.stateVersion = lib.mkDefault "24.11";
    services.cloud-init.network.enable = lib.mkDefault false;
  };
}
