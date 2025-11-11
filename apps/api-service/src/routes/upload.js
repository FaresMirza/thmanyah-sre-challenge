const express = require("express");
const multer = require("multer");
const axios = require("axios");
const FormData = require("form-data");
const fs = require("fs");
const path = require("path");

const router = express.Router();

// Use /tmp for uploads in container, or ./uploads locally
const uploadDir = process.env.NODE_ENV === "production" ? "/tmp/uploads" : path.join(__dirname, "../../uploads");

// Ensure upload directory exists
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const upload = multer({ dest: uploadDir });

const IMAGE_SERVICE_URL = process.env.IMAGE_SERVICE_URL || "http://image-service:5000";

router.post("/upload", upload.single("file"), async (req, res) => {
  const token = req.headers.authorization;
  
  if (!token) {
    return res.status(401).json({ error: "Missing authorization token" });
  }

  if (!req.file) {
    return res.status(400).json({ error: "No file uploaded" });
  }

  const filePath = req.file.path;

  try {
    // Create form data with the file
    const formData = new FormData();
    formData.append("file", fs.createReadStream(filePath), {
      filename: req.file.originalname,
      contentType: req.file.mimetype,
    });

    // Forward to image-service with JWT token
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

    res.json({
      message: "Uploaded successfully",
      filename: filename,
      url: imageUrl
    });
  } catch (err) {
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
      if (err) console.error("Failed to delete temp file:", err);
    });
  }
});

module.exports = router;
