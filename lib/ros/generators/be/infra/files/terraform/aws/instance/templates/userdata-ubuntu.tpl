#cloud-config
repo_update: true
repo_upgrade: all

packages:
  - git
  - docker.io
  - docker-compose
  - ansible
  - python-pip

runcmd:
  %{ for key in ssh_public_keys ~}
  - "echo ${key} >> /home/ubuntu/.ssh/authorized_keys"
  %{ endfor ~}
