const axios = require("axios");

const AUTH_URL = process.env.AUTH_SERVICE_URL;

exports.verifyToken = async (token) => {
  return axios.get(`${AUTH_URL}/verify`, {
    headers: { Authorization: token },
    timeout: 2000,
  });
};
