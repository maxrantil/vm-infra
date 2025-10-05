[vms]
%{ if vm_ip != "" ~}
${vm_ip} ansible_user=${vm_user} ansible_ssh_private_key_file=~/.ssh/vm_key ansible_ssh_common_args='-o StrictHostKeyChecking=no'
%{ endif ~}
