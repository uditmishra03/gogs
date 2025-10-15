# Quick Rehydrate Guide

A concise, scripting-friendly checklist to recreate the full Gogs stack (EKS + Helm + PostgreSQL subchart) after an intentional teardown.

> Keep this file up-to-date when infra or chart conventions change.

---
## 0. Prerequisites
- Local tools: `awscli` (v2), `terraform (>=1.5)`, `kubectl`, `helm (>=3.12)`, `jq` (optional)
- AWS IAM identity with permissions for: IAM, EKS, EC2, VPC, ELB, S3, DynamoDB, CloudWatch Logs, KMS (if added later)
- Region (stored previously): `us-east-1`
- Desired cluster name: `gogs-prod-cluster`
- Terraform backend bucket + lock table:
  - S3 Bucket: `gogs-terraform-14101025` (create if deleted)
  - DynamoDB Table: `terraform-locks` (PK: `LockID` string)

If backend resources were deleted, (re)create:
```bash
aws s3 mb s3://gogs-terraform-14101025 --region us-east-1 || true
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST 2>/dev/null || true
```

Export region for all shell steps:
```bash
export AWS_REGION=us-east-1
export TF_IN_AUTOMATION=1
```

---
## 1. Terraform Infrastructure
```bash
cd eks-prod
terraform init -reconfigure
terraform apply -auto-approve
```
Outputs to note (if you add them): cluster name, VPC ID, private subnets.

Optional: if you want a dry run first:
```bash
terraform plan -out tfplan
```

---
## 2. EKS Access (If Using Access Entry)
If you set `admin_principal_arn` in `terraform.tfvars`, Terraform created an `aws_eks_access_entry` + policy association. Otherwise ensure your IAM entity can call `eks:DescribeCluster`.

Validate:
```bash
aws eks describe-cluster --name gogs-prod-cluster --region $AWS_REGION | jq '.cluster.status'
```
Should be `"ACTIVE"`.

Update local kubeconfig:
```bash
aws eks update-kubeconfig --name gogs-prod-cluster --region $AWS_REGION --alias gogs-prod
kubectl config use-context gogs-prod
kubectl get nodes
```

---
## 3. Cluster Add-ons
### 3.1 AWS Load Balancer Controller (IRSA + Helm)
(If you move this to Terraform later, skip.)
```bash
# Discover OIDC provider
OIDC_ID=$(aws eks describe-cluster --name gogs-prod-cluster --region $AWS_REGION --query 'cluster.identity.oidc.issuer' --output text | sed -e 's#https://##')

# Create IAM policy if not existing
curl -s https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json -o alb-iam-policy.json
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://alb-iam-policy.json 2>/dev/null || true

# Create service account via Helm (controller will create its own when serviceAccount.create=true)
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=gogs-prod-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$AWS_REGION \
  --set vpcId=$(terraform -chdir=eks-prod output -raw vpc_id 2>/dev/null || echo "<vpc-id>")
```
Verify:
```bash
kubectl -n kube-system get deploy aws-load-balancer-controller
```

### 3.2 EBS CSI Driver (Managed Add-on Recommended)
```bash
aws eks create-addon --cluster-name gogs-prod-cluster --addon-name aws-ebs-csi-driver --region $AWS_REGION 2>/dev/null || \
aws eks update-addon --cluster-name gogs-prod-cluster --addon-name aws-ebs-csi-driver --region $AWS_REGION

kubectl get pods -n kube-system | grep ebs-csi
```

(If using a custom StorageClass file in repo, apply it now.)
```bash
kubectl apply -f manifests/storage/gp2-csi-storageclass.yaml
kubectl get storageclass
```

---
## 4. Helm Chart (Gogs + Bitnami PostgreSQL)
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm dependency update ./helm-chart

# App DB secret (static approach Option A)
kubectl create namespace gogs 2>/dev/null || true
kubectl create secret generic gogs-db-secret -n gogs \
  --from-literal=password='StrongPass123!' 2>/dev/null || \
  kubectl patch secret gogs-db-secret -n gogs --type merge -p '{"data":{}}'

