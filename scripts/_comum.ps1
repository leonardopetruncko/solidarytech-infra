# Funções compartilhadas pelos scripts da Fase 5 (carregado com ". $PSScriptRoot\_comum.ps1").

$ErrorActionPreference = "Continue"   # PS 5.1: stderr de comando nativo com "Stop" vira exceção
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$script:InfraDir = Split-Path -Parent $PSScriptRoot
$script:TfDir = Join-Path $script:InfraDir "terraform"
$script:GitopsDir = Join-Path (Split-Path -Parent $script:InfraDir) "solidarytech-gitops"

function Passo([string]$m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok([string]$m) { Write-Host "    OK  $m" -ForegroundColor Green }
function Aviso([string]$m) { Write-Host "    !!  $m" -ForegroundColor Yellow }
function Falhar([string]$m) { Write-Host "`nERRO: $m" -ForegroundColor Red; exit 1 }

function Novo-Hex([int]$bytes) {
    $b = New-Object byte[] $bytes
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    return -join ($b | ForEach-Object { $_.ToString("x2") })
}

function Ler-Env([string]$arquivo) {
    if (-not (Test-Path $arquivo)) { Falhar "não achei $arquivo. Copie fase5.env.example para fase5.env e preencha." }
    $cfg = @{}
    foreach ($linha in Get-Content $arquivo -Encoding UTF8) {
        $l = $linha.Trim()
        if ($l -eq "" -or $l.StartsWith("#") -or -not $l.Contains("=")) { continue }
        $i = $l.IndexOf("=")
        $cfg[$l.Substring(0, $i).Trim()] = $l.Substring($i + 1).Trim().Trim('"')
    }
    return $cfg
}

function Conta-Aws {
    $id = aws sts get-caller-identity --query Account --output text 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $id) { Falhar "sem credencial AWS válida. Cole as credenciais do Lab (AWS Details) e tente de novo." }
    return $id.Trim()
}

# Cria (se não existir) um bucket S3 seguro e tagueado. Feito pela AWS CLI porque, no AWS
# Academy, uma SCP nega s3:GetBucketObjectLockConfiguration, que o aws_s3_bucket do
# Terraform sempre lê. O bucket do state precisa existir antes do Terraform de qualquer forma.
function Garantir-Bucket([string]$bucket, [string]$regiao, [string]$proposito) {
    aws s3api head-bucket --bucket $bucket --region $regiao 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok "bucket $bucket já existe"; return }
    if ($regiao -eq "us-east-1") { aws s3api create-bucket --bucket $bucket --region $regiao | Out-Null }
    else { aws s3api create-bucket --bucket $bucket --region $regiao --create-bucket-configuration "LocationConstraint=$regiao" | Out-Null }
    if ($LASTEXITCODE -ne 0) { Falhar "não consegui criar o bucket $bucket" }
    aws s3api put-public-access-block --bucket $bucket --region $regiao --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" | Out-Null
    aws s3api put-bucket-versioning --bucket $bucket --region $regiao --versioning-configuration Status=Enabled | Out-Null
    aws s3api put-bucket-encryption --bucket $bucket --region $regiao --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}' | Out-Null
    aws s3api put-bucket-tagging --bucket $bucket --region $regiao --tagging "TagSet=[{Key=Project,Value=SolidaryTech},{Key=Environment,Value=Production},{Key=CostCenter,Value=NGO-Core},{Key=ManagedBy,Value=scripts},{Key=Purpose,Value=$proposito}]" | Out-Null
    Ok "bucket $bucket criado em $regiao (privado, versionado, criptografado, tagueado)"
}

# Init do Terraform apontando o backend para o bucket desta conta.
function Terraform-Init([string]$conta) {
    $bucket = "solidarytech-tfstate-$conta"
    Garantir-Bucket $bucket "us-east-1" "terraform-remote-state"
    Garantir-Bucket "solidarytech-velero-$conta" "us-west-2" "velero-backup"
    terraform "-chdir=$script:TfDir" init -input=false -reconfigure "-backend-config=bucket=$bucket" | Out-Null
    if ($LASTEXITCODE -ne 0) { Falhar "terraform init falhou" }
    Ok "backend s3://$bucket"
}

function Aplicar-Namespace([string]$ns) {
    kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - | Out-Null
    if ($LASTEXITCODE -ne 0) { Falhar "não consegui criar o namespace $ns" }
}

