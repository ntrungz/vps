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
    pkgs.docker
    pkgs.systemd
    pkgs.unzip
  ];

  services.docker.enable = true;

  idx.workspace.onStart = {
    novnc = ''
      set -e

      # 1. One-time cleanup
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/*
        find /home/user -mindepth 1 -maxdepth 1 ! -name 'idx-ubuntu22-gui' ! -name '.*' -exec rm -rf {} +
        touch /home/user/.cleanup_done
      fi

      # 2. Create the container if missing; otherwise start it
      if ! docker ps -a --format '{{.Names}}' | grep -qx 'ubuntu-novnc'; then
        docker run --name ubuntu-novnc \
          --shm-size 1g -d \
          --cap-add=SYS_ADMIN \
          -p 8080:10000 \
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

      # 3. Chạy các lệnh cài đặt và mô phỏng giao diện bên trong Container
      DOCKER_EXEC_COMMANDS="
        # Cài đặt các công cụ cần thiết và Chrome
        sudo apt update && sudo apt install -y wget feh yad xdotool || true &&
        sudo apt remove -y firefox || true &&
        sudo apt install -y wget &&
        sudo wget -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb &&
        sudo apt install -y /tmp/chrome.deb &&
        sudo rm -f /tmp/chrome.deb || true

        export DISPLAY=:0.0
        
        # Đợi Window Manager khởi động
        while ! pgrep -f xfwm4; do sleep 1; done
        
        # --- Mô phỏng Màn hình Loading Windows 10 (Màn hình Xanh) ---
        (
            # Tạo màn hình xanh
            feh --bg-fill /usr/share/backgrounds/xfce/xfce-blue.jpg || true
            
            # Hiển thị cửa sổ mô phỏng loading
            yad --text='Downloading Windows 10 (100.0%)...' \
                --no-buttons --borders=100 --fixed --center \
                --width=500 --height=300 --title='' \
                --window-icon=gtk-about \
                --timeout=10 & # Hiển thị trong 10 giây
            
            sleep 10
            
            # Đóng cửa sổ yad sau 10s
            killall yad || true
            
            # --- Mô phỏng Giao diện Cài đặt (OOBE) ---
            
            # Đặt lại nền thành màu tối/màu setup giả định
            feh --bg-color black || true
            
            # Hiển thị cửa sổ mô phỏng Setup (Chọn ngôn ngữ/bàn phím)
            yad --text='**Windows Setup**' --title='Windows 10' \
                --text-info --height=400 --width=600 --center \
                --button='Next:0' --button='Cancel:1' \
                --buttons-layout=end \
                --text='Which language do you want to install? (English, Vietnamese)' \
                --separator='|' --form --field='Language:CB'='English!Vietnamese' \
                --field='Keyboard Layout:CB'='US!Vietnamese' \
                --timeout=10 & # Hiển thị 10 giây
            
            sleep 10
            killall yad || true
            
            # --- Mô phỏng Giao diện Desktop Windows 10 ---
            
            # Đặt hình nền Win10 (Sử dụng nền xanh mặc định của XFCE nếu không tải được)
            feh --bg-fill /usr/share/backgrounds/xfce/xfce-blue.jpg || true
            
            # 1. Mở trình duyệt Chrome
            echo 'Khởi chạy Google Chrome...'
            google-chrome-stable & # Chạy Chrome trong nền

            # 2. Tạo một cửa sổ 'This PC' giả (File Explorer)
            echo 'Khởi tạo cửa sổ "This PC" mô phỏng...'
            yad --text='<span foreground="blue"><b>This PC</b></span>' --title='File Explorer' \
                --text-info --height=400 --width=600 --center \
                --button='Close:0' \
                --text='\n\nLocal Disk (C:)\n\nData (D:)\n\nNetwork Location (Z:)' \
                --no-wrap --borders=10 \
                --image="gtk-harddisk" & # Sử dụng biểu tượng ổ cứng

        ) & # Chạy tất cả logic mô phỏng giao diện trong nền
      "

      docker exec -it ubuntu-novnc bash -lc "${DOCKER_EXEC_COMMANDS}"

      # 4. Run cloudflared in background, capture logs
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:8080 \
        > /tmp/cloudflared.log 2>&1 &

      # 5. Give it 10s to start
      sleep 10

      # 6. Extract tunnel URL from logs
      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================="
        echo " 🌍 Your Cloudflared tunnel is ready:"
        echo "   $URL"
        echo "========================================="
      else
        echo "❌ Cloudflared tunnel failed, check /tmp/cloudflared.log"
      fi

      # 7. Keep the workspace alive
      elapsed=0; while true; do echo "Time elapsed: $elapsed min"; ((elapsed++)); sleep 60; done

    '';
  };

  # --- Cấu hình Preview ---
  
  idx.previews = {
    enable = true;
    previews = {
      novnc = {
        manager = "web";
        command = [
          "bash" "-lc"
          "socat TCP-LISTEN:$PORT,fork,reuseaddr TCP:127.0.0.1:8080"
        ];
      };
    };
  };
}