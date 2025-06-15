terraform {
  required_version = ">= 1.0"

  backend "s3" {
    bucket = "pnieto-terraform-state-mar"
    key    = "terraform/state"
    region = "eu-west-1"
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "aws_region" "current" {}

# --- 1. Crear el repositorio en ECR ---
# Este recurso define el repositorio donde se almacenará la imagen de Docker.

resource "aws_ecr_repository" "api_repository" {
  name = "my-api-repo"
  force_delete = true
}

resource "aws_iam_role" "ecr_push_role" {
  name = "ecr-push-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecr_push_policy" {
  name = "ecr-push-policy"
  role = aws_iam_role.ecr_push_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ],
        Effect = "Allow",
        Resource = aws_ecr_repository.api_repository.arn
      }
    ]
  })
}

resource "null_resource" "docker_build_and_push" {
  triggers = {
    always_run = "${timestamp()}"
  }    
  provisioner "local-exec" {
    command = <<-EOT
      aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${aws_ecr_repository.api_repository.repository_url}
      
      docker buildx build --platform linux/amd64 -t my-api-repo:latest . --load

      docker tag my-api-repo:latest ${aws_ecr_repository.api_repository.repository_url}:latest
      
      docker push ${aws_ecr_repository.api_repository.repository_url}:latest

    EOT
  }
  depends_on = [aws_ecr_repository.api_repository]
}

data "aws_ecr_image" "my_image" {
  repository_name = aws_ecr_repository.api_repository.name
  image_tag       = "latest"
  depends_on      = [null_resource.docker_build_and_push]
}

resource "null_resource" "trigger_apprunner_deployment" {
  triggers = {
    image_digest = "${data.aws_ecr_image.my_image.image_digest}"
  }
  depends_on = [null_resource.docker_build_and_push]
}

# --- 2. Rol IAM para que App Runner pueda acceder a ECR ---
# App Runner necesita permisos explícitos para extraer imágenes de un repositorio ECR privado.
resource "aws_iam_role" "apprunner_ecr_role" {
  name = "AppRunnerECRAccessRoleForStore"

  # Define quién puede asumir este rol (en este caso, el servicio App Runner)
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
      },
    ]
  })
}

# Adjunta la política gestionada por AWS que otorga los permisos necesarios.
resource "aws_iam_role_policy_attachment" "apprunner_ecr_policy_attachment" {
  role       = aws_iam_role.apprunner_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}


# --- 3. Crear el servicio de App Runner ---
# Este recurso define el servicio que ejecutará nuestro contenedor.
resource "aws_apprunner_service" "tienda_api_service" {
  service_name = "tienda-online-servicio-tf"

  # Configuración de la fuente de la imagen
  source_configuration {
    image_repository {
      image_identifier      = "${aws_ecr_repository.api_repository.repository_url}:latest"
      image_repository_type = "ECR"
      image_configuration {
        port = "8080" # El puerto expuesto en nuestro Dockerfile
      }
    }
    # Proporciona el rol IAM que creamos para dar permisos de acceso a ECR.
    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_ecr_role.arn
    }
    # Deshabilitamos el despliegue automático para este ejemplo
    auto_deployments_enabled = false
  }

  # Etiqueta para identificar recursos creados por Terraform
  tags = {
    ManagedBy = "Terraform"
  }
}


# --- 4. Outputs ---
# Estos outputs nos darán las URLs y nombres que necesitamos,
# para no tener que buscarlos en la consola de AWS.
output "ecr_repository_url" {
  description = "URL del repositorio de ECR para hacer push de la imagen Docker."
  value       = aws_ecr_repository.api_repository.repository_url
}

output "app_runner_service_url" {
  description = "URL pública del servicio de App Runner para usar en el frontend."
  value       = aws_apprunner_service.tienda_api_service.service_url
}


# --- Variables para la Base de Datos ---
variable "db_username" {
  description = "El nombre de usuario para la base de datos RDS."
  type        = string
  default     = "mar"
}

variable "db_password" {
  description = "La contraseña para la base de datos RDS."
  type        = string
  sensitive   = true
  default     = "edemedem" # Cambia esto por una contraseña segura.
}

# --- 1. Crear la VPC (Virtual Private Cloud) ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
  }
}

# --- 2. Crear la Subnet Pública ---
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-central-1a"

  tags = {
    Name = "public-subnet-1"
  }
}

# --- 3. Crear las Subnets Privadas ---
# Subnet privada en la AZ 'eu-central-1b'
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1b"

  tags = {
    Name = "private-subnet-1"
  }
}

# ¡NUEVO! Segunda subnet privada en la AZ 'eu-central-1c' para cumplir el requisito de RDS.
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-central-1c"

  tags = {
    Name = "private-subnet-2"
  }
}

# --- 4. Crear una Gateway de Internet (IGW) y Asociarla ---
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

# --- 5. Crear una Tabla de Rutas para la Subnet Pública ---
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }
  tags = {
    Name = "public-route-table"
  }
}

# --- 6. Asociar la Tabla de Rutas con la Subnet Pública ---
resource "aws_route_table_association" "public_subnet_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# --- 7. Crear un Grupo de Seguridad para RDS ---
resource "aws_security_group" "rds_sg" {
  name = "rds-security-group"
  # ¡CORREGIDO! Descripción sin tildes.
  description = "Permite el trafico a la instancia RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

# --- 8. Crear un Grupo de Subnets para RDS ---
resource "aws_db_subnet_group" "rds_subnet_group" {
  name = "main-rds-subnet-group"
  # ¡CORREGIDO! Añadimos las dos subnets privadas.
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name = "Main RDS Subnet Group"
  }
}

# --- 9. Crear la Instancia de RDS en la Subnet Privada ---
resource "aws_db_instance" "main_rds" {
  identifier           = "main-db-instance"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  engine               = "postgres"
  engine_version       = "17.5"
  db_name              = "mydatabase"
  username             = var.db_username
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true

  tags = {
    Name = "main-rds-instance"
  }
}

# --- Outputs ---
output "vpc_id" {
  description = "El ID de la VPC creada."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "El ID de la subnet pública."
  value       = aws_subnet.public_subnet.id
}

output "private_subnet_ids" {
  description = "Los IDs de las subnets privadas."
  value       = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
}

output "rds_instance_endpoint" {
  description = "El endpoint de la instancia de RDS para conectarse."
  value       = aws_db_instance.main_rds.endpoint
}
