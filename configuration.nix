{
  lib,
  pkgs,
  ...
}: let
  config = {
    homelab_ip = "10.100.0.2";

    tcp_ports = [
      80 # http
      443 # https

      25565 # minecraft
      25 # smtp
      2222 # ssh for minecraft
    ];

    udp_ports = [];

    wg_vps_addr_cidr = "10.100.0.1/24";
    wg_homelab_peer_ip = "10.100.0.2/32";
    wg_listen_port = 55055;
    wg_mtu = 1408;

    wg_private_key_path = "/var/lib/wireguard/private.key";
    wg_homelab_peer_pubkey = "W2w72HnZqCouR1gRuB7LB8NgGk3pBULzxyWezXILO3c=";

    ssh_authorized_keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCfsYNHpOOrLtFd3rv8RPIl+WIDi3ePHBtffp6vmqWbY9NghnPXIUCLcuJiC845xLtOLAOLdSSn0MT2QqcPwesXfAZI5aBks2ojsNsPHB9ucoGrNRAln877RTju3iEMafUs2baSR9G8NBsy7FkitiLlRmoJlYYoLh0mPP+GB3eUldfDiXTORtRzXGfUSbLMam81WqhGn+8k+NLxmSZQEnd/HqNhlL7cy69yJqDCXcjUHbrttGqIZtoYzHq+p4GUqwBGTJmCM11PLOvtk1XlTAjZ1aAFna/A7tca9qTAIW1PJ9JSWbyIw10BXuDBY7UT565tTF8R/0zVZpu85dnH7zZn ssh-key-2025-09-03"
    ];

    host_name = "vps-proxy";
    time_zone = "UTC";
  };

  # derived helpers (auto)
  tcp_set = "{ " + lib.concatStringsSep ", " (map toString config.tcp_ports) + " }";
  udp_set = "{ " + lib.concatStringsSep ", " (map toString config.udp_ports) + " }";
  have_tcp = config.tcp_ports != [];
  have_udp = config.udp_ports != [];
in {
  # boot + basics
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  networking.hostName = config.host_name;
  time.timeZone = config.time_zone;
  i18n.defaultLocale = "en_US.UTF-8";
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # enable ipv4 forwarding (required for nat)
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  # nftables nat: public -> homelab (dnat), and replies back via wg0 (snat)
  networking.nftables = {
    enable = true;
    tables.nat = {
      family = "ip";
      content = ''
        chain prerouting {
          type nat hook prerouting priority -100; policy accept;
          ${lib.optionalString have_tcp "tcp dport ${tcp_set} dnat to ${config.homelab_ip}"}
          ${lib.optionalString have_udp "udp dport ${udp_set} dnat to ${config.homelab_ip}"}
        }
        chain postrouting {
          type nat hook postrouting priority 100; policy accept;
          ${lib.optionalString have_tcp "oifname \"wg0\" ip daddr ${config.homelab_ip} tcp dport ${tcp_set} masquerade"}
          ${lib.optionalString have_udp "oifname \"wg0\" ip daddr ${config.homelab_ip} udp dport ${udp_set} masquerade"}
        }
      '';
    };
  };

  # firewall input policy: open only ssh, wg, and the forwarded service ports
  networking.firewall = {
    enable = true;
    trustedInterfaces = ["wg0"];
    allowedTCPPorts = [22] ++ config.tcp_ports;
    allowedUDPPorts = [config.wg_listen_port] ++ config.udp_ports;
  };

  # wireguard device
  networking.wireguard.interfaces.wg0 = {
    mtu = config.wg_mtu;
    ips = [config.wg_vps_addr_cidr];
    listenPort = config.wg_listen_port;
    privateKeyFile = config.wg_private_key_path;
    generatePrivateKeyFile = true;

    peers = [
      {
        publicKey = config.wg_homelab_peer_pubkey;
        allowedIPs = [config.wg_homelab_peer_ip];
      }
    ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  users.users.root.openssh.authorizedKeys.keys = config.ssh_authorized_keys;

  # print wireguard public key at activation
  system.activationScripts.show-wireguard-key = ''
    if [ -f ${lib.escapeShellArg config.wg_private_key_path} ]; then
      echo "========================================="
      echo "vps wireguard public key:"
      ${pkgs.wireguard-tools}/bin/wg pubkey < ${lib.escapeShellArg config.wg_private_key_path}
      echo "add this to your homelab peer"
      echo "========================================="
    fi
  '';

  environment.systemPackages = [pkgs.wireguard-tools];

  system.stateVersion = "25.05";
}
