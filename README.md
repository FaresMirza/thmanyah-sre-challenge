# Thmanyah SRE Challenge - تحدي الموثوقية

## نظرة عامة

هذا المشروع يوضح بناء ونشر بيئة Kubernetes كاملة باستخدام GitOps (ArgoCD) مع نظام مراقبة شامل (Prometheus + Grafana + Alertmanager) وإدارة الأسرار (Sealed Secrets) واختبار سيناريوهات الفشل.

### المكونات الأساسية

- **Kubernetes Cluster**: Kind (Kubernetes in Docker)
- **GitOps**: ArgoCD للنشر المستمر
- **Monitoring Stack**: Prometheus, Grafana, Alertmanager
- **Applications**:
  - API Service (Node.js)
  - Auth Service (Go)
  - Image Service (Python)
  - PostgreSQL Database
  - MinIO Object Storage
- **Security**: Sealed Secrets, Network Policies, RBAC
- **High Availability**: HPA, PDB, Resource Limits

---

## 1️⃣ كيف بنيت ونشرت البيئة بالتفصيل

### المتطلبات الأساسية

```bash
# الأدوات المطلوبة
- Docker Desktop
- kubectl
- kind (سيتم تثبيته تلقائياً)
- kubeseal (سيتم تثبيته تلقائياً)
- Git
```

### خطوات البناء والنشر

#### الخطوة 1: إنشاء الكلاستر

```bash
cd scripts
./01-provision-cluster.sh
```

**ما يحدث داخلياً:**
- يفحص وجود `kind`، إذا لم يكن موجوداً يثبّته تلقائياً (macOS/Linux/Windows)
- يفحص وجود `kubectl`، يثبّته إذا لزم الأمر
- ينشئ كلاستر Kubernetes محلي باستخدام Kind مع:
  - 1 Control Plane Node
  - 2 Worker Nodes
  - Port mappings للوصول للخدمات (80, 443, 30000-30010)
  - Extra mounts للتخزين الدائم
- يفعّل Ingress Controller
- ينتظر حتى تصبح جميع الـ nodes جاهزة

**الملف المستخدم:** `scripts/config/kind-config.yaml`

#### الخطوة 2: تثبيت ArgoCD والأدوات المساعدة

```bash
./02-install-argocd.sh
```

**ما يحدث داخلياً:**
- ينشئ namespace `argocd`
- يثبّت ArgoCD من المانيفست الرسمي
- يثبّت Sealed Secrets Controller لتشفير الأسرار
- يثبّت Metrics Server (مع patch لـ Kind)
- ينتظر جاهزية جميع المكونات
- يعرض:
  - ArgoCD Admin Password
  - طريقة الوصول للواجهة الرسومية
  - خطوات تثبيت `kubeseal`

