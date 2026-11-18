<#
.SYNOPSIS
  DR (Opção A): demonstra o backup do cluster com o Velero e a restauração.

.DESCRIPTION
  1. Lista os backups agendados (a cada 15 min) no bucket S3 de us-west-2.
  2. Faz um backup manual do namespace solidarytech agora.
  3. Restaura esse backup num namespace NOVO (solidarytech-restore), sem mexer na
     produção nem brigar com o Argo CD - prova que o backup é restaurável.
  4. -Limpar remove o namespace de teste.

.EXAMPLE
  .\scripts\velero-demo.ps1
  .\scripts\velero-demo.ps1 -Limpar
#>
param([switch]$Limpar)
. (Join-Path $PSScriptRoot "_comum.ps1")
function Velero { kubectl exec -n velero deploy/velero -c velero -- /velero @args }

if ($Limpar) {
    kubectl delete namespace solidarytech-restore --ignore-not-found
    exit 0
}

Passo "Local de backup (bucket na outra região)"
Velero backup-location get

Passo "Agendamentos"
Velero schedule get

$nome = "demo-" + (Get-Date -Format "yyyyMMdd-HHmmss")
Passo "Backup manual agora: $nome"
Velero backup create $nome --include-namespaces solidarytech --wait
Velero backup describe $nome

Passo "Backups existentes"
Velero backup get

Passo "Restore em namespace novo (solidarytech-restore)"
Velero restore create "restore-$nome" --from-backup $nome --namespace-mappings solidarytech:solidarytech-restore --wait
Velero restore describe "restore-$nome"

Passo "Recursos restaurados"
kubectl get deploy,svc,configmap,secret,hpa -n solidarytech-restore
Write-Host "`nPara limpar: .\scripts\velero-demo.ps1 -Limpar" -ForegroundColor Yellow
exit 0
