# Initial VPS Setup Guide

This guide assumes:

- Ubuntu 24.04 LTS
- You have already connected to the VPS using the root password
- You are working from your local machine

---

# 1. Change the Root Password (Optional)

If you want to change the root password:

```bash
passwd
```

Enter the new password when prompted.

---

# 2. Check for an Existing SSH Key

On your **local machine**:

```bash
ls ~/.ssh
```

If you already have:

```
id_ed25519
id_ed25519.pub
```

you can reuse them.

Otherwise, generate a new key.

---

# 3. Generate an SSH Key

On your **local machine**:

```bash
ssh-keygen -t ed25519 -C "your@email.com"
```

Accept the default location.

Optionally set a passphrase.

This creates:

```
~/.ssh/id_ed25519
~/.ssh/id_ed25519.pub
```

---

# 4. Copy the Public Key to the VPS

The easiest method:

```bash
ssh-copy-id root@YOUR_SERVER_IP
```

Enter the root password one final time.

---

## Manual Method

If `ssh-copy-id` isn't available:

Display your public key:

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the entire line.

On the VPS:

```bash
mkdir -p ~/.ssh
nano ~/.ssh/authorized_keys
```

Paste the key.

Save.

Set permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

---

# 5. Test Passwordless Login

Disconnect:

```bash
exit
```

Reconnect:

```bash
ssh root@YOUR_SERVER_IP
```

You should log in without entering the VPS password.

If you added a passphrase to your SSH key, you'll be prompted for that instead.

---

# 6. Disable Password Authentication (Recommended)

Edit the SSH configuration:

```bash
nano /etc/ssh/sshd_config
```

Find or add:

```text
PasswordAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
```

Restart SSH:

```bash
systemctl restart ssh
```

> **Important:** Before closing your current SSH session, open a second terminal and verify that you can still connect using your SSH key.

---

# 7. Update Ubuntu

```bash
apt update
apt upgrade -y
```

Reboot if required.

---

# 8. Create a Normal User

```bash
adduser mico
```

Grant sudo privileges:

```bash
usermod -aG sudo mico
```

---

# 9. Copy the SSH Key to the New User

As root:

```bash
mkdir -p /home/mico/.ssh

cp ~/.ssh/authorized_keys /home/mico/.ssh/

chown -R mico:mico /home/mico/.ssh

chmod 700 /home/mico/.ssh

chmod 600 /home/mico/.ssh/authorized_keys
```

Test:

```bash
ssh mico@YOUR_SERVER_IP
```

If successful, use this account for daily administration instead of root.

---

# 10. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
```

Allow your user to run Docker:

```bash
sudo usermod -aG docker $USER
```

Log out and log back in.

Verify Docker:

```bash
docker run hello-world
```

---

# 11. Enable the Firewall

Allow SSH:

```bash
sudo ufw allow OpenSSH
```

Allow HTTP:

```bash
sudo ufw allow 80
```

Allow HTTPS:

```bash
sudo ufw allow 443
```

Enable:

```bash
sudo ufw enable
```

Verify:

```bash
sudo ufw status
```

---

# 12. Final Checklist

You now have:

- ✅ Updated Ubuntu
- ✅ Passwordless SSH
- ✅ Password authentication disabled
- ✅ Non-root administrator account
- ✅ Docker installed
- ✅ Firewall enabled

The server is now ready for:

- Docker Compose
- PostgreSQL
- Backend API
- Caddy Reverse Proxy
- Automated backups

---

# Recommended Login Workflow

Instead of:

```bash
ssh root@YOUR_SERVER_IP
```

Use:

```bash
ssh mico@YOUR_SERVER_IP
```

Only use `sudo` when administrative privileges are required.