# Install/upgrade
helm upgrade --install gogs ./helm-chart \
  -n gogs --create-namespace \
  --set postgresql.auth.password='StrongPass123!'
```

Validate:
```bash
kubectl get pods -n gogs
kubectl get pvc -n gogs
kubectl get ingress -n gogs
ALB=$(kubectl get ingress -n gogs -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
[ -n "$ALB" ] && curl -I http://$ALB/ || echo "ALB not ready"
```

---
## 5. External DB Mode (Optional Instead of Subchart)
Disable embedded Postgres and point to RDS:
```bash
kubectl create secret generic gogs-db-secret -n gogs \
  --from-literal=postgres-password='RDS_Strong_Pass'

helm upgrade --install gogs ./helm-chart \
  -n gogs \
  --set postgresql.enabled=false \
  --set externalDatabase.enabled=true \
  --set externalDatabase.host='mydb.xxxxxx.us-east-1.rds.amazonaws.com' \
  --set externalDatabase.user='gogs' \
  --set externalDatabase.database='gogs' \
  --set externalDatabase.existingSecret='gogs-db-secret'
```

---
## 6. Operational Checks
```bash
# Liveness/readiness
kubectl logs -n gogs deploy/gogs --tail=100
kubectl exec -n gogs deploy/gogs -- netstat -tlnp | grep :3000 || true

# Postgres connectivity test (inside pod)
kubectl exec -n gogs $(kubectl get pod -n gogs -l app=gogs -o jsonpath='{.items[0].metadata.name}') -- \
  sh -c 'apk add --no-cache postgresql-client 2>/dev/null || true; psql -h gogs-postgresql -U gogs -d gogs -c "select 1"'
```

---
## 7. Updating & Scaling
- Scale app replicas: `helm upgrade gogs ./helm-chart -n gogs --set gogs.replicas=3`
- Increase app PVC size (if StorageClass allows expansion): edit `values.yaml` `gogsPersistence.size` and upgrade.
- Increase Postgres size: adjust `postgresql.primary.persistence.size` and rely on EBS volume expansion.

---
## 8. Backup & Migration
Embedded → External:
```bash
kubectl exec -n gogs statefulset/gogs-postgresql -- \
  sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U gogs gogs' > gogs.sql
# Restore into external DB, then switch helm values (see section 5)
```

---
## 9. Clean Teardown (Reverse Order)
```bash
helm uninstall gogs -n gogs || true
helm uninstall aws-load-balancer-controller -n kube-system || true
aws eks delete-addon --cluster-name gogs-prod-cluster --addon-name aws-ebs-csi-driver --region $AWS_REGION || true
terraform destroy -auto-approve   # from eks-prod
```
If VPC deletion is stuck: delete leftover LB, ENIs, custom SGs, then re-run destroy.

---
## 10. Common Pitfalls
| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Helm upgrade fails on `postgres.yaml` | Legacy template present | Ensure `templates/postgres.yaml` removed |
| Pods Pending (PVC) | EBS CSI driver not ready | Wait for addon ACTIVE / reinstall |
| ALB not created | Controller missing or IAM issue | Reinstall controller with correct IRSA & VPC ID |
| App 500 errors on first load | DB not ready yet | Wait; readiness probe will gate traffic |
| Destroy VPC dependency violation | Leftover SG or LB ENIs | Manually delete SGs / LBs, retry |

---
## 11. Future Enhancements (Backlog)
- Replace static DB env with templated dynamic logic (fallback secret keys).
- Add NetworkPolicy & PodSecurity standards.
- Integrate cert-manager for HTTPS ALB (ACM + annotation flow).
- Terraform modules for ALB controller & CSI additions.
- Automated backups (pg_dump CronJob or AWS RDS automated snapshots when external DB).

---
## 12. Version Bumps Checklist
When bumping chart or dependencies:
- `helm dependency update ./helm-chart`
- Review Bitnami Postgres release notes (major version data migration steps)
- Re-run smoke tests section 6.

---
**Done.** Use this guide to stand everything back up in ~10–15 minutes.
