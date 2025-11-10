const express = require("express");
const router = express.Router();
const { listImages, uploadImage } = require("../utils/imageClient");

// Get all images
router.get("/", async (req, res) => {
  try {
    const images = await listImages();
    res.json(images.data);
  } catch (err) {
    console.error(err.message);
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
