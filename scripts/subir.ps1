<#
.SYNOPSIS
  Sobe o ambiente PRIMÁRIO da SolidaryTech (us-east-1) do zero, com 1 comando.

.DESCRIPTION
  1. Confere a credencial do AWS Academy e cria o bucket do state (1ª vez na conta).
  2. terraform apply em 2 fases: infraestrutura -> add-ons (Argo CD + Velero).
  3. kubeconfig + Secrets (senhas e chaves fora do Git).
  4. Aplica o App-of-Apps: daqui em diante o Argo CD sobe todo o resto (GitOps).

.EXAMPLE
  .\scripts\subir.ps1
#>
param([string]$EnvFile = (Join-Path $PSScriptRoot "fase5.env"))
. (Join-Path $PSScriptRoot "_comum.ps1")
$inicio = Get-Date

Passo "Credenciais e configuração"
$cfg = Ler-Env $EnvFile
if ([string]::IsNullOrEmpty($cfg["DB_PASSWORD"])) { Falhar "DB_PASSWORD vazio no fase5.env" }
$env:TF_VAR_db_password = $cfg["DB_PASSWORD"]
$conta = Conta-Aws
Ok "conta AWS $conta"

Terraform-Init $conta
terraform "-chdir=$TfDir" workspace select default | Out-Null

Passo "Terraform - fase 1: rede, EKS, RDS, DynamoDB, SQS, ECR, bucket de backup (~15 min)"
terraform "-chdir=$TfDir" apply -auto-approve -input=false "-var-file=envs/primary.tfvars" "-var=install_addons=false"
if ($LASTEXITCODE -ne 0) { Falhar "terraform apply (fase 1) falhou" }

Passo "Terraform - fase 2: Argo CD + Velero"
terraform "-chdir=$TfDir" apply -auto-approve -input=false "-var-file=envs/primary.tfvars" "-var=install_addons=true"
if ($LASTEXITCODE -ne 0) { Falhar "terraform apply (fase 2) falhou" }

$tf = Ler-Outputs
Passo "kubeconfig"
aws eks update-kubeconfig --name $tf.eks_cluster_name.value --region $tf.region.value --alias solidarytech | Out-Null
kubectl get nodes
if ($LASTEXITCODE -ne 0) { Falhar "sem acesso ao cluster" }

Passo "Secrets (fora do Git)"
$grafanaPass = Criar-Secrets $tf $cfg

Passo "GitOps: App-of-Apps"
kubectl apply -f (Join-Path $GitopsDir "argocd\project\solidarytech-project.yaml")
kubectl apply -f (Join-Path $GitopsDir "argocd\root-app.yaml")
if ($LASTEXITCODE -ne 0) { Falhar "não consegui aplicar o root-app" }

$min = [int]((Get-Date) - $inicio).TotalMinutes
Write-Host "`n==================== PRONTO em $min min ====================" -ForegroundColor Green
Write-Host "Registry ECR : $($tf.ecr_registry.value)"
Write-Host "Grafana      : admin / $grafanaPass   (kubectl port-forward svc/kube-prometheus-stack-grafana -n observability 3000:80)"
Write-Host "Argo CD      : admin / $(Ler-Secret 'argocd' 'argocd-initial-admin-secret' 'password')   (kubectl port-forward svc/argocd-server -n argocd 8080:80)"
Write-Host "`nPróximos passos:"
Write-Host "  1. Atualize os secrets AWS_* do repo solidarytech-app (credenciais do Lab) e rode os 3 pipelines."
Write-Host "  2. Acompanhe: kubectl get applications -n argocd ; kubectl get pods -n solidarytech"
exit 0
