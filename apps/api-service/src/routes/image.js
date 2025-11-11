const express = require("express");
const axios = require("axios");
const path = require("path");

const router = express.Router();
const IMAGE_SERVICE_URL = process.env.IMAGE_SERVICE_URL || "http://image-service:5000";

// Helper to determine content type from filename
function getContentType(filename) {
  const ext = path.extname(filename).toLowerCase();
  const mimeTypes = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.svg': 'image/svg+xml',
    '.bmp': 'image/bmp',
  };
  return mimeTypes[ext] || 'application/octet-stream';
}

router.get("/images/:filename", async (req, res) => {
  const token = req.headers.authorization;
  
  if (!token) {
    return res.status(401).json({ error: "Missing authorization token" });
  }

  const { filename } = req.params;

  try {
    const response = await axios.get(`${IMAGE_SERVICE_URL}/images/${filename}`, {
      headers: { Authorization: token },
      responseType: "stream",
    });

    // Set proper content type based on file extension
    const contentType = response.headers["content-type"] || getContentType(filename);
    res.setHeader("Content-Type", contentType);
    res.setHeader("Content-Disposition", `inline; filename="${filename}"`);
    
    // Pipe the image stream to the response
    response.data.pipe(res);
  } catch (error) {
    console.error("Image fetch error:", error.message);
    
    if (error.response) {
      return res.status(error.response.status).json({ 
        error: error.response.data?.detail || "Failed to fetch image" 
      });
    }
    
    res.status(500).json({ error: "Failed to fetch image" });
  }
});

module.exports = router;
