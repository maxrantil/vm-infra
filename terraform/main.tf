# ABOUTME: Terraform configuration for libvirt/KVM Ubuntu VMs

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

variable "dotfiles_local_path" {
  description = "Local path to dotfiles for testing (optional)"
  type        = string
  default     = ""

  validation {
    condition     = var.dotfiles_local_path == "" || can(regex("^/", var.dotfiles_local_path))
    error_message = "dotfiles_local_path must be empty or an absolute path (starting with /)"
  }
}

# VM disk (based on external permanent base image)
# Base image: /var/lib/libvirt/images/ubuntu-24.04-base.qcow2
# Download once with: curl -L https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img -o /var/lib/libvirt/images/ubuntu-24.04-base.qcow2
resource "libvirt_volume" "vm_disk" {
  name             = "${var.vm_name}.qcow2"
  base_volume_pool = "default"
  base_volume_name = "ubuntu-22.04-base.qcow2"
  pool             = "default"
  size             = var.disk_size
}

# Read SSH public key
locals {
  ssh_key = var.ssh_public_key != "" ? var.ssh_public_key : file(pathexpand(var.ssh_public_key_file))
}

# ═══════════════════════════════════════════════════════════════════════════
# WORKAROUND: Manual Cloud-Init ISO Creation
# ═══════════════════════════════════════════════════════════════════════════
#
# Issue: libvirt provider race condition with cloudinit_disk resources
# GitHub: https://github.com/dmacvicar/terraform-provider-libvirt/issues/973
# Affects: Provider versions 0.7.x - 0.8.3 (current)
#
# Problem: libvirt_cloudinit_disk creates volumes with random UUID suffixes
# (e.g., /path/to/file.iso;random-uuid) that fail lookup when the domain
# tries to attach them before upload completes. This is a race condition.
#
# Workaround: Create cloud-init ISO manually using genisoimage, then reference
# it as a regular libvirt_volume. This bypasses the provider's broken
# cloudinit_disk resource entirely.
#
# Migration Path: When provider > 0.8.3 fixes the race condition, replace
# this workaround with native libvirt_cloudinit_disk resource.
#
# ═══════════════════════════════════════════════════════════════════════════

# Step 1: Execute bash script to generate cloud-init ISO
resource "null_resource" "cloudinit_iso" {
  provisioner "local-exec" {
    command = "sudo ${path.module}/create-cloudinit-iso.sh '${var.vm_name}' '${local.ssh_key}'"
  }

  # Recreate ISO if VM name or SSH key changes
  triggers = {
    vm_name = var.vm_name
    ssh_key = local.ssh_key
  }
}

# Step 2: Reference the manually created ISO as a libvirt volume
resource "libvirt_volume" "cloudinit" {
  name   = "${var.vm_name}-cloudinit.iso"
  pool   = "default"
  source = "/var/lib/libvirt/images/${var.vm_name}-cloudinit.iso"

  depends_on = [null_resource.cloudinit_iso]
}

# Define the VM
resource "libvirt_domain" "vm" {
  name   = var.vm_name
  memory = var.memory
  vcpu   = var.vcpus

  # NOTE: cloudinit attribute removed due to provider bug (see workaround above)
  # Native approach would be: cloudinit = libvirt_cloudinit_disk.commoninit.id
  # Using explicit disk attachment instead as part of the workaround

  network_interface {
    network_name = "default"
  }

  # Main OS disk
  disk {
    volume_id = libvirt_volume.vm_disk.id
  }

  # Cloud-init ISO attached as secondary disk (explicit attachment for workaround)
  disk {
    volume_id = libvirt_volume.cloudinit.id
    scsi      = false
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
    vm_ip               = length(libvirt_domain.vm.network_interface[0].addresses) > 0 ? libvirt_domain.vm.network_interface[0].addresses[0] : ""
    vm_user             = "mr"
    dotfiles_local_path = var.dotfiles_local_path
  })
  filename = "${path.module}/../ansible/inventory.ini"
}
