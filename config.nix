{
  homelab_wg_ip = "10.100.0.10";

  tcp_ports = [
    25565 # minecraft
    2222 # ssh for minecraft
    2223 # ssh for amnezia vm
  ];

  enable_proxy_protocol = true;

  tcp_port_ranges = ["35000-35010"];

  tcp_port_mappings = { "25" = 2525; };

  wg_mtu = 1408;
  wg_listen_port = 55055;
  wg_homelab_peer_pubkey = "wFLCjKjqIRATFeRKhNw0ESc64H0IRxN1aLvR5xSNYxU=";

  udp_ports = [];
  udp_port_ranges = ["35000-35010"];

  ssh_authorized_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ1K76M6pG9qKUpOj0n1/KxmDABQmXw/GxfjHktzSZY2"];
}
