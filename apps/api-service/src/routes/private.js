const express = require("express");
const router = express.Router();
const { verifyToken } = require("../utils/authClient");

router.get("/", async (req, res) => {
  const token = req.headers.authorization;
  if (!token) return res.status(401).json({ error: "Missing token" });

  try {
    const result = await verifyToken(token);
    if (result.valid === "true") {
      res.json({ message: "Access granted ✅" });
    } else {
      res.status(401).json({ error: "Invalid token" });
    }
  } catch (err) {
    console.error("Verify error:", err.message);
    res.status(401).json({ error: "Unauthorized" });
  }
});

module.exports = router;
