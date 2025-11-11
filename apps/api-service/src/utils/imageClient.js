const axios = require("axios");

const IMAGE_URL = process.env.IMAGE_SERVICE_URL;

exports.listImages = async (token) => {
  return axios.get(`${IMAGE_URL}/list`, { 
    headers: { Authorization: token },
    timeout: 2000 
  });
};

exports.uploadImage = async (payload) => {
  return axios.post(`${IMAGE_URL}/upload`, payload, { timeout: 2000 });
};
