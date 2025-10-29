#!/bin/bash

# WordPress Docker Compose Installation Script
# This script automates the setup of WordPress with Docker, Nginx reverse proxy, and SSL

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== WordPress Docker Compose Setup ===${NC}\n"

# Check if script is run from correct directory
if [ ! -f "docker-compose.yml" ] || [ ! -f "env.example" ]; then
    echo -e "${RED}Error: docker-compose.yml or env.example not found!${NC}"
    echo "Please run this script from the project root directory."
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed!${NC}"
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not installed!${NC}"
    exit 1
fi

# Step 1: Copy env.example to .env
echo -e "${YELLOW}Step 1: Creating .env file${NC}"
if [ -f ".env" ]; then
    read -p ".env file already exists. Overwrite? (y/n): " overwrite
    if [ "$overwrite" != "y" ]; then
        echo "Using existing .env file..."
    else
        cp env.example .env
        echo -e "${GREEN}.env file created${NC}"
    fi
else
    cp env.example .env
    echo -e "${GREEN}.env file created${NC}"
fi

echo ""

# Step 2: Ask for domain name
echo -e "${YELLOW}Step 2: Domain Configuration${NC}"
read -p "Enter domain name (e.g., example.com): " domain

# Validate domain name
if [ -z "$domain" ]; then
    echo -e "${RED}Error: Domain name cannot be empty!${NC}"
    exit 1
fi

echo -e "${GREEN}Domain: $domain${NC}"
echo ""

# Step 3: Show occupied ports
echo -e "${YELLOW}Step 3: Port Configuration${NC}"
echo "Currently occupied ports:"
if command -v ss &> /dev/null; then
    ss -tuln | grep LISTEN | awk '{print $5}' | sed 's/.*://' | sort -un | head -20
elif command -v netstat &> /dev/null; then
    netstat -tuln | grep LISTEN | awk '{print $4}' | sed 's/.*://' | sort -un | head -20
else
    echo -e "${YELLOW}Warning: Cannot detect occupied ports (ss/netstat not available)${NC}"
fi

echo ""

# Step 4: Ask for port number
read -p "Enter port number for WordPress (default: 80): " port
port=${port:-80}

# Validate port number
if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo -e "${RED}Error: Invalid port number!${NC}"
    exit 1
fi

echo -e "${GREEN}Port: $port${NC}"
echo ""

# Step 5: Ask for DB root password
echo -e "${YELLOW}Step 4: Database Configuration${NC}"
read -sp "Enter MySQL root password: " db_password
echo ""

# Validate password
if [ -z "$db_password" ]; then
    echo -e "${RED}Error: Password cannot be empty!${NC}"
    exit 1
fi

echo -e "${GREEN}Password saved${NC}"
echo ""

# Step 6: Update .env file
echo -e "${YELLOW}Step 5: Updating .env file${NC}"
sed -i.bak "s/^IP=.*/IP=127.0.0.1/" .env
sed -i.bak "s/^PORT=.*/PORT=$port/" .env
sed -i.bak "s/^DB_ROOT_PASSWORD=.*/DB_ROOT_PASSWORD=$db_password/" .env
sed -i.bak "s/^DB_NAME=.*/DB_NAME=wordpress/" .env
rm .env.bak 2>/dev/null || true

echo -e "${GREEN}.env file updated${NC}"
echo ""

# Step 7: Ask for Nginx configuration directory
echo -e "${YELLOW}Step 6: Nginx Configuration${NC}"
echo "Select Nginx configuration directory:"
echo "1) sites-available (Debian/Ubuntu)"
echo "2) conf.d (CentOS/RHEL)"
read -p "Enter choice (1 or 2): " nginx_choice

if [ "$nginx_choice" != "1" ] && [ "$nginx_choice" != "2" ]; then
    echo -e "${RED}Error: Invalid choice!${NC}"
    exit 1
fi

