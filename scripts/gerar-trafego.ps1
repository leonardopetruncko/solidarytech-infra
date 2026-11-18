<#
.SYNOPSIS
  Gera tráfego contínuo nos 3 microsserviços (alimenta Golden Metrics, SLOs, traces e alertas).

.DESCRIPTION
  Sobe o pod "trafego" (curl) dentro do cluster, que chama em loop:
    POST /donations (Hot Path) + GET /donations, POST/GET /ngos, POST/GET /volunteers.
  Cada linha mostra o HTTP status de cada chamada (000 = timeout).

.EXAMPLE
  .\scripts\gerar-trafego.ps1          # inicia e mostra o log (Ctrl+C só sai do log)
  .\scripts\gerar-trafego.ps1 -Parar   # remove o pod
#>
param([switch]$Parar)
. (Join-Path $PSScriptRoot "_comum.ps1")
$ns = "solidarytech"

kubectl delete pod trafego -n $ns --ignore-not-found --wait=true 2>$null | Out-Null
if ($Parar) { Write-Host "Tráfego parado." -ForegroundColor Yellow; exit 0 }

$manifest = @'
apiVersion: v1
kind: Pod
metadata:
  name: trafego
  namespace: solidarytech
  labels:
    app: trafego
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: curl
      image: curlimages/curl:8.11.1
      resources:
        requests: { cpu: 20m, memory: 16Mi }
        limits: { memory: 32Mi }
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: { drop: ["ALL"] }
      command: ["sh", "-c"]
      args:
        - |
          D=http://donation-service:8082; N=http://ngo-service:8081; V=http://volunteer-service:8083
          H="Content-Type: application/json"
          i=0
          while true; do
            i=$((i+1)); ngo=$(( (i % 2) + 1 )); valor=$(( (i % 200) + 10 ))
            d=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" -X POST -H "$H" -d "{\"ngo_id\":$ngo,\"amount\":$valor.50,\"donor_name\":\"Doador $i\"}" $D/donations)
            dl=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" $D/donations)
            if [ $((i % 5)) -eq 0 ]; then
              n=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" -X POST -H "$H" -d "{\"name\":\"ONG $i\",\"email\":\"ong$i-$RANDOM@teste.org\",\"cause\":\"Educação\",\"city\":\"São Paulo\"}" $N/ngos)
              v=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" -X POST -H "$H" -d "{\"name\":\"Voluntario $i\",\"email\":\"v$i@teste.org\",\"ngo_id\":$ngo}" $V/volunteers)
            else
              n=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" $N/ngos)
              v=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" $V/volunteers/$ngo)
            fi
            echo "$(date +%H:%M:%S) #$i doacao=$d listar=$dl ongs=$n voluntarios=$v"
            sleep 0.3
          done
'@

$manifest | kubectl apply -f - | Out-Null
if ($LASTEXITCODE -ne 0) { Falhar "não consegui criar o pod de tráfego" }
kubectl wait --for=condition=Ready pod/trafego -n $ns --timeout=90s | Out-Null
Write-Host "Tráfego rodando no pod 'trafego' (Ctrl+C sai do log; o tráfego continua)." -ForegroundColor Green
Write-Host "Para parar: .\scripts\gerar-trafego.ps1 -Parar`n"
kubectl logs -f trafego -n $ns
