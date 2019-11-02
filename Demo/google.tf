variable "rancher_version" {
  default     = "latest"
  description = "Rancher Server Version"
}

variable "count_agent_all_nodes" {
  default     = "2"
  description = "Number of Agent All Designation Nodes"
}

variable "count_agent_etcd_nodes" {
  default     = "0"
  description = "Number of ETCD Nodes"
}

variable "count_agent_controlplane_nodes" {
  default     = "0"
  description = "Number of K8s Control Plane Nodes"
}

variable "count_agent_worker_nodes" {
  default     = "0"
  description = "Number of Worker Nodes"
}

variable "admin_password" {
  default     = "admin"
  description = "Password to set for the admin account in Rancher"
}

variable "cluster_name" {
  default     = "quickstart"
  description = "Kubernetes Cluster Name"
}

variable "docker_version_server" {
  default     = "17.03"
  description = "Docker Version to run on Rancher Server"
}

variable "docker_version_agent" {
  default     = "17.03"
  description = "Docker Version to run on Kubernetes Nodes"
}

variable "gce_ssh_user" {
  default = "yahyaozturk"
  description = "ssh username"
}
variable "gce_ssh_pub_key_file" {
  default = "googlecloud.pub"
  description = "sshkey public key"
}
variable "gce_ssh_private_key_file" {
  default = "googlecloud"
  description = "sshkey private key"
}
variable "gce_project" {
  default = "data-oasis-217410"
  description = "Google Cloud Project Name"
}
variable "gce_zone" {
  default = "europe-west1-b"
  description = "Google Cloud Zone Name"
}
variable "gce_machinetype" {
  default = "n1-standard-1"
  description = "Google Cloud machine type"
}
variable "credentials" {
  default = "ContinuousIntegration.json"
  description = "Google Cloud Credentials"
}

provider "google" {
  project      = "${var.gce_project}"
  zone         = "${var.gce_zone}"
  credentials = "${file(var.credentials)}"
}

resource "google_compute_instance" "server" {
  count        = 1
  name         = "rancher-server-${count.index+1}"
  machine_type = "${var.gce_machinetype}"

  tags = ["http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = "docker-host"
      size  = 30
    }
  }

scheduling{
  automatic_restart = true
}

  network_interface {
    network = "default"
    access_config {
      // Ephemeral IP
    }
  }

  metadata {
    sshKeys = "${var.gce_ssh_user}:${file(var.gce_ssh_pub_key_file)}"
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "${var.gce_ssh_user}"
      private_key = "${file(var.gce_ssh_private_key_file)}"
    }
    inline = ["${data.template_file.userdata_server.rendered}"]
  }
}

resource "google_compute_instance" "rancheragent-all" {
  count        = "${var.count_agent_all_nodes}"
  name         = "rancher-worker-${count.index+1}-all"
  machine_type = "${var.gce_machinetype}"
  depends_on = ["google_compute_instance.server"]

  tags = ["http-server", "https-server"]

  boot_disk {
    initialize_params {
      image = "docker-host"
      size  = 30
    }
  }

scheduling{
  automatic_restart = true
}

  network_interface {
    network = "default"
    access_config {
      // Ephemeral IP
    }
  }

  metadata {
    sshKeys = "${var.gce_ssh_user}:${file(var.gce_ssh_pub_key_file)}"
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "${var.gce_ssh_user}"
      private_key = "${file(var.gce_ssh_private_key_file)}"
    }
    inline = ["${data.template_file.userdata_agent.rendered}"]
  }
}
  data "template_file" "userdata_server" {
    template = "${file("script/userdata_server")}"

    vars {
      admin_password        = "${var.admin_password}"
      cluster_name          = "${var.cluster_name}"
      docker_version_server = "${var.docker_version_server}"
      rancher_version       = "${var.rancher_version}"
    }
  }

  data "template_file" "userdata_agent" {
  template = "${file("script/userdata_agent")}"

  vars {
    admin_password       = "${var.admin_password}"
    cluster_name         = "${var.cluster_name}"
    docker_version_agent = "${var.docker_version_agent}"
    rancher_version      = "${var.rancher_version}"
    server_address       = "${google_compute_instance.server.network_interface.0.access_config.0.nat_ip}"
  }
}