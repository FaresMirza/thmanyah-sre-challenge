# 🖼️ Image Service

This service handles file uploads to MinIO (S3-compatible) storage.
It verifies JWT tokens internally with the `auth-service`.

## Endpoints
- `POST /upload` → Upload file (requires Authorization header)
- `GET /healthz` → Health check

## Environment Variables
| Variable | Description |
|-----------|--------------|
| `AUTH_SERVICE_URL` | Internal URL for auth-service |
| `MINIO_ENDPOINT` | Host:Port for MinIO |
| `MINIO_ACCESS_KEY` | MinIO username |
| `MINIO_SECRET_KEY` | MinIO password |
| `MINIO_BUCKET` | Bucket name (must exist) |

## Example
```bash
curl -X POST http://localhost:5000/upload \
  -H "Authorization: Bearer <JWT_TOKEN>" \
  -F "file=@test.png"
```

---

### ✅ Environment variables (in `kind` or Kubernetes)
```yaml
env:
  - name: AUTH_SERVICE_URL
    value: "http://auth-service:4000"
  - name: MINIO_ENDPOINT
    value: "minio:9000"
  - name: MINIO_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: minio-secret
        key: accesskey
  - name: MINIO_SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: minio-secret
        key: secretkey
  - name: MINIO_BUCKET
    value: "images"
```
