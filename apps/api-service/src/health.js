exports.readiness = (req, res) => {
  // You can later add checks (DB connection, auth ping, etc.)
  res.status(200).json({ status: "ready" });
};

exports.liveness = (req, res) => {
  res.status(200).json({ status: "alive" });
};
