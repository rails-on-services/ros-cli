locals {
  worker_groups = {
    instance_type         = "m5.xlarge"
    name                  = "eks_workers_a"
    key_name              = "perx-whistler"
    asg_max_size          = 10
    asg_min_size          = 2
    root_volume_size      = 30
    root_volume_type      = "gp2"
    autoscaling_enabled   = true
    protect_from_scale_in = true
    asg_force_delete      = true   # This is to address a case when terraform cannot delete autoscaler group if protect_from_scale_in = true
    enable_monitoring     = false
    kubelet_extra_args    = "--node-labels=beta.kubernetes.io/fluentd-ds-ready=true"
  }
  
}