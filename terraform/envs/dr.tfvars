# Ambiente de DR (Warm Standby / Opção B) - us-west-2
# Mesmo código, outra região, com 1 comando:  .\scripts\dr.ps1
#
# Warm standby = versão reduzida do primário, pronta para crescer:
#  - 1 nó SPOT (até 70% mais barato) que escala para 3 se o DR for ativado;
#  - RDS menor e sem backup próprio (os dados vêm do restore do primário).
region        = "us-west-2"
site          = "dr"
backup_region = "us-west-2"

node_instance_types = ["t3.large", "t3a.large", "m5.large"] # vários tipos = mais chance de Spot
node_capacity_type  = "SPOT"
node_desired_size   = 1
node_min_size       = 1
node_max_size       = 3

db_instance_class        = "db.t3.micro"
db_multi_az              = false
db_backup_retention_days = 1
