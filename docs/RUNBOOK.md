# Runbook: build, demo and tear down (do this in order)

Use **Azure Cloud Shell (Bash)** (portal toolbar icon `>_`) — it already has `az`, `terraform`, `kubectl`, `helm` and `git`,
so you install nothing. Upload or `git clone` this repo into it.

## Before you start (15 min)

1. **Pick the region where your quota lives** and keep it everywhere:
   `az vm list-usage -l centralindia -o table | grep -i -E "regional|Dn"`
   If `centralindia` shows no free quota, try `southindia`, `westindia`, `southeastasia`, then run every script with `LOCATION=<region>`.
2. **Check your billing currency** (Portal → Cost Management → Cost analysis). 17k credits on an Indian account is almost certainly **INR (≈ $200)**, not dollars.
   Set `budget_amount` accordingly (default 5000 = ₹5,000).
3. Create an **empty public GitHub repo** (no README) named e.g. `azure-aks-platform`. Do **not** push code yet.

## Phase 1 — Bootstrap (Day 1, ~30 min)

```bash
export LOCATION=centralindia          # your region
./scripts/00-preflight-and-bootstrap.sh
```
This fails fast if `Standard_D2nls_v6` is unavailable/restricted in the region — much better than failing 15 minutes into `terraform apply`.

> **If the node size is rejected by AKS** (D2nls_v6 is a *preview* VM series): change `aks_vm_size` in `terraform/envs/dev/variables.tf`
> to another 2-vCPU/4 GiB+ size you have quota for (e.g. `Standard_D2ls_v6`, `Standard_D2als_v6`) and re-run.

```bash
./scripts/01-setup-github-oidc.sh YOUR_GITHUB_USER/azure-aks-platform
gh variable set ALERT_EMAIL --repo YOUR_GITHUB_USER/azure-aks-platform --body "you@example.com"
# no gh CLI? The script prints the variables; add them in GitHub > Settings > Secrets and variables > Actions > Variables
```
In GitHub → Settings → **Environments**: create `dev` (no rules) and `prod` (tick **Required reviewers** → yourself).
Add repo secret `GRAFANA_ADMIN_PASSWORD` (any strong password).

Now push the code:
```bash
git init -b main && git add . && git commit -m "Initial platform" 
git remote add origin https://github.com/YOUR_GITHUB_USER/azure-aks-platform.git && git push -u origin main
```
The push triggers *Infrastructure* (terraform apply) automatically because `terraform/**` changed. Watch it in the Actions tab.
First apply takes ~10–15 min (AKS create, plus a deliberate 90 s wait for role-assignment propagation).

After the first successful run, **commit the lock file** that `terraform init` produced (`terraform/envs/dev/.terraform.lock.hcl`) — it pins provider versions.
(Download it from the workflow, or run `terraform init -backend-config=backend.hcl` once in Cloud Shell and commit it.)

## Phase 2 — Platform add-ons (Day 1/2, ~15 min)

Actions → **Platform add-ons (Gateway + monitoring)** → Run workflow.
Installs Envoy Gateway (Gateway API controller) and Prometheus + Grafana with Helm.

Verify (Cloud Shell: `az aks get-credentials -g rg-aksplat-dev -n aks-aksplat-dev`):
```bash
kubectl get nodes
kubectl top nodes                  # memory headroom - should stay well under 85%
kubectl get pods -A
kubectl get gatewayclass eg        # ACCEPTED = True
```

## Phase 3 — Deploy the app (~10 min)

Actions → **Build and deploy** → Run workflow → `dev`. The run summary prints the public URL.
```bash
curl http://<IP>/            # service info + pod name
curl http://<IP>/config-check   # {"api_key_loaded":true,...}  <- proves Key Vault -> CSI -> pod works
curl -X POST http://<IP>/items -H 'content-type: application/json' -d '{"name":"demo","quantity":2}'
```
Every later push to `main` touching `app/` or `k8s/` redeploys automatically. Prod: run the same workflow with `prod` → waits for your approval.

## Phase 4 — Capture your demo (record this!)

```bash
kubectl -n demo-dev get hpa,pods                          # 1 replica
./scripts/load-test.sh start                              # 4 load pods
kubectl -n demo-dev get hpa,pods -w                       # watch it scale to 3
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80   # open the "AKS Platform API" dashboard
./scripts/load-test.sh stop
```
Capture: pipeline runs (green), PR with the Terraform plan comment (open a small PR to get one), Grafana dashboard while scaling, `kubectl get hpa -w`, budget in the portal, the architecture diagram. **Do this before day 5.**

Make a PR on purpose: change `replicas` in `k8s/overlays/dev`, or add a tag in Terraform → shows plan-on-PR and review flow.

## Phase 5 — Azure DevOps copy (stretch, only after everything above is recorded)

Follow the header comments in `azure-devops/azure-pipelines.yml` (service connection with workload identity federation, 3 pipeline variables).
Run it once successfully before listing "Azure DevOps" on your resume.

## Phase 6 — Teardown (before your subscription ends)

```bash
./scripts/teardown.sh       # or: Actions -> Infrastructure -> destroy
```
Confirm in the portal that no `rg-aksplat-*` and no `MC_*` resource groups remain. Keep the repo — it rebuilds everything from scratch.

## Troubleshooting cheatsheet

| Symptom | Likely cause / fix |
|---|---|
| `QuotaExceeded` / `vCPU` error | Region has < 4 free vCPUs for the family or in *Total Regional vCPUs*. Change `LOCATION` or VM family. |
| Pods `Pending` with `Insufficient memory/cpu` | Cluster is full. `kubectl describe node`; lower Prometheus requests in `monitoring/kube-prometheus-stack-values.yaml`, or skip monitoring until after the app demo. |
| App unreachable but pods Ready | Check `kubectl -n demo-dev get gateway,httproute` (Programmed/Accepted?). To rule out NetworkPolicy: `kubectl -n demo-dev delete networkpolicy default-deny-ingress` temporarily. |
| `config-check` says `api_key_loaded:false` / pod stuck `ContainerCreating` | CSI mount failed: `kubectl -n demo-dev describe pod <pod>`. Usually role assignment not propagated yet (wait 2 min, restart pod) or wrong `CSI_CLIENT_ID`. |
| Terraform `403` writing Key Vault secret | RBAC propagation delay; re-run apply. If you apply locally *and* in CI, set `TF_VAR_extra_kv_admin_object_ids` (printed by script 01). |
| `terraform apply` AuthorizationFailed on role assignment | CI service principal lacks *User Access Administrator* on the subscription (script 01 grants it). |
| Workflow fails at "Azure login" with `AADSTS70021` | Federated credential subject doesn't match. Jobs using `environment: dev` need the `environment:dev` credential (script 01 creates it). |
| `helm install` times out | Nodes are memory-starved; see Pending row. |

## Cost guide (indicative — check the portal)

2 × D2nls_v6 ≈ $165/month → about **$5.50/day**, plus Standard LB/public IP ≈ $0.5–1/day, ACR Basic ≈ $0.17/day, state storage pennies.
Five days ≈ **$30–35 (≈ ₹2,500–3,000)** — comfortably inside ₹17k. The Budget module emails you at 50/80/100%.
