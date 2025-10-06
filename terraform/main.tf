terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Variables
variable "vm_name" {
  description = "Name of the VM"
  type        = string
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 4096
}

variable "vcpus" {
  description = "Number of vCPUs"
  type        = number
  default     = 2
}

variable "disk_size" {
  description = "Disk size in bytes"
  type        = number
  default     = 21474836480 # 20GB
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  default     = ""
}

variable "ssh_public_key_file" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/vm_key.pub"
}

# Ubuntu cloud image
resource "libvirt_volume" "ubuntu_base" {
  name   = "${var.vm_name}-base.qcow2"
  pool   = "default"
  source = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  format = "qcow2"
}

# VM disk (based on cloud image)
resource "libvirt_volume" "vm_disk" {
  name           = "${var.vm_name}.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  pool           = "default"
  size           = var.disk_size
}

# Read SSH public key
locals {
  ssh_key = var.ssh_public_key != "" ? var.ssh_public_key : file(pathexpand(var.ssh_public_key_file))
}

# Cloud-init disk
resource "libvirt_cloudinit_disk" "commoninit" {
  name = "${var.vm_name}-cloudinit.iso"
  user_data = templatefile("../cloud-init/user-data.yaml", {
    ssh_public_key = local.ssh_key
  })
  pool = "default"
}

# Define the VM
resource "libvirt_domain" "vm" {
  name   = var.vm_name
  memory = var.memory
  vcpu   = var.vcpus

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  network_interface {
    network_name = "default"
  }

  disk {
    volume_id = libvirt_volume.vm_disk.id
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }
}

# Output the VM's IP
output "vm_ip" {
  value = length(libvirt_domain.vm.network_interface[0].addresses) > 0 ? libvirt_domain.vm.network_interface[0].addresses[0] : "pending"
}

# Generate Ansible inventory file
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    vm_ip   = length(libvirt_domain.vm.network_interface[0].addresses) > 0 ? libvirt_domain.vm.network_interface[0].addresses[0] : ""
    vm_user = "mr"
  })
  filename = "${path.module}/../ansible/inventory.ini"
}
