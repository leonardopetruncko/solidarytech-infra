<#
.SYNOPSIS
  Destrói o ambiente da SolidaryTech (primário e, com -DR, também o warm standby).

.EXAMPLE
  .\scripts\destruir.ps1          # só o primário
  .\scripts\destruir.ps1 -DR      # DR (us-west-2) e depois o primário
#>
param([switch]$DR, [string]$EnvFile = (Join-Path $PSScriptRoot "fase5.env"))
. (Join-Path $PSScriptRoot "_comum.ps1")

$cfg = Ler-Env $EnvFile
$env:TF_VAR_db_password = $cfg["DB_PASSWORD"]
$conta = Conta-Aws
Terraform-Init $conta

if ($DR) {
    Passo "Destruindo o DR (us-west-2)"
    terraform "-chdir=$TfDir" workspace select dr
    if ($LASTEXITCODE -eq 0) {
        terraform "-chdir=$TfDir" destroy -auto-approve -input=false "-var-file=envs/dr.tfvars" "-var=install_addons=true"
        terraform "-chdir=$TfDir" workspace select default | Out-Null
    }
}

Passo "Destruindo o primário (us-east-1)"
terraform "-chdir=$TfDir" workspace select default | Out-Null
terraform "-chdir=$TfDir" destroy -auto-approve -input=false "-var-file=envs/primary.tfvars" "-var=install_addons=true"
if ($LASTEXITCODE -ne 0) { Falhar "destroy falhou: rode de novo (recursos em remoção às vezes precisam de 2 passadas)" }
Write-Host "`nAmbiente destruído." -ForegroundColor Green
exit 0
