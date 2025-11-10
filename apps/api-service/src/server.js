const express = require("express");
const morgan = require("morgan");
const routes = require("./routes");
const health = require("./health");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(morgan("dev"));
app.use(express.json());

// Health endpoints for Kubernetes probes
app.get("/healthz", health.readiness);
app.get("/livez", health.liveness);

// Mount routes
app.use("/api", routes);

app.get("/", (req, res) => {
  res.json({ service: "api-service", message: "Welcome to Thmanyah API" });
});

app.listen(PORT, () => console.log(`🚀 API Service listening on port ${PORT}`));
