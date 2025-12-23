{ config, pkgs, lib, ... }:

{
  # --- HARDWARE & DRIVERS ---
  
  # Enable OpenGL/Vulkan access for applications
  hardware.graphics = {
    enable = true;
  };

  # Enable redistributable firmware (important for WiFi/BT cards on bare metal)
  hardware.enableAllFirmware = true;
}