function Ler-Secret([string]$ns, [string]$nome, [string]$chave) {
    $b64 = kubectl get secret $nome -n $ns -o "jsonpath={.data.$chave}" 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($b64)) { return $null }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
}

function Aplicar-Secret([string]$ns, [string]$nome, [hashtable]$dados) {
    $argumentos = @("create", "secret", "generic", $nome, "-n", $ns, "--dry-run=client", "-o", "yaml")
    foreach ($k in $dados.Keys) {
        if (-not [string]::IsNullOrEmpty($dados[$k])) { $argumentos += "--from-literal=$k=$($dados[$k])" }
    }
    $yaml = & kubectl @argumentos
    if ($LASTEXITCODE -ne 0) { Falhar "não consegui montar o secret $ns/$nome" }
    $yaml | kubectl apply -f - | Out-Null
    if ($LASTEXITCODE -ne 0) { Falhar "não consegui aplicar o secret $ns/$nome" }
    Ok "secret $ns/$nome"
}

# Secrets do cluster: senhas do banco e chaves das integrações. Nada disso vai para o Git.
function Criar-Secrets($tf, $cfg) {
    $rds = $tf.rds_endpoint.value
    $master = $tf.db_password.value

    Aplicar-Namespace "solidarytech"
    Aplicar-Namespace "observability"

    # Região do site ativo: o mesmo manifesto GitOps roda no primário e no DR.
    kubectl create configmap solidarytech-site -n solidarytech "--from-literal=AWS_REGION=$($tf.region.value)" "--from-literal=SITE=$($tf.site.value)" --dry-run=client -o yaml | kubectl apply -f - | Out-Null
    Ok "configmap solidarytech/solidarytech-site ($($tf.site.value) em $($tf.region.value))"

    Aplicar-Secret "solidarytech" "solidarytech-db-admin" @{ PGHOST = $rds; PGUSER = "dbadmin"; PGPASSWORD = $master }

    # Um usuário por serviço (menor privilégio). Reaproveita a senha se o secret já existe.
    foreach ($svc in @(@{ n = "ngo-service"; u = "ngo_app"; db = "ngo_db" }, @{ n = "donation-service"; u = "donation_app"; db = "donation_db" })) {
        $pass = Ler-Secret "solidarytech" "$($svc.n)-secret" "DB_PASSWORD"
        if (-not $pass) { $pass = Novo-Hex 16 }
        $dados = @{
            DB_USER      = $svc.u
            DB_PASSWORD  = $pass
            DATABASE_URL = "postgres://$($svc.u):$pass@${rds}:5432/$($svc.db)?sslmode=require"
        }
        if ($svc.n -eq "donation-service") {
            $admin = Ler-Secret "solidarytech" "donation-service-secret" "ADMIN_TOKEN"
            if (-not $admin) { $admin = Novo-Hex 16 }
            $dados["AWS_SQS_URL"] = $tf.sqs_url.value
            $dados["ADMIN_TOKEN"] = $admin
        }
        Aplicar-Secret "solidarytech" "$($svc.n)-secret" $dados
    }

    $grafanaPass = $cfg["GRAFANA_ADMIN_PASSWORD"]
    if ([string]::IsNullOrEmpty($grafanaPass)) {
        $grafanaPass = Ler-Secret "observability" "grafana-admin" "admin-password"
        if (-not $grafanaPass) { $grafanaPass = Novo-Hex 8 }
    }
    Aplicar-Secret "observability" "grafana-admin" @{ "admin-user" = "admin"; "admin-password" = $grafanaPass }
    Aplicar-Secret "observability" "grafana-alerting" @{
        PAGERDUTY_ROUTING_KEY = $cfg["PAGERDUTY_ROUTING_KEY"]
        DISCORD_WEBHOOK_URL   = $cfg["DISCORD_WEBHOOK_URL"]
    }
    Aplicar-Secret "observability" "datadog-api" @{ "api-key" = $cfg["DATADOG_API_KEY"] }
    return $grafanaPass
}

function Ler-Outputs {
    $json = terraform "-chdir=$script:TfDir" output -json
    if ($LASTEXITCODE -ne 0) { Falhar "não consegui ler os outputs do Terraform" }
    return (($json | Out-String) | ConvertFrom-Json)
}
