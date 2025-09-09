#!/bin/bash

# Define the 'kaliup' command
echo "################################################################################################"
echo "Creating 'kaliup' command..."
sudo bash -c 'cat > /usr/local/bin/kaliup << EOF
#!/bin/bash
echo "Starting system update and upgrade..."
sudo apt update --fix-missing && sudo apt upgrade -y && sudo apt full-upgrade -y
sudo apt autoremove -y && sudo apt autoclean
sudo apt --fix-broken install -y && sudo apt-get check
echo "System update and upgrade complete!"
EOF'
sudo chmod +x /usr/local/bin/kaliup
echo "'kaliup' command created successfully!"

# Update sources.list
echo "################################################################################################"
echo "Updating sources.list..."
#sudo bash -c 'cat > /etc/apt/sources.list << EOF
# Kali Linux Rolling Repository
#deb http://ftp.acc.umu.se/mirror/kali.org/kali kali-rolling main contrib non-free non-free-firmware
#deb-src http://ftp.acc.umu.se/mirror/kali.org/kali kali-rolling main contrib non-free non-free-firmware
#deb http://kali.download/kali kali-rolling main contrib non-free non-free-firmware
#deb-src http://kali.download/kali kali-rolling main contrib non-free non-free-firmware
#EOF'
sudo apt purge spike -y

# Run 'kaliup' command
echo "################################################################################################"
echo "Running 'kaliup' command..."
kaliup

# Clone and execute PimpMyKali repository
echo "################################################################################################"
echo "Cloning PimpMyKali repository..."
git clone https://github.com/Dewalt-arch/pimpmykali
cd pimpmykali || exit
echo "Running PimpMyKali script..."
sudo ./pimpmykali.sh
cd ..

# Function to prompt user for installation
yes_no_prompt() {
    while true; do
        read -rp "$1 (y/n): " choice
        case "$choice" in
            [Yy]*) return 0 ;;  # Yes, proceed
            [Nn]*) return 1 ;;  # No, skip
            *) echo "Please enter y or n." ;;
        esac
done
}

# Install Docker if user agrees
if yes_no_prompt "Do you want to install Docker?"; then
    echo "################################################################################################"
    echo "Installing Docker..."
    sudo apt update -y    # Optional but good practice to update package lists
    sudo apt install -y docker.io    # Install Docker
    sudo systemctl enable docker --now    # Enable Docker service to start on boot and start it immediately
    sudo systemctl start docker    # Start Docker service
    # Add your user to the docker group to allow running docker without sudo
    sudo usermod -aG docker "$USER"
    # Now, apply the group membership change to the current session without logging out
    exec sudo su -l "$USER"
    echo "Docker installed and configured successfully."
    echo "################################################################################################"
    echo "Installing Docker..."
    echo "################################################################################################"
    sudo apt update -y    # Optional but good practice to update package lists
    sudo apt install -y docker.io    # Install Docker
    sudo systemctl enable docker --now    # Enable Docker service to start on boot and start it immediately
    sudo systemctl start docker    # Start Docker service
    sudo usermod -aG docker "$USER"
    exec sudo su -l "$USER"
    sudo apt install docker-compose
    echo "Docker installed and configured successfully."
    echo "################################################################################################"
else
    echo "Skipping Docker installation."
fi

# Install Kubernetes tools if user agrees
if yes_no_prompt "Do you want to install Kubernetes tools?"; then
    echo "################################################################################################"
    echo "Installing Kubernetes tools..."
    sudo apt install -y apt-transport-https ca-certificates curl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    echo "kubectl installed successfully."
else
    echo "Skipping Kubernetes installation."
fi

# Install Minikube if user agrees
if yes_no_prompt "Do you want to install Minikube?"; then
    echo "################################################################################################"
    echo "Installing Minikube..."
    curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube
    sudo mv minikube /usr/local/bin/
    echo "Minikube installed successfully."
else
    echo "Skipping Minikube installation."
fi

# Install GNOME Desktop Environment if user agrees
if yes_no_prompt "Do you want to install GNOME Desktop Environment?"; then
    echo "################################################################################################"
    echo "Installing GNOME desktop environment..."
    sudo apt install -y kali-desktop-gnome
    echo "GNOME desktop environment installed successfully."
else
    echo "Skipping GNOME installation."
fi

# Script completion
echo "################################################################################################"
echo "Script execution completed."
echo "################################################################################################"
echo "------------------------------------------------------------------------------------------------"

