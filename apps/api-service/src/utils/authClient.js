const axios = require("axios");

const AUTH_URL = process.env.AUTH_SERVICE_URL;

/**
 * Log in a user using the auth-service.
 * This sends username & password to /login
 * and returns a JWT token if valid.
 */
exports.loginUser = async (username, password) => {
  const response = await axios.post(`${AUTH_URL}/login`, { username, password }, { timeout: 3000 });
  return response.data; // { token: "..." }
};

/**
 * Verify JWT token via auth-service.
 * Returns { valid: "true" } or throws 401 if invalid.
 */
exports.verifyToken = async (token) => {
  const response = await axios.get(`${AUTH_URL}/verify`, {
    headers: { Authorization: token },
    timeout: 2000,
  });
  return response.data;
};
