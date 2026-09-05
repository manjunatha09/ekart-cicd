# ekart-cicd

A GitOps CI/CD demo project: a minimal Spring Boot app, built and scanned by
Jenkins, deployed to a self-managed Kubernetes cluster (kubeadm + containerd
+ Calico) via Argo CD, all running on AWS infrastructure provisioned with
Terraform.

```
GitHub (this repo)
   │  git push
   ▼
Jenkins  ──▶  Maven build/test ──▶ SonarQube ──▶ OWASP Dependency-Check
   │                                                  │
   │                                            Trivy FS scan
   ▼
Docker Hub (manja098/ekart:<build-number>)
   │
   ▼
Trivy image scan ──▶ Jenkins updates kubernetes/deployment.yaml
   │
   ▼
git commit + push (same repo, "[ci skip]")
   │
   ▼
Argo CD detects the change ──▶ syncs Kubernetes ──▶ rolling update
```

Jenkins never runs `kubectl apply`. It only builds, scans, and updates the
desired state in Git — Argo CD is what actually deploys to the cluster.

## 1. Prerequisites

- An AWS account with an active Free Tier / credits (EC2, EBS, S3, DynamoDB
  usage below is **not** entirely free-tier eligible — see the cost note
  at the end)
- AWS CLI configured locally (`aws configure`)
- Terraform >= 1.5
- An existing EC2 Key Pair (see below)
- A GitHub account
- A Docker Hub account with the `manja098/ekart` repository

## 2. AWS setup

Make sure your AWS CLI credentials belong to a user/role with permission
to create VPCs, EC2 instances, security groups, S3 buckets, DynamoDB
tables, and IAM roles.

## 3. Key pair

In the AWS Console: **EC2 → Key Pairs → Create key pair**, name it
`awspem`, download `awspem.pem`, and keep it somewhere safe — it is
**not** included in this repo and Terraform does not upload it anywhere.

```bash
chmod 400 awspem.pem
```

## 4. Getting your public IP

SSH is restricted to your IP by design. Get it with:

```bash
./scripts/get-public-ip.sh
```

Copy the result into `terraform/infrastructure/terraform.tfvars` as
`admin_cidr`. If your ISP changes your IP later, re-run this and
`terraform apply` again to update the Security Group rule.

## 5. Terraform bootstrap (state bucket)

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Note the `state_bucket_name` output and paste it into
`terraform/infrastructure/backend.tf`.

## 6. Terraform infrastructure

```bash
cd ../infrastructure
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set admin_cidr, key_pair_name, and optionally
# git_repo_url (see §10)
terraform init
terraform apply
```

This creates the VPC, subnet, security groups, an AWS Network Load
Balancer, and all five EC2 instances (Jenkins, SonarQube, Kubernetes
control plane + 2 workers), each running its user-data bootstrap script
automatically. Note the output IPs and `app_url`.

Instance bootstrap (SonarQube's first start, the Kubernetes control-plane
init, and each worker automatically joining via SSM — see §9) takes a
few minutes — give it 5–10 minutes before moving on.

## 7. Jenkins setup

1. SSH in and grab the initial admin password:
   ```bash
   ssh -i awspem.pem ubuntu@<jenkins_public_ip> \
     sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
2. Open `http://<jenkins_public_ip>:8080`, unlock, install suggested
   plugins, plus: **SonarQube Scanner**, **OWASP Dependency-Check**,
   **Pipeline: GitHub**, **Docker Pipeline**.
3. Configure the SonarQube server under **Manage Jenkins → System** as
   `sonarqube-server`, and the Dependency-Check tool install as
   `owasp-dc` (matching the names used in `jenkins/Jenkinsfile`).
4. Create Jenkins credentials (see §13/§14 below): `dockerhub`, `github`.

## 8. SonarQube setup

Open `http://<sonarqube_public_ip>:9000`, log in with the default
`admin`/`admin` and change the password. Generate a token under
**My Account → Security** and add it to the Jenkins SonarQube server
configuration.

## 9. Kubernetes verification

The control plane finishes `kubeadm init`, installs Calico + Argo CD, and
publishes the `kubeadm join` command to an AWS SSM Parameter Store
parameter (`/ekart-cicd/k8s-join-command`, as a `SecureString`). Each
worker polls that parameter and runs the join command itself as soon as
it appears — **no manual SSH copy-paste required.** Auth in both
directions goes through the instances' IAM role (`terraform/infrastructure/iam.tf`),
scoped to only that one parameter plus the KMS calls needed to
decrypt it.

Give it a few minutes after `terraform apply`, then verify from the
master:

```bash
ssh -i awspem.pem ubuntu@<k8s_master_public_ip>
kubectl get nodes
# should show 3 nodes (control-plane + 2 workers) in Ready state
```

If a worker never joins, check its own log — `/var/log/ekart-bootstrap.log`
on that instance — and its bootstrap script will tell you the exact `aws
ssm get-parameter` command to run by hand as a fallback.

## 10. Argo CD installation

Argo CD itself (the control plane — `argocd-server`, `argocd-repo-server`,
etc.) is installed automatically by the control-plane bootstrap script,
in the `argocd` namespace, exposed as a NodePort service. Get the initial
admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

That only gets Argo CD *running* — it isn't watching anything yet.
`argocd/application.yaml` is the object that tells it what to watch: it's
an `Application` custom resource specifying this repo's `kubernetes/`
folder as the source, the local cluster as the destination, and
`automated: {prune: true, selfHeal: true}` so it syncs on every push and
reverts any manual `kubectl` drift back to what's in Git.

