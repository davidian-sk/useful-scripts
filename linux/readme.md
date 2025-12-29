# **Homelab Docker Manager**

A lightweight, terminal-based (TUI) dashboard to manage Docker containers and configuration files on your server. Designed for homelab enthusiasts who want fast access to logs, consoles, and configs without remembering complex Docker commands.

## **🚀 Key Features**

### **1\. Container Management**

* **Dashboard:** See real-time status of all containers (Up/Down) at a glance.  
* **Quick Actions:** Start, Stop, and Restart containers.  
* **Consoles:** Jump straight into a container's shell. The script automatically asks which shell you prefer (bash, sh, zsh, ash).  
* **Logs:**  
  * **Live Mode:** Watch logs stream in real-time (tail \-f).  
  * **Static Mode:** Scroll through the last N lines of history.

### **2\. Smart Config Editor (/opt)**

This is the workflow enhancer. Instead of manually finding files, editing them, and restarting containers:

1. **Browse:** Navigates your /opt directory with a smart filter (hides "noise" folders like logs, db\_data, .git).  
2. **Context:** Shows you which folder belongs to which container.  
3. **Safety:**  
   * **Auto-Backup:** Creates a timestamped .bak copy of any file before you edit it.  
   * **Restart Prompt:** If you change a file, the script detects which container "owns" that file (via mounts) and asks if you want to restart it immediately.  
4. **Editor:** Defaults to nano for quick edits (falls back to vi).

### **3\. Safety Protocols**

* **Protected Containers:** Prevents accidental stopping or removal of critical infrastructure.  
  * *Current Protected List:* portainer, traefik, watchtower, diun, docker-proxy.  
* **Destructive Actions:** "Remove Container" and "Prune System" require explicit confirmation.

### **4\. Bulk Operations**

* **Restart All:** Useful after a server update or network change.  
* **Stop All:** Quickly shut down services.  
* **System Prune:** Clean up unused images, networks, and volumes to free up disk space.

### **5\. Host Integration**

* **Resource Monitor:** View live CPU/Memory usage (docker stats).  
* **Disk Usage:** Check free space (df \-h).  
* **Minimize:** Drop to the host shell to run other commands, then type exit to return to the menu.

## **⚡ Quick Install (One-Liner)**

Copy and run this command to download, install, and launch the script in one go:
```bash
wget \-O \~/manage\_docker.sh \[https://raw.githubusercontent.com/davidian-sk/useful-scripts/main/linux/docker\_manager.sh\](https://raw.githubusercontent.com/davidian-sk/useful-scripts/main/linux/docker\_manager.sh) && chmod \+x \~/manage\_docker.sh && \~/manage\_docker.sh
```
## **🛠️ Requirements**

* **OS:** Linux (Debian/Ubuntu/Garuda/Raspberry Pi OS)  
* **Permissions:** User must be in the docker group or have sudo privileges.  
* **Dependencies:**  
  * dialog (for the menu interface)  
  * nano (preferred editor)

## **📦 Manual Installation**

1. Save the script to your home or bin folder:  
```bash
   \# Create the file  
   nano \~/manage\_docker.sh  
   \# (Paste code and save)

   \# Make executable  
   chmod \+x \~/manage\_docker.sh
```
2. Run it:
```bash
   ./manage\_docker.sh
```
## **⚙️ Customization**

* **View Mode:** Toggle between "All Folders" and "Associated Folders" (folders mounted to running containers) inside the Config menu.  
* **Noise Filter:** Toggle the filter ON/OFF to see hidden/system directories in /opt.

*© 2025 \- David Šmidke*
