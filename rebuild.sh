#!/bin/bash
set -e

echo "========================================"
echo "   Project Bedrock — Rebuild Script"
echo "   InnovateMart EKS Infrastructure"
echo "========================================"
echo ""

# ── Step 1: Terraform apply ──────────────────
echo ">>> Step 1: Provisioning infrastructure with Terraform..."
cd terraform/root
terraform init
terraform apply -auto-approve

VPC_ID=$(terraform output -raw vpc_id)
MYSQL_ENDPOINT=$(terraform output -raw mysql_endpoint | cut -d':' -f1)
POSTGRES_ENDPOINT=$(terraform output -raw postgres_endpoint | cut -d':' -f1)
cd ../..
echo "✅ Infrastructure provisioned"
echo "   VPC ID: $VPC_ID"
echo "   MySQL: $MYSQL_ENDPOINT"
echo "   Postgres: $POSTGRES_ENDPOINT"

# ── Step 2: Update values-bedrock.yaml ───────
echo ""
echo ">>> Step 2: Updating RDS endpoints in values-bedrock.yaml..."
sed -i '' "s|endpoint:.*bedrock-mysql.*|endpoint: $MYSQL_ENDPOINT|g" \
  helm/retail-store-upstream/values-bedrock.yaml
sed -i '' "s|host:.*bedrock-postgres.*|host: $POSTGRES_ENDPOINT|g" \
  helm/retail-store-upstream/values-bedrock.yaml
echo "✅ RDS endpoints updated"

# ── Step 3: Connect kubectl ──────────────────
echo ""
echo ">>> Step 3: Connecting kubectl to EKS cluster..."
aws eks update-kubeconfig \
  --region us-east-1 \
  --name project-bedrock-cluster
echo "✅ kubectl connected"

# ── Step 4: Wait for nodes ───────────────────
echo ""
echo ">>> Step 4: Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s
echo "✅ Nodes ready"

# ── Step 5: Create namespace ─────────────────
echo ""
echo ">>> Step 5: Creating retail-app namespace..."
kubectl create namespace retail-app --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Namespace ready"

# ── Step 6: DynamoDB GSI ─────────────────────
echo ""
echo ">>> Step 6: Adding DynamoDB GSI for carts service..."
aws dynamodb update-table \
  --table-name bedrock-retail-store \
  --attribute-definitions AttributeName=customerId,AttributeType=S \
  --global-secondary-index-updates \
  '[{"Create":{"IndexName":"idx_global_customerId","KeySchema":[{"AttributeName":"customerId","KeyType":"HASH"}],"Projection":{"ProjectionType":"ALL"}}}]' \
  --region us-east-1 2>/dev/null && \
  echo "✅ DynamoDB GSI created" || \
  echo "⚠️  GSI may already exist, skipping"

echo "Waiting 30 seconds for DynamoDB GSI to become active..."
sleep 30

# ── Step 7: ALB Controller IAM Policy ────────
echo ""
echo ">>> Step 7: Checking ALB Controller IAM policy..."
aws iam get-policy \
  --policy-arn arn:aws:iam::035786426828:policy/AWSLoadBalancerControllerIAMPolicy \
  --region us-east-1 > /dev/null 2>&1 && \
  echo "✅ ALB IAM policy already exists" || \
  (echo "Creating ALB IAM policy..." && \
  curl -s -o /tmp/alb-iam-policy.json \
    https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json && \
  aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file:///tmp/alb-iam-policy.json && \
  echo "✅ ALB IAM policy created")

# ── Step 8: Install ALB Controller ───────────
echo ""
echo ">>> Step 8: Installing AWS Load Balancer Controller..."
helm repo add eks https://aws.github.io/eks-charts > /dev/null 2>&1
helm repo update > /dev/null 2>&1

eksctl create iamserviceaccount \
  --cluster=project-bedrock-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::035786426828:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve \
  --region us-east-1

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=project-bedrock-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1 \
  --set vpcId=$VPC_ID
echo "✅ ALB Controller installed"

# ── Step 9: Secrets Store CSI Driver ─────────
echo ""
echo ">>> Step 9: Installing Secrets Store CSI driver..."
helm repo add secrets-store-csi-driver \
  https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts > /dev/null 2>&1
helm repo update > /dev/null 2>&1

helm upgrade --install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true

kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

echo "Waiting 30 seconds for CSI driver pods to start..."
sleep 30

kubectl patch csidriver secrets-store.csi.k8s.io \
  --type=merge \
  -p '{"spec":{"tokenRequests":[{"audience":"sts.amazonaws.com"}]}}'
echo "✅ Secrets Store CSI driver installed"

