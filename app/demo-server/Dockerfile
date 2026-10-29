# The SSH server App Review signs in to: one password user, nothing else on it, and no way out (see compose.yml).
FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-server tmux htop vim-tiny nano less git ncurses-term \
 && rm -rf /var/lib/apt/lists/* /etc/update-motd.d/* /etc/legal /etc/ssh/ssh_host_* \
 && useradd -m -s /bin/bash demo && mkdir -p /run/sshd
COPY sshd_config /etc/ssh/sshd_config
COPY motd /etc/motd
COPY --chown=demo:demo home/ /home/demo/
RUN su demo -c "cd ~/project && git init -q -b main && git add . && git -c user.name=deck -c user.email=deck@deckterm-demo commit -qm 'Start the project'"
COPY entrypoint.sh /entrypoint.sh
CMD ["/entrypoint.sh"]
