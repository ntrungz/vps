{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.docker
    pkgs.cloudflared
    pkgs.socat
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.sudo
    pkgs.apt
    pkgs.systemd
    pkgs.unzip
    pkgs.netcat
  ];

  services.docker.enable = true;

  idx.workspace.onStart = {
    novnc = ''
      set -e

      mkdir -p ~/vps
      cd ~/vps || true

      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/* || true
        find /home/user -mindepth 1 -maxdepth 1 ! -name 'idx-ubuntu22-gui' ! -name '.*' -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
      fi

      if ! docker ps -a --format '{{.Names}}' | grep -qx 'ubuntu-novnc'; then
        docker pull thuonghai2711/ubuntu-novnc-pulseaudio:22.04
        docker run --name ubuntu-novnc \
          --shm-size 1g -d \
          --cap-add=SYS_ADMIN \
          -p 10000:10000 \
          -e VNC_PASSWD=12345678 \
          -e PORT=10000 \
          -e AUDIO_PORT=1699 \
          -e WEBSOCKIFY_PORT=6900 \
          -e VNC_PORT=5900 \
          -e SCREEN_WIDTH=1024 \
          -e SCREEN_HEIGHT=768 \
          -e SCREEN_DEPTH=24 \
          thuonghai2711/ubuntu-novnc-pulseaudio:22.04
      else
        docker start ubuntu-novnc || true
      fi

      ########################################
      # Install Antigravity INSIDE container (ROOT)
      ########################################
      docker exec -u 0 ubuntu-novnc bash -lc "
        set -e
        if [ ! -f /etc/apt/sources.list.d/antigravity.list ]; then
          echo '[+] Installing Antigravity inside container (root)'

          apt update
          apt install -y curl gnupg ca-certificates

          mkdir -p /etc/apt/keyrings

          curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
            gpg --dearmor -o /etc/apt/keyrings/antigravity-repo-key.gpg

          echo 'deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main' \
            > /etc/apt/sources.list.d/antigravity.list

          apt update
          apt install -y antigravity
        else
          echo '[+] Antigravity already installed in container'
        fi
      "
      ########################################

      while ! nc -z localhost 10000; do sleep 1; done

      docker exec -u 0 ubuntu-novnc bash -lc "
        apt update &&
        apt remove -y firefox || true &&
        apt install -y wget &&
        wget -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb &&
        apt install -y /tmp/chrome.deb &&
        rm -f /tmp/chrome.deb
      "

      nohup cloudflared tunnel --no-autoupdate --url http://localhost:10000 \
        > /tmp/cloudflared.log 2>&1 &

      sleep 10

      URL=""
      for i in {1..15}; do
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        [ -n "$URL" ] && break
        sleep 1
      done

      if [ -n "$URL" ]; then
        echo "========================================="
        echo " 🌍 Your Cloudflared tunnel is ready:"
        echo "   $URL"
        echo "  Mật khẩu vps của bạn là:12345678"
        echo "=========================================="
      else
        echo "❌ Cloudflared tunnel failed"
      fi

      elapsed=0
      while true; do
        echo "Time elapsed: $elapsed min"
        ((elapsed++))
        sleep 60
      done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      novnc = {
        manager = "web";
        command = [
          "bash" "-lc"
          "socat TCP-LISTEN:$PORT,fork,reuseaddr TCP:127.0.0.1:10000"
        ];
      };
    };
  };
}