**الوصول لـ ArgoCD (Port Forwarding):**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# ثم افتح: https://localhost:8080
# Username: admin
# Password: (يظهر في نهاية السكربت)
```

> **ملاحظة:** ArgoCD غير معروض عبر Ingress لأسباب أمنية. استخدم port-forward للوصول.

#### الخطوة 3: إنشاء وتشفير الأسرار

```bash
./03-create-secrets.sh
```

**ما يحدث داخلياً:**
- ينشئ Docker registry credentials للـ container images
- ينشئ secrets للخدمات:
  - PostgreSQL: `POSTGRES_PASSWORD`
  - MinIO: `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`
  - Auth Service: `JWT_SECRET`
  - Grafana: `GF_SECURITY_ADMIN_PASSWORD`
  - Alertmanager: `SLACK_WEBHOOK_URL`, `SLACK_CHANNEL`
- يشفّر جميع الـ secrets باستخدام Sealed Secrets
- يحفظ الـ Sealed Secrets في المجلدات المناسبة تحت `infra/thmanyah/`

**الملفات المنتجة:**
```
infra/thmanyah/
├── api/regcred-sealed.yaml & sealed-secret.yaml
├── auth/regcred-sealed.yaml & sealed-secret.yaml
├── image/regcred-sealed.yaml & sealed-secret.yaml
├── db/sealed-secret.yaml
├── minio/sealed-secret.yaml
├── grafana/sealed-secret.yaml
└── prometheus/alertmanager-sealed-secret.yaml
```

#### الخطوة 4: نشر التطبيقات عبر ArgoCD

```bash
./04-deploy-apps.sh
```

**ما يحدث داخلياً:**

##### 1. تطبيق ApplicationSet
السكربت يطبّق `infra/thmanyah-applicationset.yaml` على الكلاستر:
```bash
kubectl apply -f ../infra/thmanyah-applicationset.yaml
```

##### 2. كيف يعمل ApplicationSet
```yaml
# المولّد (Generator): يبحث في Git Repository
generators:
  - git:
      repoURL: https://github.com/FaresMirza/thmanyah-sre-challenge.git
      revision: main
      directories:
        - path: infra/thmanyah/*  # يكتشف كل مجلد تلقائياً

# القالب (Template): ينشئ Application لكل مجلد
template:
  metadata:
    name: '{{path.basename}}-app'  # مثلاً: api-app, db-app, prometheus-app
  spec:
    destination:
      namespace: '{{path.basename}}-ns'  # مثلاً: api-ns, db-ns
    source:
      path: '{{path}}'  # المسار الكامل للمجلد
```

##### 3. النتيجة
ArgoCD ينشئ **Application منفصل** لكل مجلد:
- `api-app` → ينشر محتويات `infra/thmanyah/api/` إلى `api-ns`
- `auth-app` → ينشر محتويات `infra/thmanyah/auth/` إلى `auth-ns`
- `image-app` → ينشر محتويات `infra/thmanyah/image/` إلى `image-ns`
- `db-app` → ينشر محتويات `infra/thmanyah/db/` إلى `data-ns`
- `prometheus-app` → ينشر محتويات `infra/thmanyah/prometheus/` إلى `prometheus-ns`
- `grafana-app` → ينشر محتويات `infra/thmanyah/grafana/` إلى `grafana-ns`
- `minio-app` → ينشر محتويات `infra/thmanyah/minio/` إلى `minio-ns`
- `ingress-app` → ينشر محتويات `infra/thmanyah/ingress/` إلى `ingress-ns`

##### 4. الإعدادات الذكية

**Auto-Sync و Self-Heal:**
```yaml
syncPolicy:
  automated:
    prune: true      # يحذف الموارد الزائدة
    selfHeal: true   # يصلح التغييرات اليدوية تلقائياً
```

**تجاهل replicas (للسماح بـ HPA):**
```yaml
ignoreDifferences:
  - kind: Deployment
    jsonPointers:
      - /spec/replicas  # يتجاهل تغييرات عدد النسخ
  - kind: StatefulSet
    jsonPointers:
      - /spec/replicas
```

**لماذا نتجاهل replicas؟**
- ✅ HPA يحتاج تغيير `replicas` ديناميكياً
- ✅ سيناريوهات الفشل تحتاج scale يدوي
- ✅ بدون ignore، ArgoCD سيرجع `replicas` للقيمة في Git

##### 5. ما يتم نشره

**Data Layer:**
- PostgreSQL StatefulSet (قاعدة البيانات)
- MinIO Deployment (Object Storage)
- PVCs للتخزين الدائم

**Application Services:**
- API Service (Node.js)
- Auth Service (Go)
- Image Service (Python)

**Monitoring Stack:**
- Prometheus (المراقبة)
- Alertmanager (الإشعارات)
- Grafana (الـ Dashboards)

**Infrastructure:**
- Nginx Ingress Controller
- Network Policies (عزل الشبكة)
- RBAC (الصلاحيات)
- PDB (الحماية من الانقطاع)
- HPA (التوسع التلقائي)

**التحقق من النشر:**
```bash
# 1. التحقق من Applications في ArgoCD
kubectl get applications -n argocd
# يجب أن ترى 8-10 applications

# 2. التحقق من حالة كل Application
kubectl get applications -n argocd -o wide
# Health: Healthy, Sync: Synced

# 3. عرض تفاصيل Application معين
kubectl get application api-app -n argocd -o yaml

# 4. التحقق من الـ Pods
kubectl get pods -A
# يجب أن ترى pods في جميع الـ namespaces

# 5. التحقق من الـ Services
kubectl get svc -A

# 6. التحقق من الـ Ingress
kubectl get ingress -A

# 7. مشاهدة ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# افتح: https://localhost:8080
# ستشاهد جميع الـ Applications مع حالتها
```

**ماذا يحدث إذا غيّرت ملف في Git؟**
1. تعمل commit و push للتغيير
2. ArgoCD يكتشف التغيير خلال 3 دقائق (أو فوري مع webhook)
3. يقارن الحالة الحالية مع Git
4. يطبّق التغييرات تلقائياً (Auto-Sync)
5. تشوف التحديث في الـ UI

### البنية التحتية كـ Code (GitOps)

```
infra/
├── thmanyah-applicationset.yaml      # ApplicationSet الرئيسي
└── thmanyah/
    ├── api/                          # API Service
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── ingress.yaml
    │   ├── hpa.yaml
    │   ├── pdb.yaml
    │   ├── networkpolicy.yaml
    │   └── sealed-secrets
    ├── auth/                         # Auth Service
    ├── image/                        # Image Service
    ├── db/                           # PostgreSQL
    │   ├── statefulset.yaml
    │   ├── service.yaml
    │   ├── pvc.yaml
    │   └── networkpolicy.yaml
    ├── minio/                        # Object Storage
    ├── prometheus/                   # Monitoring
    │   ├── deployment.yaml
    │   ├── configmap.yaml
    │   ├── alerts.yaml
    │   ├── rbac.yaml
    │   └── alertmanager-*
    ├── grafana/                      # Dashboards
    │   ├── deployment.yaml
    │   ├── dashboards-configmap.yaml
    │   └── ingress.yaml
    └── ingress/                      # Nginx Ingress Controller
```

### استراتيجية الـ High Availability

#### 1. Horizontal Pod Autoscaler (HPA)
```yaml
# مثال: API Service HPA
minReplicas: 2
maxReplicas: 5
metrics:
  - CPU: 70%
  - Memory: 80%
```

#### 2. Pod Disruption Budget (PDB)
```yaml
# يضمن توفر replica واحد على الأقل أثناء الصيانة
minAvailable: 1
```

#### 3. Network Policies
- عزل الشبكة بين الـ namespaces
- السماح فقط بالاتصالات المطلوبة
- حماية قاعدة البيانات من الوصول المباشر

#### 4. Resource Limits
```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

---

## 2️⃣ خطوات محاكاة الفشل والتحقق من التعافي

### السيناريوهات المتاحة

تحت مجلد `scripts/failure-scenarios/` توجد سكربتات لمحاكاة سيناريوهات فشل مختلفة:

#### السيناريو 1: حمل عالي على خدمة الصور 📈

```bash
cd scripts/failure-scenarios
./01-image-service-stress.sh
```

**ما يحدث:**
- يرسل 1000 طلب HTTP متزامن لخدمة الصور
- يستخدم أداة `hey` لتوليد الحمل
- يقيس:
  - Response time
  - Success rate
  - Requests per second

**ما يجب مراقبته:**
```bash
# مراقبة HPA
kubectl get hpa -n image-ns -w

# مراقبة الـ Pods
kubectl get pods -n image-ns -w

# مراقبة الـ Metrics
kubectl top pods -n image-ns
```

**النتيجة المتوقعة:**
- ✅ HPA يكتشف الحمل العالي
- ✅ يزيد عدد الـ replicas تلقائياً (من 2 إلى 5 max)
- ✅ Prometheus يرسل alert: `ImageServiceHighLoad`
- ✅ بعد انتهاء الحمل، HPA يقلل الـ replicas تدريجياً

**التحقق من Prometheus:**
```bash
# Prometheus عبر Port Forward فقط:
kubectl port-forward -n prometheus-ns svc/prometheus 9090:9090
# افتح: http://localhost:9090
# Query: kube_horizontalpodautoscaler_status_current_replicas{namespace="image-ns"}
```

---

#### السيناريو 2: توقف قاعدة البيانات 🔴

```bash
./02-db-down.sh
```

**ما يحدث:**
- يعمل scale للـ StatefulSet `db` إلى 0 replicas
- قاعدة البيانات تتوقف بالكامل

**ما يجب مراقبته:**
```bash
# مراقبة StatefulSet
kubectl get sts -n data-ns -w

# مراقبة Pods
kubectl get pods -n data-ns -w

# مراقبة الخدمات المتأثرة
kubectl get pods -n api-ns -w
kubectl get pods -n auth-ns -w
kubectl get pods -n image-ns -w
```

**النتيجة المتوقعة:**
- 🔴 قاعدة البيانات تتوقف فوراً
- 🔴 API Service يفشل في الاتصال بقاعدة البيانات
- 🔴 Auth Service يفشل
- 📬 **Alerts المتوقعة في Prometheus/Slack:**
  - `PostgreSQLDown` (critical)
  - `ServiceDown` (critical)
  - `APIHighErrorRate` (critical)
  - `AuthServiceHighErrorRate` (critical)

**التعافي:**
```bash
# استعادة قاعدة البيانات
kubectl scale statefulset db --replicas=1 -n data-ns

# مراقبة التعافي
kubectl rollout status statefulset/db -n data-ns
kubectl get pods -n data-ns
```

**زمن التعافي المتوقع:**
- Database pod: ~30-60 ثانية
- Application services: ~10-20 ثانية بعد عودة DB
- Alerts resolution: ~30 ثانية بعد التعافي

---

#### السيناريو 3: تعطيل خدمة 🛑

```bash
# تعطيل API service
./03-service-down.sh api

# أو تعطيل Auth service
./03-service-down.sh auth

# أو تعطيل Image service
./03-service-down.sh image
```

**ما يحدث:**
- يعمل scale للـ Deployment إلى 0 replicas
- الخدمة تتوقف بالكامل

**النتيجة المتوقعة:**
- 🔴 الخدمة المحددة تتوقف
- 🔴 الخدمات الأخرى التي تعتمد عليها تفشل
- 📬 **Alerts المتوقعة:**
  - `ServiceDown` (critical)
  - `HighErrorRate` (critical)
  - `PodNotReady` (warning)

**التعافي:**
```bash
# مثال: استعادة API service
kubectl scale deployment api --replicas=2 -n api-ns

# أو دع HPA يتعامل معها (إذا كان هناك حمل)
```

**ملاحظة مهمة:**
- لأن ArgoCD مضبوط على تجاهل `replicas` للـ Deployments
- يمكنك عمل scale يدوياً دون أن يعيدها ArgoCD
- HPA لن يرجعها تلقائياً لأنه لا يوجد حمل (الخدمة معطلة)

---

### التحقق من الـ Alerts

#### 1. Slack Notifications (الطريقة الأساسية) 📱

**التهيئة:**
```bash
# في سكربت 03-create-secrets.sh، تأكد من إضافة:
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
SLACK_CHANNEL="#alerts"  # أو أي قناة تفضلها
```

**كيف يعمل:**
1. Prometheus يكتشف المشكلة ويطلق الـ alert
2. Alertmanager يستقبل الـ alert
3. Alertmanager يرسل إشعار **مباشرة** إلى Slack (بدون port forward!)
4. تستقبل الرسالة في القناة المحددة خلال ثوانٍ

**شكل الرسالة في Slack:**
```
🔴 [FIRING:1] PostgreSQLDown critical
PostgreSQL database is down
PostgreSQL has been unreachable for more than 2 minutes.

Labels:
  • alertname: PostgreSQLDown
  • severity: critical
  • component: database
```

**المميزات:**
- ✅ إشعارات فورية (لا حاجة لفتح الـ browser)
- ✅ تعمل 24/7 تلقائياً
- ✅ يمكن إعداد Slack mobile app للإشعارات الفورية
- ✅ Alert يُحل تلقائياً عندما تعود الخدمة (رسالة خضراء ✅)

---

#### 2. Prometheus UI (للفحص التفصيلي)
```bash
# Prometheus ليس له Ingress - استخدم Port Forward
kubectl port-forward -n prometheus-ns svc/prometheus 9090:9090
# افتح: http://localhost:9090/alerts
```

**متى تستخدمه:**
- التحقق من Alerts rules
- كتابة PromQL queries مخصصة
- مراجعة metrics history

---

#### 3. Grafana Dashboards (للتحليل المرئي)
```bash
# الطريقة 1: عبر Ingress (موصى بها)
# أضف thmanyah.local للـ hosts file (إذا لم تضفه من قبل):
echo "127.0.0.1 thmanyah.local" | sudo tee -a /etc/hosts

# افتح المتصفح:
# https://thmanyah.local/grafana

# الطريقة 2: Port Forward (بديل)
kubectl port-forward -n prometheus-ns svc/grafana 3000:3000
# افتح: http://localhost:3000
# Username: admin
# Password: (تحقق من sealed-secret)
```

**Dashboards المتاحة:**
- Kubernetes Cluster Overview
- Application Performance Monitoring
- Database Metrics
- HPA & Autoscaling

**متى تستخدمه:**
- عرض graphs و dashboards
- تحليل الأداء التاريخي
- عمل correlation بين metrics مختلفة

---

#### 4. Alertmanager UI (اختياري)
```bash
# الطريقة 1: عبر Ingress (إذا كان مضبوط)
# https://thmanyah.local/alertmanager

# الطريقة 2: Port Forward
kubectl port-forward -n prometheus-ns svc/alertmanager 9093:9093
# افتح: http://localhost:9093
```

**متى تستخدمه:**
- مشاهدة الـ alerts النشطة
- Silence alerts مؤقتاً (أثناء الصيانة)
- التحقق من routing rules

---

### ملخص طرق الوصول للخدمات

| الخدمة | الطريقة المفضلة | البديل |
|--------|-----------------|--------|
| **Slack Alerts** | ✅ تلقائي (بدون تدخل) | - |
| **API Service** | `https://thmanyah.local/api/*` | - |
| **Grafana** | `https://thmanyah.local/grafana` | Port-forward 3000 |
| **Prometheus** | Port-forward 9090 (فقط) | - |
| **ArgoCD** | Port-forward 8080 (أمني) | - |
| **Alertmanager** | Port-forward 9093 | - |

**API Endpoints المتاحة:**
- `GET  /api/ping` - Health check
- `GET  /healthz` - Kubernetes readiness
- `GET  /livez` - Kubernetes liveness
- `GET  /metrics` - Prometheus metrics
- `POST /register` - User registration
- `POST /login` - User login
- `GET  /private` - Protected route (requires auth)
- `POST /upload` - Upload image
- `GET  /images` - List all images
- `GET  /images/:filename` - Get specific image

> **ملاحظة:** تأكد من إضافة `127.0.0.1 thmanyah.local` في `/etc/hosts` (Linux/Mac) أو `C:\Windows\System32\drivers\etc\hosts` (Windows)

---

## 3️⃣ كيف يمكن إعادة إنتاج التجربة

### البداية من الصفر

```bash
# 1. استنساخ المشروع
git clone https://github.com/FaresMirza/thmanyah-sre-challenge.git
cd thmanyah-sre-challenge

# 2. تشغيل السكربتات بالترتيب
cd scripts

# إنشاء الكلاستر
./01-provision-cluster.sh

# تثبيت ArgoCD والأدوات
./02-install-argocd.sh

# إنشاء الأسرار (عدّل القيم حسب الحاجة)
./03-create-secrets.sh

# نشر التطبيقات
./04-deploy-apps.sh

# 3. انتظر حتى تصبح جميع الـ pods جاهزة
kubectl get pods -A

# 4. إضافة thmanyah.local للـ hosts
echo "127.0.0.1 thmanyah.local" | sudo tee -a /etc/hosts

# 5. الوصول للخدمات
# Grafana
open https://thmanyah.local/grafana

# API Service
curl https://thmanyah.local/api/ping -k

# ArgoCD (Port Forward فقط)
kubectl port-forward svc/argocd-server -n argocd 8080:443
open https://localhost:8080

# Prometheus (Port Forward فقط)
kubectl port-forward -n prometheus-ns svc/prometheus 9090:9090
open http://localhost:9090

# 6. اختبار سيناريوهات الفشل
cd failure-scenarios
./02-db-down.sh
```

### المتطلبات المسبقة

#### macOS
```bash
# تثبيت Docker Desktop
brew install --cask docker

# باقي الأدوات ستثبت تلقائياً عبر السكربتات
```

#### Linux
```bash
# تثبيت Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# باقي الأدوات ستثبت تلقائياً عبر السكربتات
```

#### Windows
```powershell
# تثبيت Docker Desktop
# من: https://www.docker.com/products/docker-desktop

# تثبيت WSL2
wsl --install

# باقي الأدوات ستثبت تلقائياً عبر السكربتات
```

### تخصيص البيئة

#### تغيير عدد الـ Nodes
عدّل `scripts/config/kind-config.yaml`:
```yaml
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker  # أضف المزيد
```

#### تخصيص الـ Resources
عدّل الـ deployments في `infra/thmanyah/`:
```yaml
resources:
  requests:
    cpu: 200m      # زيادة CPU
    memory: 256Mi  # زيادة Memory
  limits:
    cpu: 1000m
    memory: 1Gi
```

#### تخصيص الـ HPA
عدّل `infra/thmanyah/*/hpa.yaml`:
```yaml
minReplicas: 3     # زيادة الحد الأدنى
maxReplicas: 10    # زيادة الحد الأقصى
targetCPUUtilizationPercentage: 60  # تقليل العتبة
```

#### تخصيص الـ Alerts
عدّل `infra/thmanyah/prometheus/alerts.yaml`:
```yaml
- alert: APIHighErrorRate
  expr: |
    (sum(rate(http_requests_total{job="api-service",status_code=~"5.."}[5m])) by (instance) 
    / sum(rate(http_requests_total{job="api-service"}[5m])) by (instance)) > 0.02  # عتبة أقل
  for: 0s  # إطلاق فوري
```

## الخلاصة

هذا المشروع يوضح:
- ✅ بناء بيئة Kubernetes كاملة من الصفر
- ✅ GitOps باستخدام ArgoCD
- ✅ مراقبة شاملة مع Prometheus/Grafana
- ✅ أمان متعدد الطبقات
- ✅ اختبار سيناريوهات الفشل
- ✅ استراتيجيات التعافي

**الهدف النهائي:**
بناء نظام موثوق، قابل للتوسع، وآمن، مع القدرة على التعافي التلقائي من الفشل.

---

## الموارد المفيدة

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Kind Documentation](https://kind.sigs.k8s.io/)


**Made By Eng.Fares Mirza**
