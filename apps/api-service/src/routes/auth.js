const express = require("express");
const router = express.Router();
const { verifyToken } = require("../utils/authClient");

// Validate token
router.get("/verify", async (req, res) => {
  const token = req.headers.authorization;
  if (!token) return res.status(401).json({ error: "Missing Authorization token" });

  try {
    const result = await verifyToken(token);
    res.json({ status: "success", user: result.data.user });
  } catch (err) {
    console.error(err.message);
    res.status(401).json({ error: "Invalid token" });
  }
});

module.exports = router;
