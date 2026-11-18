<#
.SYNOPSIS
  FinOps: evidência da política de tags. Lista todos os recursos com Project=SolidaryTech
  (API Resource Groups Tagging) e mostra as tags obrigatórias de cada um.

.EXAMPLE
  .\scripts\listar-tags.ps1
  .\scripts\listar-tags.ps1 -Regiao us-west-2
#>
param([string]$Regiao = "us-east-1")
. (Join-Path $PSScriptRoot "_comum.ps1")

$json = aws resourcegroupstaggingapi get-resources --region $Regiao --tag-filters Key=Project,Values=SolidaryTech --output json
if ($LASTEXITCODE -ne 0) { Falhar "não consegui consultar a API de tags (credenciais do Lab?)" }
$lista = (($json | Out-String) | ConvertFrom-Json).ResourceTagMappingList

$linhas = $lista | ForEach-Object {
    $t = @{}; $_.Tags | ForEach-Object { $t[$_.Key] = $_.Value }
    [pscustomobject]@{
        Servico     = ($_.ResourceARN -split ':')[2]
        Recurso     = ($_.ResourceARN -split '[:/]')[-1]
        Project     = $t.Project
        Environment = $t.Environment
        CostCenter  = $t.CostCenter
        Service     = $t.Service
    }
} | Sort-Object Servico, Recurso

$linhas | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
$sem = @($linhas | Where-Object { -not $_.Environment -or -not $_.CostCenter })
Write-Host "Recursos com Project=SolidaryTech em ${Regiao}: $($linhas.Count)" -ForegroundColor Cyan
if ($sem.Count -eq 0) { Ok "100% com as tags obrigatórias (Project, Environment, CostCenter)" }
else { Aviso "$($sem.Count) recurso(s) sem todas as tags obrigatórias" }