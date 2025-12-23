{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Enable SearXNG container or service
  # Since this is a simple flake, we'll try to use the native service if available,
  # but for stability in this custom environment, we might want to check if packages exist.
  # Assuming 24.11/unstable has services.searx.

  # Use SearXNG (Modern Fork)
  services.searx = {
    enable = true;

    # Try to use SearXNG package if available, otherwise fallback to default
    package = pkgs.searxng;

    # Configure settings (YAML structure)
    settings = {
      server = {
        port = 8888;
        bind_address = "127.0.0.1";
        secret_key = "omni-os-fixed-secret-key-123456"; # Fixed secure key
        image_proxy = false;
        limiter = false; # Disable rate limiter
      };
      search = {
        safe_search = 0; # Moderate
        autocomplete = "google";
        formats = [
          "html"
          "json"
        ]; # Explicitly allow JSON
      };
      # Default engines are usually fine, but let's be safe
      engines = [
        {
          name = "duckduckgo";
          engine = "duckduckgo";
          enabled = false;
        }
        {
          name = "google";
          engine = "google";
          enabled = true;
        }
        {
          name = "bing";
          engine = "bing";
          enabled = false;
        }
        {
          name = "qwant";
          engine = "qwant";
          enabled = false;
        }
        {
          name = "wikipedia";
          engine = "wikipedia";
          enabled = true;
        }
      ];
    };
  };

  # Open port firewall if needed (localhost only usually doesn't need it, but good practice if expanding)
  networking.firewall.allowedTCPPorts = [ 8888 ];
}
