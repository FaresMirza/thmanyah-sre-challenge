const express = require("express");
const router = express.Router();

const authRoutes = require("./auth");
const imageRoutes = require("./images");

router.get("/ping", (req, res) => {
  res.json({ status: "ok", service: "api-service" });
});

router.use("/auth", authRoutes);
router.use("/images", imageRoutes);

module.exports = router;
