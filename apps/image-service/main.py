from fastapi import FastAPI, UploadFile, File, HTTPException, Header, Request
from fastapi.responses import StreamingResponse
import boto3, os, uuid, requests
import logging
import time
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [IMAGE-SERVICE] %(levelname)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

app = FastAPI()

# Environment variables
AUTH_URL = os.getenv("AUTH_SERVICE_URL")
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY")
MINIO_BUCKET = os.getenv("MINIO_BUCKET")

logger.info(f"Starting Image Service with configuration:")
logger.info(f"  Auth Service URL: {AUTH_URL}")
logger.info(f"  MinIO Endpoint: {MINIO_ENDPOINT}")
logger.info(f"  MinIO Bucket: {MINIO_BUCKET}")

# Initialize MinIO (S3) client
try:
    s3 = boto3.client(
        "s3",
        endpoint_url=f"http://{MINIO_ENDPOINT}",
        aws_access_key_id=MINIO_ACCESS_KEY,
        aws_secret_access_key=MINIO_SECRET_KEY,
    )
    logger.info("MinIO S3 client initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize MinIO S3 client: {e}")
    raise

# Ensure bucket exists on startup
try:
    s3.head_bucket(Bucket=MINIO_BUCKET)
    logger.info(f"Bucket '{MINIO_BUCKET}' exists and is accessible")
except Exception:
    try:
        s3.create_bucket(Bucket=MINIO_BUCKET)
        logger.info(f"Created new bucket '{MINIO_BUCKET}'")
    except Exception as e:
        logger.error(f"Failed to create bucket '{MINIO_BUCKET}': {e}")

# Middleware for request logging
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.time()
    
    # Skip logging for health check endpoints to reduce noise
    if request.url.path not in ["/healthz", "/livez"]:
        logger.info(f"Incoming request: {request.method} {request.url.path} from {request.client.host}")
    
    response = await call_next(request)
    
    process_time = time.time() - start_time
    if request.url.path not in ["/healthz", "/livez"]:
        logger.info(f"Completed: {request.method} {request.url.path} - Status: {response.status_code} - Duration: {process_time:.3f}s")
    
    return response

@app.get("/healthz")
def health():
    return {"status": "ok"}

@app.get("/livez")
def live():
    return {"status": "alive"}

@app.get("/list")
def list_images(authorization: str = Header(None)):
    """List all images in the MinIO bucket"""
    if not authorization:
        logger.warning(f"List images attempt without authorization")
        raise HTTPException(status_code=401, detail="Missing token")

    # Verify token with auth-service
    try:
        logger.debug(f"Verifying token with auth service for list images request")
        verify = requests.get(f"{AUTH_URL}/verify", headers={"Authorization": authorization}, timeout=2)
        if verify.status_code != 200:
            logger.warning(f"List images attempt with invalid token")
            raise HTTPException(status_code=401, detail="Invalid token")
    except requests.exceptions.Timeout:
        logger.error("Auth service timeout during list images verification")
        raise HTTPException(status_code=503, detail="Auth service timeout")
    except Exception as e:
        logger.error(f"Auth service error during list images: {e}")
        raise HTTPException(status_code=503, detail="Auth service unavailable")

    try:
        logger.info(f"Listing images from bucket '{MINIO_BUCKET}'")
        response = s3.list_objects_v2(Bucket=MINIO_BUCKET)
        
        if 'Contents' not in response:
            logger.info(f"No images found in bucket '{MINIO_BUCKET}'")
            return {"images": [], "count": 0}
        
        images = []
        for obj in response['Contents']:
            images.append({
                "filename": obj['Key'],
                "size": obj['Size'],
                "last_modified": obj['LastModified'].isoformat()
            })
        
        logger.info(f"Successfully listed {len(images)} images from bucket '{MINIO_BUCKET}'")
        return {"images": images, "count": len(images)}
    except Exception as e:
        logger.error(f"Error listing images: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to list images: {str(e)}")

@app.post("/upload")
def upload_image(file: UploadFile = File(...), authorization: str = Header(None)):
    client_ip = "unknown"
    if not authorization:
        logger.warning(f"Upload attempt without authorization from {client_ip}")
        raise HTTPException(status_code=401, detail="Missing token")

    # Verify JWT with auth-service
    try:
        logger.debug(f"Verifying token with auth service for upload request")
        verify = requests.get(f"{AUTH_URL}/verify", headers={"Authorization": authorization}, timeout=2)
        if verify.status_code != 200:
            logger.warning(f"Upload attempt with invalid token from {client_ip}")
            raise HTTPException(status_code=401, detail="Invalid token")
    except requests.exceptions.Timeout:
        logger.error("Auth service timeout during upload verification")
        raise HTTPException(status_code=503, detail="Auth service timeout")
    except Exception as e:
        logger.error(f"Auth service error during upload: {e}")
        raise HTTPException(status_code=503, detail="Auth service unavailable")

    # Generate unique file name
    file_id = str(uuid.uuid4())
    object_name = f"{file_id}_{file.filename}"
    file_size = 0

    try:
        # Get file size
        file.file.seek(0, 2)
        file_size = file.file.tell()
        file.file.seek(0)
        
        logger.info(f"Uploading file '{file.filename}' ({file_size} bytes) as '{object_name}' to MinIO")
        s3.upload_fileobj(file.file, MINIO_BUCKET, object_name)
        logger.info(f"Successfully uploaded '{object_name}' ({file_size} bytes) to bucket '{MINIO_BUCKET}'")
        return {"message": "Uploaded successfully", "filename": object_name, "size": file_size}
    except Exception as e:
        logger.error(f"Failed to upload file '{file.filename}': {e}")
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")

@app.get("/images/{filename}")
def get_image(filename: str, authorization: str = Header(None)):
    client_ip = "unknown"
    if not authorization:
        logger.warning(f"Image retrieval attempt without authorization for '{filename}' from {client_ip}")
        raise HTTPException(status_code=401, detail="Missing token")

    # Verify token with auth-service
    try:
        logger.debug(f"Verifying token with auth service for image retrieval")
        verify = requests.get(f"{AUTH_URL}/verify", headers={"Authorization": authorization}, timeout=2)
        if verify.status_code != 200:
            logger.warning(f"Image retrieval attempt with invalid token for '{filename}' from {client_ip}")
            raise HTTPException(status_code=401, detail="Invalid token")
    except requests.exceptions.Timeout:
        logger.error("Auth service timeout during image retrieval verification")
        raise HTTPException(status_code=503, detail="Auth service timeout")
    except Exception as e:
        logger.error(f"Auth service error during image retrieval: {e}")
        raise HTTPException(status_code=503, detail="Auth service unavailable")

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
        logger.info(f"Retrieving image '{filename}' from bucket '{MINIO_BUCKET}'")
        file_obj = s3.get_object(Bucket=MINIO_BUCKET, Key=filename)
        content_length = file_obj.get('ContentLength', 0)
        logger.info(f"Successfully retrieved '{filename}' ({content_length} bytes)")
        return StreamingResponse(
            file_obj["Body"], 
            media_type=media_type,
            headers={"Content-Disposition": f'inline; filename="{filename}"'}
        )
    except s3.exceptions.NoSuchKey:
        logger.warning(f"Image not found: '{filename}' in bucket '{MINIO_BUCKET}'")
        raise HTTPException(status_code=404, detail=f"Image '{filename}' not found")
    except Exception as e:
        logger.error(f"Error retrieving image '{filename}': {e}")
        raise HTTPException(status_code=500, detail=f"Failed to retrieve image: {str(e)}")
