#!/bin/sh
set -e
# Host keys live in a volume: DeckTerm pins them, so new keys after a restart would lock the reviewer out.
for t in ed25519 ecdsa; do
  [ -f /keys/ssh_host_${t}_key ] || ssh-keygen -q -t $t -N '' -f /keys/ssh_host_${t}_key
done
echo "demo:${DEMO_PASSWORD:?}" | chpasswd
exec /usr/sbin/sshd -D -e