Two ways to get it applied:
- **Automatic**: set `git_repo_url` in `terraform.tfvars` before `terraform
  apply` (see §6) — the control plane applies it for you during bootstrap.
- **Manual**: edit the placeholder `repoURL` in `argocd/application.yaml`
  to point at your actual repo, then:
  ```bash
  kubectl apply -f argocd/application.yaml
  ```

Either way, log in to the Argo CD UI at
`http://<any-node-public-ip>:<argocd-nodeport>` (find the NodePort with
`kubectl -n argocd get svc argocd-server`) to watch the `ekart-cicd`
Application's sync status.

## 11. GitHub webhook

On this repository: **Settings → Webhooks → Add webhook**
- Payload URL: `http://<jenkins_public_ip>:8080/github-webhook/`
- Content type: `application/json`
- Trigger: **Just the push event**

## 12. Jenkins credentials

**Manage Jenkins → Credentials → Global**, add:
- `dockerhub` — Username/Password, using a Docker Hub **access token**
  (not your account password) with Read/Write scope.
- `github` — Username/Password (or a fine-grained PAT) with permission to
  push to this repository.

## 13. Docker Hub credentials

Create the token at **Docker Hub → Account Settings → Security → New
Access Token**. The existing `manja098/ekart` repository (with its
`latest` tag from earlier experiments) is reused as-is — the pipeline
only ever pushes new, immutable, numbered tags (`:1`, `:2`, `:3`, ...)
alongside whatever is already there.

## 14. SonarQube credentials

Covered in §8 — a token generated in the SonarQube UI, added to the
Jenkins SonarQube server config.

## 15. Running the pipeline

Push a commit to this repository (or click **Build Now** in Jenkins). The
webhook triggers Jenkins, which runs the full pipeline described in
`jenkins/Jenkinsfile`.

## 16. Testing deployment

Once Argo CD has synced, use the stable Network Load Balancer URL from
the `app_url` Terraform output (this fronts both workers, so it keeps
working even if traffic happens to land on either one):

```bash
curl $(terraform output -raw app_url)/
# EKART Application is Running! Version: 1
```

(You can also hit a specific worker directly at
`http://<worker-public-ip>:30070/` for debugging — the NLB is a
convenience, not a requirement.)

## 17. Making Version 2

Edit `app/src/main/java/com/ekart/EkartApplication.java`, change
`APP_VERSION` to `"2"`, commit, and push. Watch Jenkins build `:2`, push
it, update `kubernetes/deployment.yaml`, and push that change back.

## 18. Watching Argo CD deploy it

In the Argo CD UI, watch the Application go `OutOfSync → Syncing →
Synced`, and the pods roll from `:1` to `:2`. Then:

```bash
curl $(terraform output -raw app_url)/
# EKART Application is Running! Version: 2
```

## 19. Rollback

Two options:
- **Git-native**: revert the manifest commit and push — Argo CD syncs
  back automatically.
- **Argo CD UI/CLI**: use Argo CD's built-in history/rollback to an
  earlier synced revision.

## 20. Troubleshooting

- **Jenkins runs out of disk** — this is why the Jenkins EBS volume is
  30 GB; check `df -h` and clean old Docker images/build workspaces if it
  still fills up.
- **Worker won't join** — confirm the control plane's `6443` is reachable
  from the worker (same Security Group), then check
  `/var/log/ekart-bootstrap.log` on both the master (did it successfully
  `put-parameter`?) and the worker (is it stuck retrying `get-parameter`?).
  Tokens expire after 24h by default — if you're re-running a worker long
  after the master booted, re-run `kubeadm token create --print-join-command`
  on the master and `aws ssm put-parameter ... --overwrite` it yourself.
- **NLB target group shows unhealthy** — the health check hits
  `<worker>:30070/actuator/health`; confirm the Service's `nodePort`
  actually matches `30070` in both `kubernetes/service.yaml` and
  `terraform/infrastructure/loadbalancer.tf`, and that at least one pod is
  `Running`.
- **SonarQube crash-loops** — check `vm.max_map_count` was actually
  applied (`sysctl vm.max_map_count`), should be `262144`.
- **Argo CD shows OutOfSync forever** — check the Application's target
  repo/path/branch match this repo's `kubernetes/` folder exactly.
- **Jenkins re-triggers itself in a loop** — confirm the manifest commit
  message contains `[ci skip]` and that the pipeline's guard stage is
  actually finding it (`git log -1 --pretty=%B`).

## 21. AWS cleanup

```bash
cd terraform/infrastructure
terraform destroy

cd ../bootstrap
# only after you're fully done with the project — this removes the
# remote state bucket itself
terraform destroy
```

Double-check the EC2, EBS, and S3 consoles afterward — AWS EBS volumes,
public IPv4 addresses, and data transfer can incur charges even when an
instance itself is Free Tier eligible.

## Project layout

```
ekart-cicd/
├── app/                    Spring Boot source, pom.xml, Dockerfile
├── kubernetes/             deployment.yaml, service.yaml (watched by Argo CD)
├── argocd/                 application.yaml — tells Argo CD what to watch/sync
├── jenkins/                Jenkinsfile (the full pipeline)
├── terraform/
│   ├── bootstrap/          One-time: creates the S3 state bucket
│   └── infrastructure/     VPC, security groups, NLB, EC2 instances, user-data
└── scripts/                Helper scripts (get public IP, manual manifest update)
```
