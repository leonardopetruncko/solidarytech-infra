<#
.SYNOPSIS
  DR (Opção B - Warm Standby): levanta o ambiente "espelho" em us-west-2 com 1 comando.

.DESCRIPTION
  Mesmo código Terraform do primário, outro workspace (dr) e outro tfvars (envs/dr.tfvars):
    1. Descobre o backup replicado do RDS primário em us-west-2 (se existir) e sobe o
       banco de DR já com os dados (restore point-in-time = RPO de minutos).
    2. Sobe rede, EKS (Spot), DynamoDB, SQS, Argo CD e Velero (bucket só leitura).
    3. Restaura com o Velero o último backup do primário (Secrets e recursos do cluster).
    4. Recria os Secrets apontando para o banco de DR e liga o GitOps (mesmo repo).

.EXAMPLE
  .\scripts\dr.ps1             # ativa o DR
  .\scripts\dr.ps1 -Destruir   # desliga o DR
  .\scripts\dr.ps1 -Plano      # só mostra o que seria criado em us-west-2 (sem custo)
#>
param([switch]$Destruir, [switch]$Plano, [string]$EnvFile = (Join-Path $PSScriptRoot "fase5.env"))
. (Join-Path $PSScriptRoot "_comum.ps1")
$inicio = Get-Date

$cfg = Ler-Env $EnvFile
$env:TF_VAR_db_password = $cfg["DB_PASSWORD"]
$conta = Conta-Aws
Terraform-Init $conta
terraform "-chdir=$TfDir" workspace select -or-create dr | Out-Null
Ok "workspace dr (state separado do primário)"

if ($Plano) {
    Passo "terraform plan do DR em us-west-2 (nada é criado)"
    terraform "-chdir=$TfDir" plan -input=false "-var-file=envs/dr.tfvars" "-var=install_addons=false"
    terraform "-chdir=$TfDir" workspace select default | Out-Null
    exit 0
}

if ($Destruir) {
    terraform "-chdir=$TfDir" destroy -auto-approve -input=false "-var-file=envs/dr.tfvars" "-var=install_addons=true"
    terraform "-chdir=$TfDir" workspace select default | Out-Null
    exit $LASTEXITCODE
}

Passo "Procurando o backup replicado do RDS primário em us-west-2"
$arn = aws rds describe-db-instance-automated-backups --region us-west-2 --query "DBInstanceAutomatedBackups[?DBInstanceIdentifier=='solidarytech-postgres'].DBInstanceAutomatedBackupsArn | [0]" --output text 2>$null
if ($LASTEXITCODE -eq 0 -and $arn -and $arn -ne "None") {
    Ok "backup encontrado: o banco de DR sobe com os dados do primário"
    $env:TF_VAR_rds_restore_from_backup_arn = $arn.Trim()
}
else {
    Aviso "sem backup replicado: o banco de DR sobe vazio (os dados viriam do snapshot mais recente)"
    $env:TF_VAR_rds_restore_from_backup_arn = ""
}

Passo "Terraform DR - fase 1 (infra)"
terraform "-chdir=$TfDir" apply -auto-approve -input=false "-var-file=envs/dr.tfvars" "-var=install_addons=false"
if ($LASTEXITCODE -ne 0) { Falhar "apply do DR (fase 1) falhou" }
Passo "Terraform DR - fase 2 (Argo CD + Velero)"
terraform "-chdir=$TfDir" apply -auto-approve -input=false "-var-file=envs/dr.tfvars" "-var=install_addons=true"
if ($LASTEXITCODE -ne 0) { Falhar "apply do DR (fase 2) falhou" }

$tf = Ler-Outputs
aws eks update-kubeconfig --name $tf.eks_cluster_name.value --region $tf.region.value --alias solidarytech-dr | Out-Null
kubectl get nodes

Passo "Velero: restaurando o último backup do primário"
Start-Sleep -Seconds 60   # o Velero sincroniza a lista de backups do bucket
$ultimo = kubectl get backups.velero.io -n velero --sort-by=.metadata.creationTimestamp -o "jsonpath={.items[-1:].metadata.name}" 2>$null
if ($ultimo) {
    kubectl exec -n velero deploy/velero -c velero -- /velero restore create "dr-$ultimo" --from-backup $ultimo --wait
    Ok "restaurado: $ultimo"
}
else { Aviso "nenhum backup do primário encontrado no bucket" }

Passo "Secrets apontando para o banco de DR + GitOps"
$grafanaPass = Criar-Secrets $tf $cfg
kubectl apply -f (Join-Path $GitopsDir "argocd\project\solidarytech-project.yaml")
kubectl apply -f (Join-Path $GitopsDir "argocd\root-app.yaml")

$min = [int]((Get-Date) - $inicio).TotalMinutes
Write-Host "`n=========== DR ATIVO em us-west-2 em $min min (RTO medido) ===========" -ForegroundColor Green
Write-Host "kubectl config use-context solidarytech-dr | Grafana: admin / $grafanaPass"
exit 0
