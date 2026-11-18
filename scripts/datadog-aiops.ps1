<#
.SYNOPSIS
  AIOps no Datadog como código: cria (ou atualiza) o monitor dos alertas do Watchdog.

.DESCRIPTION
  O Watchdog (IA do Datadog) já analisa sozinho o APM dos serviços. Este script cria um
  monitor que transforma toda anomalia detectada pelo Watchdog no env:production em
  alerta (com notificação), e outro de anomalia de latência (algoritmo "agile") no
  donation-service. Precisa de DATADOG_API_KEY e DATADOG_APP_KEY no fase5.env.

.EXAMPLE
  .\scripts\datadog-aiops.ps1
#>
param([string]$EnvFile = (Join-Path $PSScriptRoot "fase5.env"))
. (Join-Path $PSScriptRoot "_comum.ps1")
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$cfg = Ler-Env $EnvFile
if (-not $cfg["DATADOG_APP_KEY"]) { Falhar "DATADOG_APP_KEY vazio (Organization Settings > Application Keys)" }
$site = if ($cfg["DATADOG_SITE"]) { $cfg["DATADOG_SITE"] } else { "datadoghq.com" }
$h = @{ "DD-API-KEY" = $cfg["DATADOG_API_KEY"]; "DD-APPLICATION-KEY" = $cfg["DATADOG_APP_KEY"]; "Content-Type" = "application/json" }
$api = "https://api.$site/api/v1/monitor"

function Criar-Monitor($m) {
    $existentes = Invoke-RestMethod -Uri "$api`?name=$([Uri]::EscapeDataString($m.name))" -Headers $h
    $corpo = [Text.Encoding]::UTF8.GetBytes(($m | ConvertTo-Json -Depth 10))
    if ($existentes.Count -gt 0) {
        Invoke-RestMethod -Method Put -Uri "$api/$($existentes[0].id)" -Headers $h -Body $corpo | Out-Null
        Ok "monitor atualizado: $($m.name) (id $($existentes[0].id))"
    }
    else {
        $r = Invoke-RestMethod -Method Post -Uri $api -Headers $h -Body $corpo
        Ok "monitor criado: $($m.name) (id $($r.id))"
    }
}

Passo "Monitores de AIOps"
Criar-Monitor @{
    name    = "[SolidaryTech] Watchdog detectou anomalia em produção"
    type    = "event-v2 alert"
    query   = 'events("source:watchdog env:production").rollup("count").last("15m") > 0'
    message = "O Watchdog (IA do Datadog) detectou um comportamento fora do padrão em produção.`n{{event.title}}`nVer o story no Watchdog e o runbook: https://github.com/leonardopetruncko/solidarytech-gitops/blob/main/docs/itsm-incidentes.md"
    tags    = @("project:solidarytech", "team:sre", "aiops:watchdog")
    options = @{ notify_no_data = $false; include_tags = $true }
    priority = 2
}
Criar-Monitor @{
    name    = "[SolidaryTech] Anomalia de latência no donation-service"
    type    = "query alert"
    query   = "avg(last_4h):anomalies(avg:trace.http.server.request.duration{env:production,service:donation-service}, 'agile', 3, direction='above', interval=60, alert_window='last_15m', count_default_zero='true') >= 1"
    message = "Latência do Hot Path fora da banda prevista pelo modelo de anomalia (AIOps). Ver APM > donation-service."
    tags    = @("project:solidarytech", "team:sre", "aiops:anomaly")
    options = @{ thresholds = @{ critical = 1.0 }; threshold_windows = @{ trigger_window = "last_15m"; recovery_window = "last_15m" }; notify_no_data = $false }
    priority = 2
}
Write-Host "`nVeja em: https://app.$site/monitors/manage?q=SolidaryTech  e  https://app.$site/watchdog" -ForegroundColor Green
