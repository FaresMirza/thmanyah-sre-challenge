const express = require("express");
const multer = require("multer");
const axios = require("axios");
const FormData = require("form-data");
const fs = require("fs");
const path = require("path");

const router = express.Router();

// Use /tmp for uploads in container, or ./uploads locally
const uploadDir = process.env.NODE_ENV === "production" ? "/tmp/uploads" : path.join(__dirname, "../../uploads");

const log = (level, message) => {
  console.log(`[${new Date().toISOString()}] [API-SERVICE] ${level}: ${message}`);
};

// Ensure upload directory exists
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
  log('INFO', `Created upload directory: ${uploadDir}`);
}

const upload = multer({ dest: uploadDir });

const IMAGE_SERVICE_URL = process.env.IMAGE_SERVICE_URL || "http://image-service:5000";

router.post("/upload", upload.single("file"), async (req, res) => {
  const token = req.headers.authorization;
  
  if (!token) {
    log('WARN', `Upload attempt without authorization from ${req.ip}`);
    return res.status(401).json({ error: "Missing authorization token" });
  }

  if (!req.file) {
    log('WARN', `Upload attempt without file from ${req.ip}`);
    return res.status(400).json({ error: "No file uploaded" });
  }

  const filePath = req.file.path;
  const fileSize = req.file.size;
  const fileName = req.file.originalname;

  log('INFO', `Upload initiated: '${fileName}' (${fileSize} bytes) from ${req.ip}`);

  try {
    // Create form data with the file
    const formData = new FormData();
    formData.append("file", fs.createReadStream(filePath), {
      filename: req.file.originalname,
      contentType: req.file.mimetype,
    });

    // Forward to image-service with JWT token
    log('INFO', `Forwarding upload to image service: '${fileName}'`);
    const response = await axios.post(`${IMAGE_SERVICE_URL}/upload`, formData, {
      headers: {
        ...formData.getHeaders(),
        "Authorization": token,
      },
      maxContentLength: Infinity,
      maxBodyLength: Infinity,
    });

    // Build the full URL for retrieving the image
    const apiBaseUrl = process.env.API_BASE_URL || `http://localhost:${process.env.PORT || 3000}`;
    const filename = response.data.filename;
    const imageUrl = `${apiBaseUrl}/images/${filename}`;

    log('INFO', `Upload successful: '${fileName}' -> '${filename}' (${fileSize} bytes)`);
    res.json({
      message: "Uploaded successfully",
      filename: filename,
      url: imageUrl
    });
  } catch (err) {
    log('ERROR', `Upload failed for '${fileName}': ${err.message}`);
    console.error("Upload error:", err.message);
    
    if (err.response) {
      return res.status(err.response.status).json({ 
        error: err.response.data?.detail || "Failed to upload image" 
      });
    }
    
    res.status(500).json({ error: "Failed to upload image" });
  } finally {
    // Clean up temporary file
    fs.unlink(filePath, (err) => {
      if (err) {
        log('ERROR', `Failed to delete temporary file '${filePath}': ${err.message}`);
      } else {
        log('INFO', `Cleaned up temporary file: '${filePath}'`);
      }
    });
  }
});

module.exports = router;
