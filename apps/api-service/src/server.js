const express = require("express");
const morgan = require("morgan");
const client = require("prom-client");
const routes = require("./routes");
const health = require("./health");
const registerRoute = require("./routes/register");
const loginRoute = require("./routes/login");
const privateRoute = require("./routes/private");
const uploadRoute = require("./routes/upload");
const imageRoute = require("./routes/image");
const imagesRoute = require("./routes/images");

const app = express();
const PORT = process.env.PORT || 3000;

// Prometheus metrics
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

// Custom logging format with timestamp
const logFormat = ':date[iso] [API-SERVICE] :method :url :status :response-time ms - :res[content-length] bytes';

// Use custom morgan format for all requests except health checks
app.use(morgan(logFormat, {
  skip: (req, res) => req.url === '/healthz' || req.url === '/livez'
}));

app.use(express.json());

// Metrics middleware
app.use((req, res, next) => {
  if (req.path === '/metrics') return next();
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route = req.route?.path || req.path;
    httpRequestDuration.labels(req.method, route, res.statusCode).observe(duration);
    httpRequestsTotal.labels(req.method, route, res.statusCode).inc();
  });
  next();
});

// Log startup configuration
console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO: Starting API Service`);
console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO: Configuration:`);
console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO:   Port: ${PORT}`);
console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO:   Auth Service: ${process.env.AUTH_SERVICE_URL || 'not configured'}`);
console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO:   Image Service: ${process.env.IMAGE_SERVICE_URL || 'not configured'}`);
console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO:   Database: ${process.env.DATABASE_URL ? 'configured' : 'not configured'}`);

// Health endpoints for Kubernetes probes
app.get("/healthz", health.readiness);
app.get("/livez", health.liveness);

// Metrics endpoint for Prometheus
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

// Auth endpoints
app.use("/register", registerRoute);
app.use("/login", loginRoute);
app.use("/private", privateRoute);

// Upload endpoint
app.use(uploadRoute);

// Images gallery endpoint - matches /images (for ingress rewrite from /api/images)
app.use("/images", imagesRoute);

// Image retrieval endpoint - matches /images/:filename
app.use(imageRoute);

// Mount API routes
app.use("/api", routes);

app.get("/", (req, res) => {
  console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO: Root endpoint accessed from ${req.ip}`);
  res.json({ service: "api-service", message: "Welcome to Thmanyah API" });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(`[${new Date().toISOString()}] [API-SERVICE] ERROR: ${err.message}`);
  console.error(`[${new Date().toISOString()}] [API-SERVICE] ERROR: Stack: ${err.stack}`);
  res.status(err.status || 500).json({ 
    error: err.message || 'Internal server error',
    path: req.path
  });
});

app.listen(PORT, () => {
  console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO: Server started successfully on port ${PORT}`);
  console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO: Endpoints registered:`);
  console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO:   GET  / - Root endpoint`);
  console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO:   GET  /healthz - Readiness probe`);
  console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO:   GET  /livez - Liveness probe`);
  console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO:   POST /register - User registration`);
  console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO:   POST /login - User login`);
  console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO:   GET  /private - Protected endpoint`);
  console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO:   POST /upload - Image upload`);
  console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO:   GET  /images/:filename - Image retrieval`);
  console.log(`[${new Date().toISOString()}] [API-SERVICE] INFO: Ready to accept connections`);
});
