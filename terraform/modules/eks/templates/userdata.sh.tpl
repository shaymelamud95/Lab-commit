#!/bin/bash
set -o xtrace

# =============================================================================
# EKS Worker Node Bootstrap Script
# Self-Managed EC2 Node - Joins EKS Cluster
# =============================================================================

# Log startup
echo "Starting EKS worker node bootstrap at $(date)"
echo "Cluster: ${cluster_name}"

# Install SSM Agent (for private subnet access without SSH)
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install CloudWatch agent for node-level metrics (Prometheus can scrape this)
yum install -y amazon-cloudwatch-agent

# Pre-pull critical images to speed up pod scheduling
# This is especially important for Prometheus/Grafana which are larger images

# Configure kubelet extra args for monitoring
cat <<EOF > /etc/kubernetes/kubelet/kubelet-config-extra.json
{
  "protectKernelDefaults": true,
  "readOnlyPort": 0,
  "eventRecordQPS": 0,
  "serverTLSBootstrap": true
}
EOF

# Bootstrap the node to join EKS cluster
# Using the official EKS bootstrap script
/etc/eks/bootstrap.sh '${cluster_name}' \
  --apiserver-endpoint '${cluster_endpoint}' \
  --b64-cluster-ca '${cluster_certificate_authority}' \
  ${bootstrap_extra_args} \
  --kubelet-extra-args '${kubelet_extra_args} --node-labels=node.kubernetes.io/lifecycle=normal,node-type=self-managed'

# Log completion
echo "Bootstrap completed at $(date)"
