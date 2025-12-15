{ config, pkgs, lib, ... }:

{
  # --- KONFIGURACJA VM: GRAFIKA I HARDWARE ---
  virtualisation = {
    memorySize = 8192;
    diskSize = 8192;
    cores = 6;
    graphics = true; # włączone (GUI QEMU) — GL wyłączone (software rendering)
    
    qemu.options = [
      # virtio-vga jest stabilniejsze dla kursora niż virtio-gpu-pci w trybie bez GL
      "-device virtio-vga"
      "-display gtk,gl=off" 
      "-device intel-hda"
      "-device hda-duplex"
      # Tablet jest kluczowy dla myszki w VM (absolutne pozycjonowanie)
      "-device virtio-tablet-pci" 
    ];
  };

  # Próba wymuszenia rozdzielczości na poziomie jądra (jako fallback)
  boot.kernelParams = [ "video=1920x1080@60" ];
}
