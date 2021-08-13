data "google_compute_image" "ubuntu2004" {
  family  = "ubuntu-2004-lts"
  project = "ubuntu-os-cloud"
}

resource "google_storage_bucket" "forest" {
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

resource "google_storage_bucket_object" "config" {
  name   = "server.cfg"
  source = <<EOF
// Dedicated Server Settings.
// Server IP address - Note: If you have a router, this address is the internal address, and you need to configure ports forwarding
serverIP ${local.server_ip}
// Steam Communication Port - Note: If you have a router you will need to open this port.
serverSteamPort 8766
// Game Communication Port - Note: If you have a router you will need to open this port.
serverGamePort 27015
// Query Communication Port - Note: If you have a router you will need to open this port.
serverQueryPort 27016
// Server display name
serverName ${var.server_name}
// Maximum number of players
serverPlayers 6
// Enable VAC (Valve Anti-cheat System at the server. Must be set off or on
enableVAC off
// Server password. blank means no password
serverPassword ${var.server_password}
// Server administration password. blank means no password
serverPasswordAdmin ${var.server_admin_password}
// Your Steam account name. blank means anonymous
serverSteamAccount ${var.login_token}
// Time between server auto saves in minutes - The minumum time is 15 minutes, the default time is 30
serverAutoSaveInterval 30
// Game difficulty mode. Must be set to Peaceful Normal or Hard
difficulty Hard
// New or continue a game. Must be set to New or Continue
initType Continue
// Slot to save the game. Must be set 1 2 3 4 or 5
slot 1
// Show event log. Must be set off or on
showLogs off
// Contact email for server admin
serverContact email@gmail.com
// No enemies
veganMode off
// No enemies during day time
vegetarianMode off
// Reset all structure holes when loading a save
resetHolesMode off
// Regrow 10% of cut down trees when sleeping
treeRegrowMode off
// Allow building destruction
allowBuildingDestruction on
// Allow enemies in creative games
allowEnemiesCreativeMode off
// Allow clients to use the built in debug console
allowCheats off
// Use full weapon damage values when attacking other players
realisticPlayerDamage off
// Allows defining a custom folder for save slots, leave empty to use the default location
saveFolderPath
// Target FPS when no client is connected
targetFpsIdle 0
// Target FPS when there is at least one client connected
targetFpsActive 0
EOF
  bucket = google_storage_bucket.forest.name
}

resource "google_compute_instance" "forest" {
  depends_on = [
    google_storage_bucket_object.config
  ]
  name         = "forest"
  machine_type = "e2-medium" # 2 vCPUs, 4G RAM
  zone         = format("%s-a", var.region)
  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu2004.self_link
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
  sudo apt -y install docker-compose unzip zip
  git clone https://github.com/jammsen/docker-the-forest-dedicated-server.git
  cd docker-the-forest-dedicated-server
  mkdir -p srv/tfds/steamcmd:/steamcmd
  mkdir -p srv/tfds/game
  gsutil cp gs://${google_storage_bucket.foest.name}/${google_storage_bucket_object.config.output_name} .
  sed -i 's/\/srv/srv/g' docker-compose.yml
  chown -R ubuntu:ubuntu ../docker-the-forest-dedicated-server
  docker-compose up -d
  EOT

  # Apply the firewall rule to allow external IPs to access this instance
  tags = ["forest-server"]
}

locals {
  ports = toset(
    [
      "8766",
      "27015",
      "27016"
    ]
  )
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