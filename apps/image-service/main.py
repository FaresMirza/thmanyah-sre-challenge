from fastapi import FastAPI, UploadFile, File, HTTPException, Header
from fastapi.responses import StreamingResponse
import boto3, os, uuid, requests

app = FastAPI()

# Environment variables
AUTH_URL = os.getenv("AUTH_SERVICE_URL")
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY")
MINIO_BUCKET = os.getenv("MINIO_BUCKET")

# Initialize MinIO (S3) client
s3 = boto3.client(
    "s3",
    endpoint_url=f"http://{MINIO_ENDPOINT}",
    aws_access_key_id=MINIO_ACCESS_KEY,
    aws_secret_access_key=MINIO_SECRET_KEY,
)

@app.get("/healthz")
def health():
    return {"status": "ok"}

@app.post("/upload")
def upload_image(file: UploadFile = File(...), authorization: str = Header(None)):
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing token")

    # Verify JWT with auth-service
    try:
        verify = requests.get(f"{AUTH_URL}/verify", headers={"Authorization": authorization}, timeout=2)
        if verify.status_code != 200:
            raise HTTPException(status_code=401, detail="Invalid token")
    except Exception:
        raise HTTPException(status_code=401, detail="Auth service unavailable")

    # Generate unique file name
    file_id = str(uuid.uuid4())
    object_name = f"{file_id}_{file.filename}"

    try:
        s3.upload_fileobj(file.file, MINIO_BUCKET, object_name)
        return {"message": "Uploaded successfully", "filename": object_name}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

@app.get("/images/{filename}")
def get_image(filename: str, authorization: str = Header(None)):
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing token")

    # Verify token with auth-service
    try:
        verify = requests.get(f"{AUTH_URL}/verify", headers={"Authorization": authorization}, timeout=2)
        if verify.status_code != 200:
            raise HTTPException(status_code=401, detail="Invalid token")
    except Exception:
        raise HTTPException(status_code=401, detail="Auth service unavailable")

    # Determine content type from file extension
    ext = filename.lower().split('.')[-1]
    content_type_map = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'svg': 'image/svg+xml',
        'bmp': 'image/bmp'
    }
    media_type = content_type_map.get(ext, 'application/octet-stream')

    try:
        file_obj = s3.get_object(Bucket=MINIO_BUCKET, Key=filename)
        return StreamingResponse(
            file_obj["Body"], 
            media_type=media_type,
            headers={"Content-Disposition": f'inline; filename="{filename}"'}
        )
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Image not found: {str(e)}")