# Step 8: Request SSL certificate
echo ""
echo -e "${YELLOW}Step 7: Requesting SSL Certificate${NC}"
echo "Running certbot for domain: $domain"

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    echo -e "${RED}Error: certbot is not installed!${NC}"
    echo "Install it with: sudo apt install certbot python3-certbot-nginx"
    exit 1
fi

sudo certbot certonly --nginx -d "$domain"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Certificate request failed!${NC}"
    exit 1
fi

echo -e "${GREEN}SSL certificate obtained${NC}"
echo ""

# Step 9: Configure Nginx
echo -e "${YELLOW}Step 8: Setting up Nginx configuration${NC}"

# Check if Nginx config template exists
if [ ! -f "Nginx/example.com" ]; then
    echo -e "${RED}Error: Nginx/example.com template not found!${NC}"
    exit 1
fi

# Copy and modify Nginx config based on user choice
if [ "$nginx_choice" == "1" ]; then
    # sites-available
    nginx_config_file="/etc/nginx/sites-available/$domain"
    
    sudo cp Nginx/example.com "$nginx_config_file"
    
    # Replace example.com with actual domain
    sudo sed -i "s/example\.com/$domain/g" "$nginx_config_file"
    
    # Replace port 80 with user-selected port
    sudo sed -i "s|http://localhost:80|http://localhost:$port|g" "$nginx_config_file"
    
    echo -e "${GREEN}Nginx config created at: $nginx_config_file${NC}"
    
    # Create symlink
    echo "Creating symlink..."
    sudo ln -sf "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
    echo -e "${GREEN}Symlink created${NC}"
    
else
    # conf.d
    nginx_config_file="/etc/nginx/conf.d/${domain}.conf"
    
    sudo cp Nginx/example.com "$nginx_config_file"
    
    # Replace example.com with actual domain
    sudo sed -i "s/example\.com/$domain/g" "$nginx_config_file"
    
    # Replace port 80 with user-selected port
    sudo sed -i "s|http://localhost:80|http://localhost:$port|g" "$nginx_config_file"
    
    echo -e "${GREEN}Nginx config created at: $nginx_config_file${NC}"
fi

echo ""

# Step 10: Test Nginx configuration
echo -e "${YELLOW}Step 9: Testing Nginx configuration${NC}"
sudo nginx -t

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Nginx configuration test failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Nginx configuration is valid${NC}"
echo ""

# Step 11: Reload and restart Nginx
echo -e "${YELLOW}Step 10: Reloading Nginx${NC}"
sudo systemctl reload nginx
echo -e "${GREEN}Nginx reloaded${NC}"

echo ""
echo -e "${YELLOW}Step 11: Restarting Nginx${NC}"
sudo systemctl restart nginx
echo -e "${GREEN}Nginx restarted${NC}"

echo ""

# Step 12: Create necessary directories
echo -e "${YELLOW}Step 12: Creating WordPress directories${NC}"
mkdir -p wp-app wp-data

echo -e "${GREEN}Directories created${NC}"
echo ""

# Step 13: Start Docker containers
echo -e "${YELLOW}Step 13: Starting Docker containers${NC}"
echo "Running: docker compose up -d --build"
echo "This may take a few minutes..."

docker compose up -d --build

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Docker compose failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Docker containers started successfully${NC}"
echo ""

# Final message
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Your WordPress site is now running!"
echo ""
echo -e "${YELLOW}Please visit:${NC} ${GREEN}https://$domain${NC}"
echo ""
echo -e "WordPress will guide you through the final setup steps."
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  - View logs:    docker compose logs -f"
echo "  - Stop:         docker compose stop"
echo "  - Start:        docker compose start"
echo "  - Restart:      docker compose restart"
echo "  - Remove:       docker compose down"
echo ""
echo -e "${YELLOW}Database backup:${NC}"
echo "  - Run:          ./export.sh"
echo ""