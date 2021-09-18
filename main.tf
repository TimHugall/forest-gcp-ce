data "google_compute_image" "ubuntu2004" {
  family  = "ubuntu-2004-lts"
  project = "ubuntu-os-cloud"
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
resource "google_storage_bucket_object" "config" {
  name   = "server.cfg.example"
  source = "objects/server.cfg.example"
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
  sh get-docker.sh
  apt -y install unzip zip git lsof p7zip-full
  usermod -aG docker ubuntu
  curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
  mkdir -p /srv/tfds/steamcmd
  mkdir -p /srv/tfds/game/savesMultiplayer
  mkdir /srv/tfds/game/config
  gsutil cp gs://${google_storage_bucket.forest.name}/${google_storage_bucket_object.config.output_name} /srv/tfds/game/config/config.cfg
  sudo chattr +i /srv/tfds/game/config/config.cfg
  chmod -R u+rwx /srv
  su - ubuntu
  cd /home/ubuntu
  git clone https://github.com/jammsen/docker-the-forest-dedicated-server.git
  cd docker-the-forest-dedicated-server
  gsutil cp gs://${google_storage_bucket.forest.name}/${google_storage_bucket_object.compose.output_name} docker-compose.yml
  gsutil cp gs://${google_storage_bucket.forest.name}/${google_storage_bucket_object.save.output_name} /srv/tfds/game/savesMultiplayer/Slot.zip
  cd /srv/tfds/game/savesMultiplayer
  sudo 7z x Slot.zip
  sudo rm -r Slot.zip
  cd /home/ubuntu/docker-the-forest-dedicated-server
  docker-compose up -d
EOT
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