{
  lib,
  pkgs,
  hostConfig,
  ...
}: let
  cfg = hostConfig;

  caddy-l4 = pkgs.caddy.withPlugins {
    plugins = ["github.com/mholt/caddy-l4@v0.0.0-20251124224044-66170bec9f4d"];
    hash = "sha256-chQXA0IOPcM223+eRX9ZpUrV6LUB/R0PyziZy1GHDs4=";
  };

  tcpPortMappings = cfg.tcp_port_mappings or {};
  tcpPortRanges = cfg.tcp_port_ranges or [];
  udpPortRanges = cfg.udp_port_ranges or [];
  enableL4 = cfg.enable_proxy_protocol or false;

  # l4 proxy handles 443, otherwise nftables does
  tcpDnatPorts = cfg.tcp_ports ++ lib.optional (!enableL4) 443;
  mappedExtPorts = map lib.toInt (lib.attrNames tcpPortMappings);

  mkPortSet = ports: "{ ${lib.concatMapStringsSep ", " toString ports} }";

  mkRangeRules = proto: ranges:
    lib.concatMapStringsSep "\n          "
    (r: "${proto} dport ${r} dnat to ${cfg.homelab_wg_ip}")
    ranges;

  mkMappingRules = proto: mappings:
    lib.concatStringsSep "\n          "
    (lib.mapAttrsToList
      (ext: int: "${proto} dport ${ext} dnat to ${cfg.homelab_wg_ip}:${toString int}")
      mappings);

  ruleIf = cond: rule: lib.optionalString cond rule;

  parseRange = s: let
    parts = lib.splitString "-" s;
  in {
    from = lib.toInt (builtins.elemAt parts 0);
    to = lib.toInt (builtins.elemAt parts 1);
  };
in {
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = false;
    };
    kernel.sysctl."net.ipv4.ip_forward" = 1;
  };

  networking = {
    hostName = cfg.host_name;

    nftables = {
      enable = true;
      tables.nat = {
        family = "ip";
        content = ''
          chain prerouting {
            type nat hook prerouting priority -100; policy accept;
            ${ruleIf (tcpPortMappings != {}) (mkMappingRules "tcp" tcpPortMappings)}
            ${ruleIf (tcpDnatPorts != []) "tcp dport ${mkPortSet tcpDnatPorts} dnat to ${cfg.homelab_wg_ip}"}
            ${ruleIf (tcpPortRanges != []) (mkRangeRules "tcp" tcpPortRanges)}
            ${ruleIf (cfg.udp_ports != []) "udp dport ${mkPortSet cfg.udp_ports} dnat to ${cfg.homelab_wg_ip}"}
            ${ruleIf (udpPortRanges != []) (mkRangeRules "udp" udpPortRanges)}
          }
          chain postrouting {
            type nat hook postrouting priority 100; policy accept;
            oifname "wg0" masquerade
            iifname "wg0" oifname "eth0" masquerade
          }
        '';
      };
    };

    firewall = {
      enable = true;
      trustedInterfaces = ["wg0"];
      allowedTCPPorts = [22 443] ++ cfg.tcp_ports ++ mappedExtPorts;
      allowedUDPPorts = [cfg.wg_listen_port] ++ cfg.udp_ports;
      allowedTCPPortRanges = map parseRange tcpPortRanges;
      allowedUDPPortRanges = map parseRange udpPortRanges;
    };

    wireguard.interfaces.wg0 = {
      mtu = cfg.wg_mtu;
      ips = ["${cfg.vps_wg_ip}/24"];
      listenPort = cfg.wg_listen_port;
      privateKeyFile = "/var/lib/wireguard/private.key";
      generatePrivateKeyFile = true;
      peers = [
        {
          publicKey = cfg.wg_homelab_peer_pubkey;
          allowedIPs = ["${cfg.homelab_wg_ip}/32"];
        }
      ];
    };
  };

  services.caddy = lib.mkIf enableL4 {
    enable = true;
    package = caddy-l4;
    globalConfig = ''
      admin off
      layer4 {
        :443 {
          route {
            proxy {
              proxy_protocol v2
              upstream ${cfg.homelab_wg_ip}:443
            }
          }
        }
      }
    '';
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  users.users.root.openssh.authorizedKeys.keys = cfg.ssh_authorized_keys;

  system.activationScripts.show-wireguard-key = ''
    if [ -f /var/lib/wireguard/private.key ]; then
      echo ""
      echo "vps wg pub key:"
      ${pkgs.wireguard-tools}/bin/wg pubkey < /var/lib/wireguard/private.key
      echo ""
    fi
  '';

  nix.settings.experimental-features = ["nix-command" "flakes"];
  environment.systemPackages = [pkgs.wireguard-tools];
  system.stateVersion = "25.05";
}
