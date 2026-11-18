<#
.SYNOPSIS
  DR (Opção A): prova que o backup do Velero (bucket em us-west-2) restaura o cluster.

.DESCRIPTION
  Os manifestos já são recuperáveis pelo Git (Argo CD). O que o Git NÃO tem são os
  Secrets (senhas do banco, token de admin) e o estado criado em runtime. É isso que o
  Velero protege, e é isso que a demo prova:
    1. Mostra o bucket de backup (outra região) e os backups agendados a cada 15 min.
    2. Faz um backup manual agora.
    3. "Desastre": apaga o Secret do donation-service (senha do banco + fila).
    4. Restaura só os Secrets do namespace a partir do backup e confere que voltou igual.

.EXAMPLE
  .\scripts\velero-demo.ps1
#>
. (Join-Path $PSScriptRoot "_comum.ps1")
function Velero { kubectl exec -n velero deploy/velero -c velero -- /velero @args }
$ns = "solidarytech"; $secret = "donation-service-secret"

Passo "Local de backup (bucket S3 em us-west-2, fora da região primária)"
Velero backup-location get

Passo "Backups agendados (a cada 15 min) e existentes"
Velero schedule get
Velero backup get

$nome = "demo-" + (Get-Date -Format "yyyyMMdd-HHmmss")
Passo "Backup manual agora: $nome"
Velero backup create $nome --include-namespaces $ns --wait
$antes = kubectl get secret $secret -n $ns -o "jsonpath={.data.DATABASE_URL}"

Passo "DESASTRE simulado: apagando o Secret $secret (não existe no Git)"
kubectl delete secret $secret -n $ns
kubectl get secret $secret -n $ns 2>&1 | Out-Host

Passo "Restore dos Secrets a partir do backup"
Velero restore create "restore-$nome" --from-backup $nome --include-resources secrets --include-namespaces $ns --wait
kubectl get secret $secret -n $ns
$depois = kubectl get secret $secret -n $ns -o "jsonpath={.data.DATABASE_URL}"
if ($antes -and $antes -eq $depois) { Ok "Secret restaurado e idêntico ao original (RPO = momento do backup)" }
else { Falhar "o Secret restaurado não confere com o original" }
exit 0
