# SolidaryTech - Infraestrutura (Terraform)

Infraestrutura da plataforma SolidaryTech na AWS, 100% como código. Parte do Hackathon da Fase 5 (FIAP POSTECH DevOps e Arquitetura Cloud).

| Repositório | Conteúdo |
|---|---|
| **solidarytech-infra** (este) | Terraform, scripts de operação e DR |
| [solidarytech-app](https://github.com/leonardopetruncko/solidarytech-app) | 3 microsserviços + CI/CD DevSecOps |
| [solidarytech-gitops](https://github.com/leonardopetruncko/solidarytech-gitops) | manifestos (Argo CD), observabilidade, SLOs e documentação |

## O que o Terraform cria

| Módulo | Recursos |
|---|---|
| `network` | VPC em 2 AZs, subnets públicas e privadas, 1 NAT Gateway, VPC Endpoints de S3 e DynamoDB |
| `eks` | EKS 1.34 + node group com launch template (tags FinOps, IMDSv2, gp3 criptografado) + metrics-server |
| `database` | RDS PostgreSQL (2 bancos lógicos, backup com PITR) + DynamoDB `SolidaryTechVolunteers` (GSI por ONG, PITR) |
| `messaging` | SQS `solidary-donations` + DLQ |
| `ecr` | 3 repositórios com scan on push e lifecycle |
| `backup` | configuração do bucket do Velero em **us-west-2** |
| `argocd` / `velero` | add-ons do cluster (2º apply) |
| `budget` | AWS Budget por tag (opcional) |

**FinOps:** todas as tags obrigatórias (`Project=SolidaryTech`, `Environment=Production`, `CostCenter=NGO-Core`) vêm do `default_tags` do provider e do launch template dos nós, com validação no código e no pipeline. Detalhes em [finops.md](https://github.com/leonardopetruncko/solidarytech-gitops/blob/main/docs/finops.md).

**DR:** o mesmo código sobe o ambiente espelho em us-west-2 (`envs/dr.tfvars`, workspace `dr`). Detalhes no [PCN](https://github.com/leonardopetruncko/solidarytech-gitops/blob/main/docs/pcn.md).

## Como usar

```powershell
copy scripts\fase5.env.example scripts\fase5.env   # preencha as chaves (o arquivo não vai para o Git)
.\scripts\testar-integracoes.ps1   # valida Datadog, PagerDuty e Discord
.\scripts\subir.ps1                # sobe tudo: Terraform (2 fases) + secrets + Argo CD
.\scripts\gerar-trafego.ps1        # tráfego nos 3 serviços
.\scripts\simular-falha.ps1        # Game Day: falha silenciosa no donation-service
.\scripts\velero-demo.ps1          # DR opção A: backup e restore com o Velero
.\scripts\dr.ps1                   # DR opção B: ambiente espelho em us-west-2 (1 comando)
.\scripts\datadog-aiops.ps1        # monitores de AIOps (Watchdog) no Datadog
.\scripts\destruir.ps1 -DR         # destrói o DR e o primário
```

## Pipeline (`.github/workflows/terraform.yml`)

`terraform fmt` e `validate` → verificação da política de tags → **Trivy IaC scan**. O pipeline falha em achado CRITICAL que não esteja justificado no `.trivyignore`.