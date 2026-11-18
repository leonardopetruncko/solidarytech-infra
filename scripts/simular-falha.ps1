<#
.SYNOPSIS
  Game Day: injeta uma falha silenciosa no donation-service (Hot Path).

.DESCRIPTION
  Chama POST /admin/chaos em TODOS os pods do donation-service (token vem do Secret).
  O /health continua 200: o Kubernetes não percebe. Quem percebe é o SRE:
    burn rate do error budget > 14,4x -> alerta -> PagerDuty + Discord -> self-healer
    faz rollout restart -> pods novos sem a falha -> alerta RESOLVED + MTTR no Discord.

.EXAMPLE
  .\scripts\simular-falha.ps1                        # 30% das doações com HTTP 500
  .\scripts\simular-falha.ps1 -Modo latency          # doações lentas (1,2 s)
  .\scripts\simular-falha.ps1 -Percentual 60
  .\scripts\simular-falha.ps1 -Desligar
#>
param(
    [ValidateSet("error", "latency")][string]$Modo = "error",
    [int]$Percentual = 30,
    [switch]$Desligar
)
. (Join-Path $PSScriptRoot "_comum.ps1")
$ns = "solidarytech"

$token = Ler-Secret $ns "donation-service-secret" "ADMIN_TOKEN"
if (-not $token) { Falhar "secret donation-service-secret sem ADMIN_TOKEN (rode o subir.ps1)" }

$pods = kubectl get pods -n $ns -l app=donation-service --field-selector=status.phase=Running -o "jsonpath={range .items[*]}{.status.podIP}{'\n'}{end}"
$ips = @($pods -split "`n" | Where-Object { $_.Trim() })
if ($ips.Count -eq 0) { Falhar "nenhum pod do donation-service rodando" }

$metodo = if ($Desligar) { "DELETE" } else { "POST" }
$urls = ($ips | ForEach-Object { "http://$($_.Trim()):8082/admin/chaos?mode=$Modo&percent=$Percentual" }) -join " "

kubectl delete pod chaos -n $ns --ignore-not-found --wait=true 2>$null | Out-Null
$manifest = @"
apiVersion: v1
kind: Pod
metadata:
  name: chaos
  namespace: solidarytech
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
  containers:
    - name: curl
      image: curlimages/curl:8.11.1
      env:
        - name: TOKEN
          valueFrom:
            secretKeyRef:
              name: donation-service-secret
              key: ADMIN_TOKEN
      command: ["sh", "-c"]
      args:
        - 'for u in $urls; do curl -s -X $metodo -H "Authorization: Bearer `$TOKEN" "`$u"; echo; done'
"@
$manifest | kubectl apply -f - | Out-Null
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/chaos -n $ns --timeout=90s | Out-Null
kubectl logs chaos -n $ns
kubectl delete pod chaos -n $ns --ignore-not-found 2>$null | Out-Null

if ($Desligar) { Write-Host "Falha desligada nos $($ips.Count) pods." -ForegroundColor Yellow; exit 0 }

Write-Host "`nFALHA INJETADA ($Modo) nos $($ips.Count) pods do donation-service - $(Get-Date -Format HH:mm:ss)" -ForegroundColor Red
Write-Host "Acompanhe:"
Write-Host "  1. Grafana > SolidaryTech - SRE: burn rate subindo e error budget caindo"
Write-Host "  2. Grafana > Alerting: FIRING em ~2 min | PagerDuty: incidente | Discord: mensagem"
Write-Host "  3. kubectl logs -f deploy/self-healer -n observability"
Write-Host "  4. kubectl get pods -n solidarytech -l app=donation-service -w"
Write-Host "  5. Datadog APM: traces com erro no donation-service (e o Watchdog)"
exit 0
