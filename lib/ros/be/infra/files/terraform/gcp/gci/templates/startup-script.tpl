#! /bin/bash
apt-get update
apt-get install -y git

[$(id -u ${user})] || sudo useradd -m ${user}

su -c "mkdir -p ~/.ssh" - ${user}
echo "${ssh_public_key}" >> /home/${user}/.ssh/authorized_keys

su -c "mkdir -p ~/${project_name}/ros" - ${user}
su -c "git clone https://github.com/rails-on-services/setup.git ~/${project_name}/ros/setup" - ${user}
su -c "~/${project_name}/ros/setup/setup.sh" - ${user}
su -c "cd ~/${project_name}/ros/setup && ./backend.yml" - ${user}
su -c "cd ~/${project_name}/ros/setup && ./devops.yml" - ${user}
su -c "cd ~/${project_name}/ros/setup && ./cli.yml" - ${user}