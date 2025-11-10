const express = require("express");
const morgan = require("morgan");
const routes = require("./routes");
const health = require("./health");
const registerRoute = require("./routes/register");
const loginRoute = require("./routes/login");
const privateRoute = require("./routes/private");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(morgan("dev"));
app.use(express.json());

// Health endpoints for Kubernetes probes
app.get("/healthz", health.readiness);
app.get("/livez", health.liveness);

// Auth endpoints
app.use("/register", registerRoute);
app.use("/login", loginRoute);
app.use("/private", privateRoute);

// Mount API routes
app.use("/api", routes);

app.get("/", (req, res) => {
  res.json({ service: "api-service", message: "Welcome to Thmanyah API" });
});

app.listen(PORT, () => console.log(`🚀 API Service listening on port ${PORT}`));