# ── Step 10: CloudWatch Observability ────────
echo ""
echo ">>> Step 10: Installing CloudWatch Observability addon..."
aws eks create-addon \
  --cluster-name project-bedrock-cluster \
  --addon-name amazon-cloudwatch-observability \
  --region us-east-1 2>/dev/null && \
  echo "✅ CloudWatch addon installed" || \
  echo "⚠️  CloudWatch addon may already exist, skipping"

# ── Step 11: Node role policies ──────────────
echo ""
echo ">>> Step 11: Attaching policies to node role..."
NODE_ROLE=$(aws eks describe-nodegroup \
  --cluster-name project-bedrock-cluster \
  --nodegroup-name $(aws eks list-nodegroups \
    --cluster-name project-bedrock-cluster \
    --query 'nodegroups[0]' \
    --output text \
    --region us-east-1) \
  --query 'nodegroup.nodeRole' \
  --output text \
  --region us-east-1 | cut -d'/' -f2)

aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy 2>/dev/null || true

aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true

aws iam attach-role-policy \
  --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess 2>/dev/null || true

echo "✅ Node role policies attached"

# ── Step 12: SSM service account ─────────────
echo ""
echo ">>> Step 12: Creating SSM service account..."
eksctl create iamserviceaccount \
  --name ssm-secrets-sa \
  --namespace retail-app \
  --cluster project-bedrock-cluster \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess \
  --override-existing-serviceaccounts \
  --approve \
  --region us-east-1
echo "✅ SSM service account created"

# ── Step 13: RBAC for bedrock-dev-view ───────
echo ""
echo ">>> Step 13: Setting up RBAC for bedrock-dev-view..."
aws eks create-access-entry \
  --cluster-name project-bedrock-cluster \
  --principal-arn arn:aws:iam::035786426828:user/bedrock-dev-view \
  --region us-east-1 2>/dev/null || true

aws eks associate-access-policy \
  --cluster-name project-bedrock-cluster \
  --principal-arn arn:aws:iam::035786426828:user/bedrock-dev-view \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=namespace,namespaces=retail-app \
  --region us-east-1 2>/dev/null || true

kubectl apply -f kubernetes/rbac.yaml
echo "✅ RBAC configured"

# ── Step 14: Database secrets from SSM ───────
echo ""
echo ">>> Step 14: Creating database secrets from SSM..."
MYSQL_PASS=$(aws ssm get-parameter \
  --name '/bedrock/mysql/password' \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region us-east-1)

POSTGRES_PASS=$(aws ssm get-parameter \
  --name '/bedrock/postgres/password' \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region us-east-1)

kubectl create secret generic catalog-db-secret \
  --from-literal=username=admin \
  --from-literal=password=$MYSQL_PASS \
  -n retail-app \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic orders-db-secret \
  --from-literal=username=dbadmin \
  --from-literal=password=$POSTGRES_PASS \
  -n retail-app \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Database secrets created"

# ── Step 15: Deploy application ──────────────
echo ""
echo ">>> Step 15: Deploying retail store application..."
kubectl label namespace retail-app \
  app.kubernetes.io/managed-by=Helm --overwrite
kubectl annotate namespace retail-app \
  meta.helm.sh/release-name=retail-store \
  meta.helm.sh/release-namespace=retail-app \
  --overwrite

helm upgrade --install retail-store helm/retail-store-upstream \
  --namespace retail-app \
  --values helm/retail-store-upstream/values-bedrock.yaml
echo "✅ Application deployed"

# ── Step 16: Apply manifests ─────────────────
echo ""
echo ">>> Step 16: Applying Kubernetes manifests..."
kubectl apply -f kubernetes/ingress.yaml
kubectl apply -f kubernetes/rbac.yaml
kubectl apply -f kubernetes/secret-provider-class.yaml
echo "✅ Manifests applied"

# ── Step 17: Generate grading.json ───────────
echo ""
echo ">>> Step 17: Generating grading.json..."
cd terraform/root
terraform output -json > ../../grading.json
cd ../..
echo "✅ grading.json updated"

# ── Step 18: Commit updated files ────────────
echo ""
echo ">>> Step 18: Committing updated files..."
git add grading.json helm/retail-store-upstream/values-bedrock.yaml
git commit -m "chore: update grading.json and RDS endpoints after rebuild"
git push origin main
echo "✅ Files committed"

# ── Final status ─────────────────────────────
echo ""
echo "Waiting 3 minutes for all pods to start..."
sleep 180

echo ""
echo "========================================"
echo "   Rebuild complete!"
echo "========================================"
echo ""
echo "Node status:"
kubectl get nodes

echo ""
echo "Pod status:"
kubectl get pods -n retail-app

echo ""
echo "Ingress:"
kubectl get ingress -n retail-app

echo ""
echo "App URL: https://bedrock.fatimahonomoh.com"
echo ""
echo "If any pods are not running, check logs:"
echo "  kubectl logs -n retail-app <pod-name>"
