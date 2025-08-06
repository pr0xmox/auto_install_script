
#Dọn gói cũ tránh xung đột
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    if dpkg -l | grep -qw "$pkg"; then
        echo "Removing package: $pkg"
        sudo apt remove -y "$pkg"
    else
        echo "Package not installed: $pkg"
    fi
done


# thêm key gpg của docker
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# thêm repo apt cùa docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update

# cài các gói latest của docker
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

clear
echo "Your installation completed"
echo "Your IP: $(hostname -I)"
echo "Your OS Version: $(. /etc/os-release && echo "$VERSION_CODENAME")"
#Script tự động cài Docker cho OS base Debian by Nguyễn Hải
