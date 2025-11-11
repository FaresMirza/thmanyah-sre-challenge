const express = require("express");
const router = express.Router();
const { listImages, uploadImage } = require("../utils/imageClient");
const axios = require("axios");

const IMAGE_SERVICE_URL = process.env.IMAGE_SERVICE_URL || "http://image-service:5000";

// Get all images as HTML gallery
router.get("/", async (req, res) => {
  const token = req.headers.authorization;
  
  console.log('[IMAGES] Request received, token:', token ? 'present' : 'missing');
  
  if (!token) {
    return res.status(401).json({ error: "Missing authorization token" });
  }

  try {
    console.log('[IMAGES] Fetching image list...');
    const images = await listImages(token);
    const imageList = images.data.images;
    
    console.log('[IMAGES] Fetching', imageList.length, 'images as base64...');
    // Fetch all images as base64
    const imageDataPromises = imageList.map(async (img) => {
      try {
        const response = await axios.get(`${IMAGE_SERVICE_URL}/images/${img.filename}`, {
          headers: { Authorization: token },
          responseType: "arraybuffer",
        });
        const base64 = Buffer.from(response.data, 'binary').toString('base64');
        const contentType = response.headers['content-type'] || 'image/png';
        return {
          ...img,
          dataUrl: `data:${contentType};base64,${base64}`
        };
      } catch (err) {
        console.error(`[IMAGES] Failed to fetch image ${img.filename}:`, err.message);
        return {
          ...img,
          dataUrl: null
        };
      }
    });
    
    const imagesWithData = await Promise.all(imageDataPromises);
    console.log('[IMAGES] Successfully fetched', imagesWithData.filter(i => i.dataUrl).length, 'images');
    
    // Generate HTML gallery
    const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Image Gallery - Thmanyah</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        h1 {
            color: white;
            text-align: center;
            margin-bottom: 10px;
            font-size: 2.5rem;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
        }
        .count {
            color: rgba(255,255,255,0.9);
            text-align: center;
            margin-bottom: 40px;
            font-size: 1.1rem;
        }
        .gallery {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        .image-card {
            background: white;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
            cursor: pointer;
        }
        .image-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 40px rgba(0,0,0,0.4);
        }
        .image-wrapper {
            width: 100%;
            height: 250px;
            overflow: hidden;
            background: #f0f0f0;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .image-wrapper img {
            width: 100%;
            height: 100%;
            object-fit: cover;
            transition: transform 0.3s ease;
        }
        .image-card:hover .image-wrapper img {
            transform: scale(1.05);
        }
        .image-info {
            padding: 15px;
        }
        .filename {
            font-weight: 600;
            color: #333;
            margin-bottom: 8px;
            word-break: break-word;
            font-size: 0.9rem;
        }
        .metadata {
            display: flex;
            justify-content: space-between;
            font-size: 0.85rem;
            color: #666;
        }
        .size {
            color: #667eea;
            font-weight: 500;
        }
        .date {
            color: #764ba2;
        }
        .empty-state {
            text-align: center;
            color: white;
            padding: 60px 20px;
        }
        .empty-state h2 {
            font-size: 2rem;
            margin-bottom: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🖼️ Image Gallery</h1>
        <p class="count">Total Images: ${imagesWithData.length}</p>
        ${imagesWithData.length > 0 ? `
        <div class="gallery">
            ${imagesWithData.map(img => `
                <div class="image-card">
                    <div class="image-wrapper">
                        ${img.dataUrl ? 
                            `<img src="${img.dataUrl}" alt="${img.filename}">` :
                            `<div style="color: #f44;">Failed to load</div>`
                        }
                    </div>
                    <div class="image-info">
                        <div class="filename">${img.filename.split('_').slice(1).join('_') || img.filename}</div>
                        <div class="metadata">
                            <span class="size">${(img.size / 1024).toFixed(2)} KB</span>
                            <span class="date">${new Date(img.last_modified).toLocaleDateString()}</span>
                        </div>
                    </div>
                </div>
            `).join('')}
        </div>
        ` : `
        <div class="empty-state">
            <h2>No images yet</h2>
            <p>Upload your first image to get started!</p>
        </div>
        `}
    </div>
</body>
</html>
    `;
    
    res.setHeader('Content-Type', 'text/html');
    res.send(html);
  } catch (err) {
    console.error(err.message);
    if (err.response && err.response.status === 401) {
      return res.status(401).json({ error: "Invalid or expired token" });
    }
    res.status(500).json({ error: "Failed to fetch images" });
  }
});

// Upload new image (mock)
router.post("/upload", async (req, res) => {
  try {
    const result = await uploadImage(req.body);
    res.json(result.data);
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: "Upload failed" });
  }
});

module.exports = router;
