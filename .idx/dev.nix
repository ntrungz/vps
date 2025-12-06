{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.docker
    pkgs.cloudflared
    pkgs.socat
    pkgs.netcat
    pkgs.coreutils
    pkgs.apt
    pkgs.systemd
    pkgs.unzip
  ];

  services.docker.enable = true;

  idx.workspace.onStart = {
    novnc = ''
      set -e

      mkdir -p ~/vps
      cd ~/vps || cd /

      echo "▶ Tạo Docker network cố định cho container..."
      if ! docker network ls --format '{{.Name}}' | grep -qx 'novnc-net'; then
        docker network create --subnet=172.25.0.0/16 novnc-net
      fi

      echo "▶ Khởi động container NoVNC..."
      if ! docker ps -a --format '{{.Names}}' | grep -qx 'ubuntu-novnc'; then
        docker pull thuonghai2711/ubuntu-novnc-pulseaudio:22.04

        docker run --name ubuntu-novnc \
          --net novnc-net --ip 172.25.0.2 \
          -p 10000:10000 \
          -p 5900:5900 \
          --shm-size 2g \
          --cap-add SYS_ADMIN \
          -d thuonghai2711/ubuntu-novnc-pulseaudio:22.04
      else
        docker start ubuntu-novnc || true
      fi

      echo "⏳ Đợi NoVNC khởi động (port 10000)..."
      for i in {1..30}; do
        if nc -z 172.25.0.2 10000; then
          echo "✅ NoVNC ready!"
          break
        fi
        echo "   ➜ Chưa mở, đợi thêm..."
        sleep 2
      done

      if ! nc -z 172.25.0.2 10000; then
        echo "❌ NoVNC không mở port 10000, Cloudflared sẽ dừng để tránh 502"
        exit 1
      fi

      echo "🚀 Khởi chạy Cloudflared..."
      nohup cloudflared tunnel --url http://172.25.0.2:10000 \
        > /tmp/cloudflared.log 2>&1 &

      sleep 10
      URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)

      echo "========================================="
      if [ -n "$URL" ]; then
        echo " 🌍 Cloudflared Tunnel:"
        echo "     $URL"
      else
        echo "❌ Không lấy được URL. Kiểm tra /tmp/cloudflared.log"
      fi

      echo ""
      echo " 🔧 Direct Control IP (cố định, cho phần mềm điều khiển):"
      echo "     172.25.0.2 : 10000"
      echo "========================================="

      # Giữ script sống
      while true; do sleep 60; done
    '';
  };

  idx.previews = {
    enable = true;
    previews.novnc = {
      manager = "web";
      command = [
        "bash" "-lc"
        "socat TCP-LISTEN:$PORT,fork TCP:172.25.0.2:10000"
      ];
    };
  };
}
