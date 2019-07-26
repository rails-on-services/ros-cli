#cloud-config
repo_update: true
repo_upgrade: all

packages:
  - git

runcmd:
%{ for key in ssh_public_keys ~}
  - "echo ${key} >> /home/ubuntu/.ssh/authorized_keys"
%{ endfor ~}
  - su -c "mkdir -p ~/${project_name}/ros" - ubuntu
  - su -c "git clone https://github.com/rails-on-services/setup.git ~/${project_name}/ros/setup" - ubuntu
  - su -c "~/${project_name}/ros/setup/setup.sh" - ubuntu
  - su -c "cd ~/${project_name}/ros/setup && ./backend.yml" - ubuntu
  - su -c "cd ~/${project_name}/ros/setup && ./devops.yml" - ubuntu
