# Ambiente PRIMÁRIO (produção ativa) - us-east-1
# terraform workspace select default
# terraform apply -var-file=envs/primary.tfvars -var db_password=...
region        = "us-east-1"
site          = "primary"
backup_region = "us-west-2"

node_instance_types = ["t3.large"]
node_capacity_type  = "ON_DEMAND"
node_desired_size   = 2
node_min_size       = 2
node_max_size       = 3

db_instance_class        = "db.t3.micro"
db_multi_az              = false
db_backup_retention_days = 7

# DR dos dados: replica os backups do RDS para us-west-2 (desligue se o Lab negar a permissão).
rds_cross_region_backup = true
