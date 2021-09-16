data "google_compute_image" "gci_image" {
  family  = "debian-10"
  project = "debian-cloud"
}

resource "google_storage_bucket" "forest" {
  force_destroy = true
  name = format("forest-%s", lower(var.login_token)) # Could also use account ID?
  versioning {
    enabled = true
  }
  location = upper(var.region)
  lifecycle {
    prevent_destroy = false
  }
}

locals {
  server_ip = split("/", var.ssh_source_cidr).0
}

resource "google_storage_bucket_object" "save" {
  name   = "Slot2-20210915T124805Z-001.zip"
  source = "saves/Slot2-20210915T124805Z-001.zip"
  bucket = google_storage_bucket.forest.name
}

resource "google_storage_bucket_object" "compose" {
  name   = "docker-compose.yml"
  source = "objects/docker-compose.yml"
  bucket = google_storage_bucket.forest.name
}

resource "google_compute_instance" "forest" {
  name         = "forest"
  machine_type = "e2-standard-4"
  zone         = format("%s-a", var.region)
  boot_disk {
    initialize_params {
      image = data.google_compute_image.gci_image.self_link
    }
  }

  allow_stopping_for_update = true

  service_account {
    scopes = ["storage-rw"] # TODO refine further
  }

  network_interface {
    network = "default"

    access_config {
      network_tier = "STANDARD"
    }
  }

  metadata_startup_script = <<EOT
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
  sudo apt -y install unzip zip git lsof p7zip
  sudo usermod -aG docker root
  sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
  cd /root
  git clone https://github.com/jammsen/docker-the-forest-dedicated-server.git
  cd docker-the-forest-dedicated-server
  mkdir -p srv/tfds/steamcmd
  mkdir -p srv/tfds/game/saves
  cd srv/tfds/game/saves/
  gsutil cp gs://${google_storage_bucket.forest.name}/${google_storage_bucket_object.save.output_name} .
  7z x ${google_storage_bucket_object.save.output_name}
  cd cd /root/docker-the-forest-dedicated-server
  sed -i 's/jammsen-docker-generated/${var.server_name}/g' server.cfg.example
  sed -i 's/serverPassword/serverPassword ${var.server_password}/g' server.cfg.example
  sed -i 's/serverPasswordAdmin/serverPasswordAdmin ${var.server_admin_password}/g' server.cfg.example
  sed -i 's/serverSteamAccount/serverSteamAccount ${var.login_token}/g' server.cfg.example
  gsutil cp gs://${google_storage_bucket.forest.name}/${google_storage_bucket_object.compose.output_name} .
  chmod -R u+rwx ../docker-the-forest-dedicated-server
  docker-compose up -d
EOT
  #  docker-compose up -d && docker-compose down
  #  cp server.cfg.example srv/tfds/game/config/config.cfg
  # Apply the firewall rule to allow external IPs to access this instance
  #   sed -i 's/0\.0\.0\.0/${local.server_ip}/g' server.cfg.example\
  tags = ["forest-server"]
}


locals {
  ports = [
      "8766",
      "27015",
      "27016"
    ]
}

resource "google_compute_firewall" "forest" {
  name    = "default-forest"
  network = "default"

  allow {
    protocol = "udp"
    ports    = local.ports
  }

  allow {
    protocol = "tcp"
    ports = local.ports
  }

  # Allow traffic from everywhere to instances with an forest-server tag to forest ports
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["forest-server"]
}

resource "google_compute_firewall" "ssh" {
  name    = "default-forest-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Allow traffic from specified range to instances with an forest-server tag to ssh
  source_ranges = [var.ssh_source_cidr]
  target_tags   = ["forest-server"]
}

# so I can use my domain in route53. default false
data "aws_route53_zone" "my_hosted_zone" {
  count        = var.use_route53 ? 1 : 0
  name         = var.hosted_zone_name
  private_zone = false
}

resource "aws_route53_record" "forest" {
  count           = var.use_route53 ? 1 : 0
  zone_id         = data.aws_route53_zone.my_hosted_zone.0.id
  name            = format("forest.%s", data.aws_route53_zone.my_hosted_zone.0.name)
  type            = "A"
  ttl             = 60
  records         = [google_compute_instance.forest.network_interface.0.access_config.0.nat_ip]
  allow_overwrite = true
}

output "instance_public_ip" {
  value = google_compute_instance.forest.network_interface.0.access_config.0.nat_ip
}