# =============================================================================
# RDS MySQL/PostgreSQL for Backend Application
# =============================================================================
# Private RDS instance in VPC private subnets
# No public accessibility (exam requirement)
# =============================================================================

# DB Subnet Group (uses private subnets)
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Database subnet group for ${var.project_name}"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS database"
  vpc_id      = var.vpc_id

  # Allow MySQL/PostgreSQL from worker nodes and Windows EC2
  ingress {
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
    description     = "Allow database access from EKS workers and Windows EC2"
  }

  # No egress needed for RDS

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# Random password for database
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.project_name}-db-password"
  description             = "RDS database password for ${var.project_name}"
  recovery_window_in_days = 0 # Immediate deletion for dev environment

  tags = {
    Name = "${var.project_name}-db-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = var.db_engine
    host     = aws_db_instance.main.endpoint
    port     = var.db_port
    dbname   = var.db_name
  })
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-db"

  # Engine configuration
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # Storage
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # CRITICAL: No public access
  port                   = var.db_port

  # Backup & Maintenance
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"
  skip_final_snapshot     = true # Dev environment
  deletion_protection     = false

  # Performance Insights
  performance_insights_enabled = false

  # Parameter group (default)
  parameter_group_name = null

  tags = {
    Name = "${var.project_name}-db"
  }
}
