const express = require("express");
const router = express.Router();
const { loginUser } = require("../utils/authClient");

router.post("/", async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password)
    return res.status(400).json({ error: "Username and password required" });

  try {
    const token = await loginUser(username, password);
    res.json(token); // returns { token: "..." }
  } catch (err) {
    if (err.response && err.response.status === 401)
      return res.status(401).json({ error: "Invalid credentials" });
    console.error("Login error:", err.message);
    res.status(500).json({ error: "Auth service unavailable" });
  }
});

module.exports = router;
