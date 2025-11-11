const express = require("express");
const router = express.Router();
const { loginUser } = require("../utils/authClient");

const log = (level, message) => {
  console.log(`[${new Date().toISOString()}] [API-SERVICE] ${level}: ${message}`);
};

router.post("/", async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    log('WARN', `Login attempt with missing credentials from ${req.ip}`);
    return res.status(400).json({ error: "Username and password required" });
  }

  try {
    log('INFO', `Login attempt for user '${username}' from ${req.ip}`);
    const token = await loginUser(username, password);
    log('INFO', `Successful login for user '${username}' from ${req.ip}`);
    res.json(token); // returns { token: "..." }
  } catch (err) {
    if (err.response && err.response.status === 401) {
      log('WARN', `Failed login attempt for user '${username}' from ${req.ip}: Invalid credentials`);
      return res.status(401).json({ error: "Invalid credentials" });
    }
    log('ERROR', `Login error for user '${username}': ${err.message}`);
    console.error("Login error:", err.message);
    res.status(500).json({ error: "Auth service unavailable" });
  }
});

module.exports = router;
